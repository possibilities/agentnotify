import Foundation
import AppKit
import NotifyCore

private var interrupted = false
private func onSignal(_ signal: Int32) { interrupted = true }
func stderr(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
func stdout(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }

final class RuntimeClient {
    let client = SocketClient(path: NotifyPaths().socket)
    func ensureRunning() throws {
        if (try? client.result("diagnose")) != nil { return }
        let env = ProcessInfo.processInfo.environment
        guard env["AGENTNOTIFY_NO_LAUNCH"] != "1", env["AGENTNOTIFY_STATE_DIR"] == nil else { throw NotifyError("service_unavailable", "No service at \(client.path). Start the isolated service with agentnotify serve.", exitCode: 4) }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundled = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [env["AGENTNOTIFY_APP_PATH"], bundled.pathExtension == "app" ? bundled.path : nil, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/AgentNotify.app").path].compactMap { $0 }
        guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { throw NotifyError("service_unavailable", "Build or install AgentNotify.app first. Run scripts/build.sh, then open dist/AgentNotify.app.", exitCode: 4) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = ["-g", app]; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline { if (try? client.result("diagnose")) != nil { return }; Thread.sleep(forTimeInterval: 0.1) }
        throw NotifyError("service_unavailable", "AgentNotify did not become ready. Open the app and inspect its error.", exitCode: 4)
    }
}

func runCLI(_ args: [String]) -> Int32 {
    if args.contains("-help") || args.contains("--help") || args.contains("--agent-help") { stdout(Catalog.help); return 0 }
    if args.contains("--agent-teaser") { stdout("agentnotify: durable macOS notification inbox; terminal-notifier CLI, socket API, and MCP.\n"); return 0 }
    if args.contains("-version") { stdout("terminal-notifier 3.1.0.\n"); return 0 }
    if args.contains("--version") { stdout("agentnotify \(Catalog.version)\n"); return 0 }
    if args.first == "guide" { stdout(JSON.string(Catalog.contract) + "\n"); return 0 }
    let legacy = args.first?.hasPrefix("-") ?? true
    do {
        var input: String?
        if !args.contains("-message"), !args.contains("-list"), !args.contains("-remove"), (args.isEmpty || legacy), isatty(STDIN_FILENO) == 0 {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let decoded = String(data: data, encoding: .utf8) else { throw NotifyError("invalid_argument", "stdin must contain UTF-8 text.") }; input = decoded
        }
        var invocation = try Arguments.parse(args, stdin: input)
        invocation.warnings.forEach(stderr)
        let runtime = RuntimeClient(); try runtime.ensureRunning()
        let client = runtime.client
        if let group = invocation.removeFirst, invocation.method == "send" { invocation.params["remove"] = group }
        let waiter = UUID().uuidString
        if invocation.legacy && invocation.method == "send" && (invocation.params["actions"] != nil || invocation.params["reply"] != nil) { invocation.params["waiterId"] = waiter }
        if Catalog.operations.first(where: { $0.name == invocation.method })?.parameters.contains(where: { $0.name == "requestId" }) == true, invocation.params["requestId"] == nil { invocation.params["requestId"] = UUID().uuidString.lowercased() }
        var data = try client.result(invocation.method, invocation.params)
        if !invocation.legacy { stdout(JSON.string(JSON.success(data)) + "\n"); return 0 }
        if invocation.method == "diagnose" { stdout(JSON.string(JSON.success(data)) + "\n"); return 0 }
        if invocation.method == "list" {
            var records: [NotificationRecord] = []
            while true {
                records += try (data["items"] as? [[String: Any]] ?? []).map { try JSON.decode(NotificationRecord.self, $0) }
                if data["hasMore"] as? Bool != true { break }
                var next = invocation.params; next["offset"] = records.count; data = try client.result("list", next)
            }
            stdout(Arguments.tsv(records, pending: invocation.params["filter"] as? String == "pending")); return 0
        }
        if invocation.method == "remove" { stderr("Removed \((data["removed"] as? [String])?.count ?? 0) notification(s); history retained."); return 0 }
        guard invocation.method == "send" else { return 0 }
        var item = try JSON.decode(NotificationRecord.self, data)
        let registrationDeadline = Date().addingTimeInterval(10)
        while item.delivery == "pending" && Date() < registrationDeadline {
            if item.interactive { _ = try? client.result("heartbeat", ["id": item.id, "waiterId": waiter]) }
            Thread.sleep(forTimeInterval: 0.05); item = try JSON.decode(NotificationRecord.self, client.result("get", ["id": item.id]))
        }
        if ["denied", "failed", "pending"].contains(item.delivery), item.interactive { _ = try? client.result("respond", ["id": item.id, "kind": "interrupt"]) }
        if item.delivery == "denied" { stderr("Optional macOS banners are off. Saved to AgentNotify as \(item.id)."); return 3 }
        if item.delivery == "failed" { stderr("Native delivery failed: \(item.deliveryError ?? "unknown error"). Saved as \(item.id)."); return 5 }
        if item.delivery == "pending" { stderr("Native registration timed out. Saved to inbox as \(item.id)."); return 4 }
        if item.delivery == "inbox-only" { stderr("Saved to the headless inbox; system notifications are unavailable.") }
        if let error = item.deliveryError { stderr(error) }
        if let due = item.scheduledAt { stderr("Scheduled for \(Date(timeIntervalSince1970: due))."); return 0 }
        guard item.interactive else { return 0 }
        signal(SIGINT, onSignal); signal(SIGTERM, onSignal); signal(SIGHUP, onSignal)
        var nextHeartbeat = Date.distantPast
        while true {
            if Date() >= nextHeartbeat { _ = try? client.result("heartbeat", ["id": item.id, "waiterId": waiter]); nextHeartbeat = Date().addingTimeInterval(1) }
            if interrupted {
                _ = try? client.result("respond", ["id": item.id, "kind": "interrupt", "requestId": UUID().uuidString]); return 6
            }
            item = try JSON.decode(NotificationRecord.self, client.result("get", ["id": item.id]))
            if let response = item.response, response.effect != "running" {
                if response.kind != "interrupt", !(response.kind == "body" && item.hasBodyAction) { stdout(response.value + "\n") }
                if let error = response.error { stderr(error) }
                return response.exitCode
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    } catch {
        let e = error as? NotifyError ?? NotifyError("internal_error", error.localizedDescription, exitCode: 5)
        if !legacy { stdout(JSON.string(JSON.failure(e)) + "\n") }
        stderr(e.message); return e.exitCode
    }
}

func runMCP() {
    let runtime = RuntimeClient()
    while let line = readLine(strippingNewline: true) {
        var id: Any = NSNull()
        do {
            guard line.utf8.count <= 1_048_576 else { throw NotifyError("invalid_request", "MCP request exceeds 1 MiB.") }
            let request = try JSON.object(Data(line.utf8)); id = request["id"] ?? NSNull()
            guard let method = request["method"] as? String else { throw NotifyError("invalid_request", "Missing method.") }
            if method.hasPrefix("notifications/") { continue }
            var result: [String: Any]
            switch method {
            case "initialize":
                let params = request["params"] as? [String: Any] ?? [:]
                let requested = params["protocolVersion"] as? String ?? "2025-06-18"
                result = ["protocolVersion": ["2024-11-05", "2025-03-26", "2025-06-18"].contains(requested) ? requested : "2025-06-18", "serverInfo": ["name": "agentnotify", "version": Catalog.version], "capabilities": ["tools": [:]], "instructions": Catalog.guidance]
            case "ping": result = [:]
            case "tools/list": result = ["tools": Catalog.tools]
            case "tools/call":
                let params = request["params"] as? [String: Any] ?? [:]
                let name = params["name"] as? String ?? ""
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                let envelope: [String: Any]
                do { try Catalog.validate(name, arguments); try runtime.ensureRunning(); var response = try runtime.client.call(name, arguments); response.removeValue(forKey: "id"); envelope = response }
                catch { envelope = JSON.failure(error) }
                result = ["content": [["type": "text", "text": JSON.string(envelope)]], "structuredContent": envelope, "isError": envelope["ok"] as? Bool != true]
            default:
                stdout(JSON.string(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]]) + "\n"); continue
            }
            stdout(JSON.string(["jsonrpc": "2.0", "id": id, "result": result]) + "\n")
        } catch { stdout(JSON.string(["jsonrpc": "2.0", "id": id, "error": ["code": -32700, "message": error.localizedDescription]]) + "\n") }
    }
}
