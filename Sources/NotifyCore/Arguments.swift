import Foundation

public struct Invocation {
    public var method: String = "send"
    public var params: [String: Any] = [:]
    public var legacy = false
    public var removeFirst: String?
    public var warnings: [String] = []
    public init() {}
}
public enum Arguments {
    public static func parse(_ args: [String], stdin: String? = nil) throws -> Invocation {
        var result = Invocation()
        if args.first == "api" {
            guard args.count == 3 else { throw NotifyError("invalid_argument", "Usage: agentnotify api METHOD '{...}'") }
            result.method = args[1]; result.params = try JSON.object(Data(args[2].utf8)); try Catalog.validate(result.method, result.params); return result
        }
        var tokens = args
        if let first = tokens.first, Catalog.operations.contains(where: { $0.name == first }) { result.method = tokens.removeFirst() }
        else { result.legacy = true }
        if result.legacy {
            var i = 0, actions: [String] = []
            let valued = ["message", "title", "subtitle", "group", "sound", "contentImage", "execute", "open", "activate", "timeout", "in", "at", "action", "list", "remove", "sender", "appIcon"]
            while i < tokens.count {
                let flag = tokens[i]; i += 1
                guard flag.hasPrefix("-") else { throw NotifyError("invalid_argument", "Unexpected argument: \(flag).") }
                let key = String(flag.drop(while: { $0 == "-" }))
                if key == "json" { continue }
                if key == "diagnose" { result.method = "diagnose"; continue }
                if key == "ignoreDnD" { result.params[key] = true; continue }
                if key == "reply" {
                    if i < tokens.count && !tokens[i].hasPrefix("-") { result.params[key] = unescape(tokens[i]); i += 1 }
                    else { result.params[key] = "" }
                    continue
                }
                guard valued.contains(key), i < tokens.count else { throw NotifyError("invalid_argument", "Unknown flag or missing value: \(flag).") }
                let value = unescape(tokens[i]); i += 1
                switch key {
                case "action": actions += value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                case "list": result.method = "list"; result.params["filter"] = value == "PENDING" ? "pending" : "delivered"; if value != "ALL" && value != "PENDING" { result.params["group"] = value }
                case "remove": result.removeFirst = value
                case "sender", "appIcon": result.warnings.append("-\(key) is ignored, matching terminal-notifier 3; AgentNotify owns its native identity.")
                case "timeout":
                    guard let number = Double(value), number.isFinite, number > 0 else { throw NotifyError("invalid_argument", "-timeout must be positive seconds.") }; result.params[key] = number
                default: result.params[key] = value
                }
            }
            if !actions.isEmpty { result.params["actions"] = actions }
            if result.method == "diagnose" { result.params = [:]; result.removeFirst = nil; return result }
            if result.method == "list" {
                result.params = result.params.filter { ["filter", "group"].contains($0.key) }; return result
            }
            if result.params["message"] == nil, result.removeFirst == nil, let stdin { result.params["message"] = stdin.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n")) }
            if result.params["message"] == nil, let group = result.removeFirst { result.method = "remove"; result.params = ["group": group]; result.removeFirst = nil }
        } else {
            guard let operation = Catalog.operations.first(where: { $0.name == result.method }) else { throw NotifyError("unknown_method", "Unknown operation.") }
            var i = 0
            while i < tokens.count {
                let token = tokens[i]; i += 1
                if token == "--json" { continue }
                guard token.hasPrefix("--") else { throw NotifyError("invalid_argument", "Use named --arguments; got \(token).") }
                let split = String(token.dropFirst(2)).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(split[0])
                guard let p = operation.parameters.first(where: { $0.name == key }) else { throw NotifyError("invalid_argument", "Unknown argument --\(key).") }
                let value: String
                if split.count == 2 { value = String(split[1]) }
                else if p.type == "boolean" && (i == tokens.count || tokens[i].hasPrefix("--")) { value = "true" }
                else { guard i < tokens.count else { throw NotifyError("invalid_argument", "Missing value for --\(key).") }; value = tokens[i]; i += 1 }
                switch p.type {
                case "string": result.params[key] = value
                case "array": guard let array = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String] else { throw NotifyError("invalid_argument", "--\(key) requires a JSON string array.") }; result.params[key] = array
                case "integer": guard let integer = Int(value) else { throw NotifyError("invalid_argument", "--\(key) requires an integer.") }; result.params[key] = integer
                case "number": guard let number = Double(value) else { throw NotifyError("invalid_argument", "--\(key) requires a number.") }; result.params[key] = number
                case "boolean": guard ["true", "false"].contains(value) else { throw NotifyError("invalid_argument", "--\(key) requires true or false.") }; result.params[key] = value == "true"
                default: break
                }
            }
        }
        if result.method == "send", let path = result.params["contentImage"] as? String {
            if let url = URL(string: path), url.isFileURL { result.params["contentImage"] = url.path }
            else if !path.hasPrefix("/") { result.params["contentImage"] = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path).standardized.path }
        }
        if result.method == "send", result.params["message"] == nil { throw NotifyError("invalid_argument", "Provide -message TEXT or pipe a UTF-8 message.", exitCode: 1) }
        try Catalog.validate(result.method, result.params)
        return result
    }
    private static func unescape(_ text: String) -> String { text.hasPrefix("\\") ? String(text.dropFirst()) : text }
    public static func tsv(_ records: [NotificationRecord], pending: Bool) -> String {
        guard !records.isEmpty else { return "" }
        func field(_ text: String) -> String { text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") }
        let header = "GroupID\tTitle\tSubtitle\tMessage\t" + (pending ? "Scheduled For" : "Delivered At")
        return ([header] + records.map { item in [item.group, item.title, item.subtitle, item.message, Date(timeIntervalSince1970: pending ? (item.snoozedUntil ?? item.scheduledAt ?? item.createdAt) : item.createdAt).description].map(field).joined(separator: "\t") }).joined(separator: "\n") + "\n"
    }
}
