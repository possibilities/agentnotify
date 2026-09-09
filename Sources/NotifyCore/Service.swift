import Foundation

public final class NotifyService {
    public let store: Store
    private let shim: NotificationShim
    public var onChange: (() -> Void)?
    public var onShow: ((String?, Bool?) -> Void)?
    public var onShowPreferences: (() -> Void)?
    public weak var interfaceController: NotifyInterfaceController?
    public var onPreferencesChange: (() -> Void)?
    public var nativeInfo: (() -> [String: Any])?
    public var nativeList: ((Bool) throws -> Set<String>)?
    private var timer: DispatchSourceTimer?
    public init(store: Store, shim: NotificationShim = NotificationShim()) { self.store = store; self.shim = shim }
    public func start() throws {
        try store.recoverEffects()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            do { let before = try self.store.cursor(); try self.store.tick(); if try self.store.cursor() != before { self.onChange?() } }
            catch { FileHandle.standardError.write(Data("AgentNotify: \(error.localizedDescription)\n".utf8)) }
        }
        self.timer = timer; timer.resume()
    }
    public func stop() { timer?.cancel(); timer = nil }
    deinit { stop() }
    public func handle(_ request: [String: Any]) -> [String: Any] {
        do {
            guard let method = request["method"] as? String, let params = request["params"] as? [String: Any] else { throw NotifyError("invalid_request", "Expected method and params object.") }
            return JSON.success(try call(method, params))
        } catch { return JSON.failure(error) }
    }
    public func call(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        try Catalog.validate(method, params)
        if method == "shimStatus" {
            var result = shim.status(); result["promptHandled"] = try store.shimPromptHandled(); return result
        }
        if method == "installShim" {
            var result = try shim.install()
            _ = try store.perform("dismissShimSetup", params: [:])
            result["promptHandled"] = true
            onPreferencesChange?()
            return result
        }
        if method == "showPreferences" {
            if let interfaceController {
                let state = try interfaceController.performInterface("uiShow", params: ["surface": "preferences"])
                return ["shown": true, "state": state]
            }
            guard let onShowPreferences else { throw NotifyError("native_unavailable", "This is a headless service. Open AgentNotify.app to use preferences.") }
            onShowPreferences(); return ["shown": true]
        }
        if method == "show" {
            if let id = params["id"] as? String { _ = try store.get(id) }
            if let interfaceController {
                var ui: [String: Any] = ["surface": "inbox"]
                if let id = params["id"] { ui["id"] = id }
                if let detached = params["detached"] { ui["pinned"] = detached }
                let state = try interfaceController.performInterface("uiShow", params: ui)
                return ["shown": true, "state": state]
            }
            guard let onShow else { throw NotifyError("native_unavailable", "This is a headless service. Open AgentNotify.app to use the inbox.") }
            onShow(params["id"] as? String, params["detached"] as? Bool); return ["shown": true]
        }
        if method.hasPrefix("ui") {
            guard let interfaceController else { throw NotifyError("native_unavailable", "This is a headless service. Open AgentNotify.app to control its native interface.") }
            return try interfaceController.performInterface(method, params: params)
        }
        if method == "list", let filter = params["filter"] as? String, ["delivered", "pending"].contains(filter), let nativeList {
            let ids = try nativeList(filter == "pending")
            let query = params["query"] as? String ?? ""
            let items = try store.all().filter { ids.contains($0.id) && (params["group"] == nil || $0.group == params["group"] as? String) && $0.createdAt >= (params["since"] as? Double ?? 0) && $0.createdAt < (params["before"] as? Double ?? .greatestFiniteMagnitude) && (query.isEmpty || [$0.title, $0.subtitle, $0.message, $0.group].joined(separator: " ").localizedCaseInsensitiveContains(query)) }.sorted { filter == "pending" ? ($0.snoozedUntil ?? $0.scheduledAt ?? 0) < ($1.snoozedUntil ?? $1.scheduledAt ?? 0) : $0.createdAt > $1.createdAt }
            let offset = params["offset"] as? Int ?? 0, limit = params["limit"] as? Int ?? 100
            let page = try JSON.boundedPage(items.dropFirst(offset).prefix(limit).map { try JSON.encode($0) })
            return ["items": page, "total": items.count, "cursor": try store.cursor(), "hasMore": offset + page.count < items.count]
        }
        var result = try store.perform(method, params: params)
        if method == "send", nativeInfo == nil, let id = result["id"] as? String { try store.updateDelivery(id: id, state: "inbox-only", error: result["deliveryError"] as? String, registered: false); result = try JSON.encode(store.get(id)) }
        if method == "diagnose" { result["native"] = nativeInfo?() ?? ["available": false, "authorization": "headless", "note": "Durable inbox works; this service does not deliver system notifications."] }
        let claim = result.removeValue(forKey: "effectClaim") as? Bool ?? false
        if ["setPreferences", "dismissShimSetup"].contains(method) { onPreferencesChange?() }
        else if method != "heartbeat", Catalog.operations.first(where: { $0.name == method })?.mutates == true { onChange?() }
        if claim {
            let item = try JSON.decode(NotificationRecord.self, result)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let error = Self.execute(item)
                do { try self?.store.finishEffect(id: item.id, error: error); self?.onChange?() }
                catch { FileHandle.standardError.write(Data("AgentNotify: \(error.localizedDescription)\n".utf8)) }
            }
        }
        return result
    }
    private static func execute(_ item: NotificationRecord) -> String? {
        var errors: [String] = []
        var commands: [(String, [String])] = []
        if let bundle = item.activate { commands.append(("/usr/bin/open", ["-b", bundle])) }
        if let command = item.execute { commands.append(("/bin/sh", ["-c", command])) }
        if let url = item.open { commands.append(("/usr/bin/open", [url])) }
        for (binary, args) in commands {
            let process = Process(); process.executableURL = URL(fileURLWithPath: binary); process.arguments = args
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            do { try process.run(); process.waitUntilExit(); if process.terminationStatus != 0 { errors.append("\(URL(fileURLWithPath: binary).lastPathComponent) exited \(process.terminationStatus).") } }
            catch { errors.append(error.localizedDescription) }
        }
        return errors.isEmpty ? nil : errors.joined(separator: " ")
    }
}
