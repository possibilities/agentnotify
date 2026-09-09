import AppKit
import UserNotifications
import NotifyCore

final class NativeNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let service: NotifyService
    private let infoLock = NSLock()
    private var info: [String: Any] = ["available": true, "authorization": "checking"]
    private var authorization: UNAuthorizationStatus = .notDetermined
    private var registering = Set<String>()
    var onAuthorization: ((String) -> Void)?
    init(service: NotifyService) {
        self.service = service; super.init(); center.delegate = self
        service.nativeInfo = { [weak self] in self?.diagnostics() ?? [:] }
        service.nativeList = { [weak self] pending in try self?.nativeIDs(pending: pending) ?? [] }
    }
    func diagnostics() -> [String: Any] { infoLock.lock(); defer { infoLock.unlock() }; return info }
    func refreshSettings(retryDenied: Bool = false) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorization = settings.authorizationStatus
                let name: String
                switch settings.authorizationStatus { case .authorized: name = "authorized"; case .denied: name = "denied"; case .provisional: name = "provisional"; case .notDetermined: name = "not-determined"; default: name = "unknown" }
                self.infoLock.lock(); self.info = ["available": true, "authorization": name, "alerts": settings.alertSetting.rawValue, "sound": settings.soundSetting.rawValue, "notificationCenter": settings.notificationCenterSetting.rawValue, "note": "Accepted delivery does not prove banner visibility; Focus and macOS settings still apply."]; self.infoLock.unlock()
                self.onAuthorization?(name)
                if retryDenied && [.authorized, .provisional].contains(settings.authorizationStatus), let items = try? self.service.store.all() {
                    for item in items where item.delivery == "denied" && ["active", "scheduled", "snoozed"].contains(item.status) {
                        try? self.service.store.updateDelivery(id: item.id, state: "pending", registered: false)
                    }
                }
                self.reconcile()
            }
        }
    }
    func enable() {
        if authorization != .notDetermined {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        } else {
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in self.refreshSettings(retryDenied: true) }
        }
    }
    func nativeIDs(pending: Bool) throws -> Set<String> {
        let semaphore = DispatchSemaphore(value: 0)
        var result = Set<String>()
        if pending { center.getPendingNotificationRequests { values in result = Set(values.map(\.identifier)); semaphore.signal() } }
        else { center.getDeliveredNotifications { values in result = Set(values.map { $0.request.identifier }); semaphore.signal() } }
        guard semaphore.wait(timeout: .now() + 5) == .success else { throw NotifyError("native_unavailable", "System notification query timed out. Retry after checking macOS notification settings.", exitCode: 4) }
        return result
    }
    func reconcile() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let items = try? service.store.all() else { return }
        let eligible = items.filter { ["active", "scheduled", "snoozed"].contains($0.status) && $0.presentable }
        let categories = Set(eligible.filter { $0.interactive && $0.response == nil }.map { item -> UNNotificationCategory in
            var actions: [UNNotificationAction] = []
            if let placeholder = item.reply { actions.append(UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: placeholder)) }
            actions += item.actions.prefix(max(0, 10 - actions.count)).enumerated().map { UNNotificationAction(identifier: "action-\($0.offset)", title: $0.element, options: []) }
            return UNNotificationCategory(identifier: item.id, actions: actions, intentIdentifiers: [], options: [.customDismissAction])
        })
        center.setNotificationCategories(categories)
        let eligibleIDs = Set(eligible.map(\.id))
        let removeIDs = items.filter { !eligibleIDs.contains($0.id) }.map(\.id)
        center.removeDeliveredNotifications(withIdentifiers: removeIDs)
        center.removePendingNotificationRequests(withIdentifiers: removeIDs)
        for item in eligible where !item.nativeRegistered && item.delivery == "pending" && !registering.contains(item.id) {
            guard [.authorized, .provisional].contains(authorization) else {
                if diagnostics()["authorization"] as? String == "checking" { continue }
                try? service.store.updateDelivery(id: item.id, state: "denied", error: "Enable notifications to show system banners. This item is saved in your inbox.", registered: false)
                service.onChange?(); continue
            }
            registering.insert(item.id)
            let content = UNMutableNotificationContent()
            content.title = item.title; content.subtitle = item.subtitle; content.body = item.message
            content.threadIdentifier = item.group; content.categoryIdentifier = item.id
            content.userInfo = ["notificationId": item.id]
            if let sound = item.sound { content.sound = sound == "default" ? .default : UNNotificationSound(named: UNNotificationSoundName(sound)) }
            if item.timeSensitive { content.interruptionLevel = .timeSensitive }
            var warning: String? = item.deliveryError
            if let path = item.contentImage {
                do {
                    let source = URL(string: path)?.isFileURL == true ? URL(string: path)! : URL(fileURLWithPath: path)
                    let directory = service.store.paths.root.appendingPathComponent("attachments/\(item.id)")
                    let original = directory.appendingPathComponent("original").appendingPathExtension(source.pathExtension)
                    let durableSource = FileManager.default.fileExists(atPath: original.path) ? original : source
                    let attributes = try FileManager.default.attributesOfItem(atPath: durableSource.path)
                    guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 20_000_000 else { throw NotifyError("invalid_argument", "Attachment must be a regular image under 20 MB.") }
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    if !FileManager.default.fileExists(atPath: original.path) { try FileManager.default.copyItem(at: source, to: original); chmod(original.path, 0o600) }
                    let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
                    try FileManager.default.copyItem(at: original, to: destination); chmod(destination.path, 0o600)
                    content.attachments = [try UNNotificationAttachment(identifier: "image", url: destination, options: nil)]
                } catch { warning = "Image unavailable: \(error.localizedDescription)" }
            }
            let due = item.snoozedUntil ?? item.scheduledAt
            if due != nil { center.removeDeliveredNotifications(withIdentifiers: [item.id]) }
            let trigger: UNNotificationTrigger? = due.flatMap { $0 > Date().timeIntervalSince1970 ? UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0 - Date().timeIntervalSince1970), repeats: false) : nil }
            center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)) { error in
                DispatchQueue.main.async {
                    self.registering.remove(item.id)
                    try? self.service.store.updateDelivery(id: item.id, state: error == nil ? "accepted" : "failed", error: error?.localizedDescription ?? warning, registered: error == nil)
                    self.service.onChange?()
                }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list, .sound]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        try? service.store.tick()
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier, (try? service.store.get(id).response) != nil {
            _ = try? service.call("show", ["id": id]); completionHandler(); return
        }
        var params: [String: Any] = ["id": id, "requestId": UUID().uuidString]
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: params["kind"] = "body"
        case UNNotificationDismissActionIdentifier: params["kind"] = "close"
        case "reply": params["kind"] = "reply"; params["value"] = (response as? UNTextInputNotificationResponse)?.userText ?? ""
        default: params["kind"] = "action"; params["actionIndex"] = Int(response.actionIdentifier.replacingOccurrences(of: "action-", with: "")) ?? -1
        }
        do { _ = try service.call("respond", params) } catch { stderr("Native response: \(error.localizedDescription)") }
        completionHandler()
    }
}
