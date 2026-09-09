import Foundation
import AppKit
import NotifyCore

let args = Array(CommandLine.arguments.dropFirst())
#if DEBUG
if args.first == "render-previews", args.count == 2 {
    _ = NSApplication.shared
    do { try PreviewRenderer.render(to: args[1]); exit(0) } catch { stderr(error.localizedDescription); exit(1) }
}
#endif
if args.first == "mcp" { runMCP() }
else if args.first == "serve" {
    do {
        let service = NotifyService(store: try Store(paths: NotifyPaths()))
        let server = try SocketServer(paths: service.store.paths, handler: service.handle)
        try service.start(); server.start()
        stderr("AgentNotify headless service ready at \(service.store.paths.socket)")
        let stopSignals: [DispatchSourceSignal] = [SIGTERM, SIGINT, SIGHUP].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { server.stop(); service.stop(); exit(0) }; source.resume(); return source
        }
        withExtendedLifetime((server, service, stopSignals)) { RunLoop.main.run() }
    } catch { stderr(error.localizedDescription); exit(4) }
} else if args.first == "app" || (args.isEmpty && URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "AgentNotify") {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate; app.setActivationPolicy(ProcessInfo.processInfo.environment["AGENTNOTIFY_PREVIEW"] == "1" ? .regular : .accessory)
    withExtendedLifetime(delegate) { app.run() }
} else { exit(runCLI(args)) }
