import AppKit
import SwiftUI
import NotifyCore

final class InboxPanel: NSPanel { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var panel: InboxPanel?
    private var controller: NSViewController!
    private var server: SocketServer?
    private var service: NotifyService?
    private var native: NativeNotifications?
    private let model = InboxModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let service = NotifyService(store: try Store(paths: NotifyPaths()))
            let server = try SocketServer(paths: service.store.paths, handler: service.handle)
            self.service = service; self.server = server; model.service = service
            let native = NativeNotifications(service: service); self.native = native
            native.onAuthorization = { [weak self] in self?.model.authorization = $0 }
            service.onChange = { [weak self] in DispatchQueue.main.async { self?.model.refresh(); self?.native?.reconcile() } }
            service.onShow = { [weak self] id, detached in DispatchQueue.main.async {
                guard let self else { return }
                self.model.reveal(id)
                if let detached, detached != self.model.detached { self.toggleDetached() }
                self.show()
            } }
            model.onDetach = { [weak self] in self?.toggleDetached() }
            model.onClose = { [weak self] in self?.closeSurface() }
            model.onEnable = { [weak self] in self?.native?.enable() }
            model.onQuit = { NSApplication.shared.terminate(nil) }
            model.onChangeCount = { [weak self] count in self?.updateStatus(count) }
            controller = NSHostingController(rootView: InboxView(model: model))
            popover.contentViewController = controller; popover.contentSize = NSSize(width: 440, height: 610)
            popover.behavior = .transient; popover.animates = false; popover.delegate = self
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
            updateStatus(0)
            try service.start(); server.start(); native.refreshSettings(); model.refresh()
            if ProcessInfo.processInfo.environment["AGENTNOTIFY_PREVIEW"] == "1" { show() }
            #if DEBUG
            if let output = ProcessInfo.processInfo.environment["AGENTNOTIFY_SELF_CHECK_DIR"], ProcessInfo.processInfo.environment["AGENTNOTIFY_STATE_DIR"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.verifyPanel(output) }
            }
            #endif
        } catch {
            if (error as? NotifyError)?.code == "already_running" { _ = try? SocketClient(path: NotifyPaths().socket).result("show"); NSApplication.shared.terminate(nil); return }
            let alert = NSAlert(); alert.messageText = "AgentNotify Could Not Open"; alert.informativeText = error.localizedDescription; alert.runModal(); NSApplication.shared.terminate(nil)
        }
    }
    private func updateStatus(_ count: Int) {
        let name = count > 0 ? "tray.fill" : "tray"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Notifications")
        image?.isTemplate = true; statusItem?.button?.image = image
        statusItem?.button?.toolTip = count > 0 ? "\(count) unread notifications" : "Notifications"
        statusItem?.button?.setAccessibilityLabel(count > 0 ? "Notifications, \(count) unread" : "Notifications")
    }
    @objc private func toggle() { if popover.isShown || panel?.isVisible == true { closeSurface() } else { show() } }
    func show() {
        native?.refreshSettings(retryDenied: true); model.refresh()
        if model.detached { panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
    private func closeSurface() { if model.detached { panel?.orderOut(nil) } else { popover.performClose(nil) } }
    private func toggleDetached() {
        if model.detached {
            panel?.orderOut(nil); panel?.contentViewController = nil; model.detached = false
            popover.contentViewController = controller; show()
        } else {
            let origin = popover.contentViewController?.view.window?.frame.origin
            popover.performClose(nil); popover.contentViewController = nil
            let panel = self.panel ?? InboxPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 610), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Notifications"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false; panel.level = .floating
            panel.minSize = NSSize(width: 360, height: 360); panel.maxSize = NSSize(width: 700, height: 1200)
            [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
            panel.contentViewController = controller; panel.delegate = self; panel.setFrameAutosaveName("AgentNotifyInbox")
            if let origin { panel.setFrameOrigin(origin) } else { panel.center() }
            self.panel = panel; model.detached = true; panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        }
    }
    #if DEBUG
    private func verifyPanel(_ output: String) {
        do {
            show()
            guard popover.isShown, popover.contentViewController === controller else { throw NotifyError("internal_error", "Popover failed to show its shared content.") }
            toggleDetached()
            guard model.detached, panel?.isVisible == true, panel?.contentViewController === controller, !popover.isShown else { throw NotifyError("internal_error", "Detachment failed to preserve one shared view.") }
            let selected = model.visible.first
            if let selected { model.select(selected); guard try service?.store.get(selected.id).readAt != nil else { throw NotifyError("internal_error", "Opening details failed to persist read state.") } }
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let panel { try PreviewRenderer.capture(panel, directory.appendingPathComponent("native-detached.png"), width: 440, height: 680) }
            toggleDetached()
            guard !model.detached, popover.isShown, popover.contentViewController === controller else { throw NotifyError("internal_error", "Reattachment failed.") }
            closeSurface()
            guard !popover.isShown else { throw NotifyError("internal_error", "Popover failed to close.") }
            let result: [String: Any] = ["ok": true, "checks": ["menu bar popover opens", "detachment retains shared view", "detached panel is visible", "detail opening persists read state", "reattachment retains shared view", "popover closes"], "notifications": model.items.count]
            try JSON.data(result).write(to: directory.appendingPathComponent("native-panel-check.json"))
            NSApp.terminate(nil)
        } catch { stderr("Native panel check failed: \(error.localizedDescription)"); exit(1) }
    }
    #endif
    func applicationWillTerminate(_ notification: Notification) { server?.stop(); service?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
