import Foundation

public struct NotifyError: Error, LocalizedError {
    public let code: String
    public let message: String
    public let exitCode: Int32
    public init(_ code: String, _ message: String, exitCode: Int32 = 2) {
        self.code = code; self.message = message; self.exitCode = exitCode
    }
    public var errorDescription: String? { message }
}

public enum JSON {
    public static func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]) }
    public static func string(_ object: Any) -> String { (try? String(data: data(object), encoding: .utf8)) ?? "null" }
    public static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NotifyError("invalid_request", "Expected a JSON object.") }
        return value
    }
    public static func encode<T: Encodable>(_ value: T) throws -> [String: Any] { try object(JSONEncoder().encode(value)) }
    public static func decode<T: Decodable>(_ type: T.Type, _ value: [String: Any]) throws -> T { try JSONDecoder().decode(type, from: data(value)) }
    public static func boundedPage(_ values: [[String: Any]]) throws -> [[String: Any]] {
        var result: [[String: Any]] = [], size = 0
        for value in values { let bytes = try data(value).count; if !result.isEmpty && size + bytes > 750_000 { break }; result.append(value); size += bytes }
        return result
    }
    public static func success(_ value: Any) -> [String: Any] { ["schema_version": 1, "ok": true, "error": NSNull(), "data": value] }
    public static func failure(_ error: Error) -> [String: Any] {
        let e = error as? NotifyError ?? NotifyError("internal_error", error.localizedDescription, exitCode: 5)
        return ["schema_version": 1, "ok": false, "data": NSNull(), "error": ["code": e.code, "message": e.message, "exit_code": e.exitCode]]
    }
}

public struct NotificationRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var message: String
    public var group: String
    public var actions: [String]
    public var reply: String?
    public var execute: String?
    public var open: String?
    public var activate: String?
    public var sound: String?
    public var contentImage: String?
    public var timeSensitive: Bool
    public var createdAt: Double
    public var updatedAt: Double
    public var scheduledAt: Double?
    public var snoozedUntil: Double?
    public var deadline: Double?
    public var readAt: Double?
    public var status: String
    public var revision: Int
    public var response: Response?
    public var delivery: String
    public var deliveryError: String?
    public var nativeRegistered: Bool
    public var presentable: Bool = true
    public var hasBodyAction: Bool { execute != nil || open != nil || activate != nil }
    public var interactive: Bool { !actions.isEmpty || reply != nil }
    public var canRespond: Bool { response == nil && status == "active" }
    public var isInbox: Bool { status == "active" }
}

public struct Response: Codable, Equatable {
    public var kind: String
    public var value: String
    public var exitCode: Int32
    public var at: Double
    public var effect: String?
    public var error: String?
}

public struct NotifyPaths {
    public let root: URL
    public var database: URL { root.appendingPathComponent("notifications.sqlite") }
    public var socket: String { root.appendingPathComponent("notify.sock").path }
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let path = environment["AGENTNOTIFY_STATE_DIR"] { root = URL(fileURLWithPath: path) }
        else {
            let base = environment["XDG_STATE_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state").path
            root = URL(fileURLWithPath: base).appendingPathComponent("agentnotify")
        }
    }
    public init(root: URL) { self.root = root }
    public func prepare() throws {
        var statbuf = stat()
        if lstat(root.path, &statbuf) == 0 {
            guard statbuf.st_mode & S_IFMT == S_IFDIR, statbuf.st_uid == getuid() else { throw NotifyError("unsafe_path", "State directory must be a real directory owned by your account.") }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(root.path, 0o700)
    }
}

public enum Schedule {
    public static func duration(_ text: String) throws -> Double {
        let suffix = text.last.map(String.init) ?? ""
        let multiplier: Double = ["s": 1, "m": 60, "h": 3600, "d": 86400][suffix] ?? 1
        let number = multiplier != 1 || suffix == "s" ? String(text.dropLast()) : text
        guard let value = Double(number), value.isFinite, value > 0, value * multiplier <= 315_576_000 else { throw NotifyError("invalid_argument", "Duration must be positive seconds or a number followed by s, m, h, or d (at most 10 years).") }
        return value * multiplier
    }
    public static func date(_ text: String, now: Date = Date()) throws -> Date {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.isLenient = false
        if text.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil {
            let parts = text.split(separator: ":").compactMap { Int($0) }
            guard parts[0] < 24, parts[1] < 60, let date = Calendar.current.nextDate(after: now, matching: DateComponents(hour: parts[0], minute: parts[1], second: 0), matchingPolicy: .nextTime) else { throw NotifyError("invalid_argument", "Invalid local clock time.") }
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = formatter.date(from: text.replacingOccurrences(of: "T", with: " ")), date > now else { throw NotifyError("invalid_argument", "Use a future local date YYYY-MM-DD HH:mm or clock time HH:mm.") }
        return date
    }
}
