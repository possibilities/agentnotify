#if DEBUG
import AppKit
import SwiftUI
import NotifyCore

// Render the production view without changing system appearance or the live inbox.
enum PreviewRenderer {
    static func render(to directory: String) throws {
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("an-render-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(paths: NotifyPaths(root: root)), model = InboxModel()
        model.service = NotifyService(store: store); model.authorization = "authorized"
        let now = Date().timeIntervalSince1970
        let samples: [[String: Any]] = [
            ["title": "Build finished", "message": "All checks passed. The app is ready for a closer look.", "group": "agentnotify:build", "execute": "/usr/bin/true"],
            ["title": "One detail before we continue", "message": "What should the next milestone focus on?", "group": "planning", "reply": "Your thoughts…"],
            ["title": "Choose the next step", "message": "The release checks passed. How would you like to proceed?", "group": "release", "actions": ["Review Changes", "Keep Working", "Defer"]],
            ["title": "Your research is ready", "message": "Three useful findings on native app design, with sources saved to the wiki.", "group": "design", "actions": ["Read Findings"]],
            ["title": "A quieter notification inbox", "message": "Every notification stays until you’re done. Read it, act on it, or come back later.", "group": "agentnotify"]
        ]
        for (index, sample) in samples.enumerated() { _ = try store.perform("send", params: sample, now: now - Double(index + 1) * 180) }
        model.refresh()
        let controller = NSHostingController(rootView: InboxView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 680), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = controller
        for theme in ["light", "dark"] {
            window.appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)
            model.filter = "inbox"; model.group = nil; model.query = ""; model.searchVisible = false; model.selected = nil; model.detached = false
            try capture(window, output.appendingPathComponent("\(theme)-inbox.png"), width: 440, height: 680)
            model.selected = model.items.first?.id; model.detached = true
            try capture(window, output.appendingPathComponent("\(theme)-detached.png"), width: 440, height: 680)
            model.filter = "all"; model.searchVisible = true; model.query = "no matching notification"
            try capture(window, output.appendingPathComponent("\(theme)-empty-search.png"), width: 360, height: 500)
        }
        window.close()
        stdout("Rendered native inbox views to \(output.path)\n")
    }
    static func capture(_ window: NSWindow, _ destination: URL, width: CGFloat, height: CGFloat) throws {
        window.setContentSize(NSSize(width: width, height: height))
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NotifyError("internal_error", "Cannot create native view snapshot.") }
        view.cacheDisplay(in: view.bounds, to: image)
        guard let data = image.representation(using: .png, properties: [:]) else { throw NotifyError("internal_error", "Cannot encode native view snapshot.") }
        try data.write(to: destination)
    }
}
#endif
