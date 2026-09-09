import AppKit
import SwiftUI
import NotifyCore

final class InboxPanel: NSPanel {
    var onDrag: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var panel: InboxPanel?
    private var controller: NSViewController!
    private var server: SocketServer?
    private var service: NotifyService?
    private var native: NativeNotifications?
    private var focusMonitor: Any?
    private var anchorTimer: Timer?
    private var anchorWindow: NSWindow?
    private var pinnedAnchor: NSRect?
    private var followsAnchor = false
    private var positioningPanel = false
    private var changingSurface = false
    private var inboxSize = NSSize(width: 440, height: 610)
    #if DEBUG
    private var geometryTimer: Timer?
    private var verificationAnchor: NSRect?
    #endif
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
            // Pointer input ends control navigation without interrupting text
            // editing. Tab and VoiceOver retain the native focus behavior.
            focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, let window = self.controller.view.window, event.window === window else { return event }
                if !NSWorkspace.shared.isVoiceOverEnabled, !(window.firstResponder is NSTextView) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
            configurePopover()
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
            updateStatus(0)
            try service.start(); server.start(); native.refreshSettings(); model.refresh()
            if ProcessInfo.processInfo.environment["AGENTNOTIFY_PREVIEW"] == "1" { show() }
            #if DEBUG
            if let output = ProcessInfo.processInfo.environment["AGENTNOTIFY_GEOMETRY_FILE"], ProcessInfo.processInfo.environment["AGENTNOTIFY_STATE_DIR"] != nil {
                geometryTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.writeGeometry(output) }
            }
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
        let wasVisible = model.detached ? panel?.isVisible == true : popover.isShown
        if model.detached {
            panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            startAnchorTracking()
            if !wasVisible { clearOpeningFocus() }
            return
        }
        guard let anchor = updatePopoverAnchor(), let anchorView = anchor.contentView else { return }
        anchor.orderFront(nil)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible { clearOpeningFocus() }
    }
    private func clearOpeningFocus() {
        if !NSWorkspace.shared.isVoiceOverEnabled, !model.searchVisible { controller.view.window?.makeFirstResponder(nil) }
    }
    private func closeSurface() {
        if model.detached { panel?.orderOut(nil) } else { popover.performClose(nil) }
        stopAnchorTracking()
    }
    func popoverDidClose(_ notification: Notification) {
        anchorWindow?.orderOut(nil)
        if !changingSurface { stopAnchorTracking() }
    }
    private func configurePopover() {
        // A popover caches its positioning window and content frame. Never
        // reuse those after the hosting view has lived in a standalone panel.
        popover = NSPopover()
        if let screen = menuBarAnchor?.screen {
            inboxSize.width = min(inboxSize.width, max(360, screen.visibleFrame.width - 32))
            inboxSize.height = min(inboxSize.height, max(340, screen.visibleFrame.height - 32))
        }
        controller.view.setFrameOrigin(.zero)
        controller.view.setBoundsOrigin(.zero)
        controller.view.setFrameSize(inboxSize)
        popover.contentViewController = controller
        popover.contentSize = inboxSize
        popover.behavior = .transient; popover.animates = false; popover.delegate = self
    }
    private var contentScreenFrame: NSRect? {
        guard let window = controller.view.window else { return nil }
        return window.convertToScreen(controller.view.convert(controller.view.bounds, to: nil))
    }
    private var statusScreenFrame: NSRect? {
        #if DEBUG
        if let verificationAnchor { return verificationAnchor }
        #endif
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
    private var menuBarAnchor: (rect: NSRect, screen: NSScreen)? {
        guard let raw = statusScreenFrame, let screen = InboxGeometry.nearestScreen(to: raw) else { return nil }
        return (InboxGeometry.visibleAnchor(raw, screen: screen.frame, topInset: screen.safeAreaInsets.top), screen)
    }
    private func updatePopoverAnchor() -> NSWindow? {
        guard let anchor = menuBarAnchor else { return nil }
        if anchorWindow == nil {
            let window = NSWindow(contentRect: anchor.rect, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.isOpaque = false
            window.backgroundColor = .clear; window.hasShadow = false; window.ignoresMouseEvents = true
            window.level = .statusBar; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.setAccessibilityElement(false); window.contentView?.setAccessibilityElement(false)
            anchorWindow = window
        }
        if anchorWindow?.frame != anchor.rect { anchorWindow?.setFrame(anchor.rect, display: false) }
        return anchorWindow
    }
    private func startAnchorTracking() {
        guard model.detached, anchorTimer == nil else { return }
        // Only the pinned panel follows auto-hide. The transient popover keeps
        // the positioning window where it was when the popover opened.
        anchorTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.followMenuBar() }
        anchorTimer?.tolerance = 0.025
        if let anchorTimer { RunLoop.main.add(anchorTimer, forMode: .common) }
    }
    private func stopAnchorTracking() { anchorTimer?.invalidate(); anchorTimer = nil }
    private func placePanelContent(at target: NSRect) {
        guard let panel else { return }
        positioningPanel = true
        defer { positioningPanel = false }
        panel.setContentSize(target.size)
        controller.view.layoutSubtreeIfNeeded()
        guard let actual = contentScreenFrame else { return }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + target.minX - actual.minX, y: panel.frame.minY + target.minY - actual.minY))
    }
    private func followMenuBar() {
        guard model.detached, followsAnchor, panel?.isVisible == true, let anchor = menuBarAnchor, let previous = pinnedAnchor, let content = contentScreenFrame else { return }
        let current = anchor.rect
        pinnedAnchor = current
        if current != previous {
            let target = content.offsetBy(dx: current.midX - previous.midX, dy: current.minY - previous.minY)
            placePanelContent(at: InboxGeometry.contained(target, in: anchor.screen.visibleFrame))
        }
    }
    func windowDidMove(_ notification: Notification) {
        if !positioningPanel, NSApp.currentEvent?.type == .leftMouseDragged { followsAnchor = false }
    }
    private func toggleDetached() {
        changingSurface = true
        defer { changingSurface = false }
        if model.detached {
            stopAnchorTracking(); followsAnchor = false
            if let size = contentScreenFrame?.size { inboxSize = size }
            panel?.orderOut(nil); panel?.contentViewController = nil
            controller.view.removeFromSuperview()
            model.detached = false
            configurePopover(); show()
        } else {
            if !popover.isShown { show() }
            guard let content = contentScreenFrame else { return }
            inboxSize = content.size
            popover.close(); popover.contentViewController = nil
            controller.view.removeFromSuperview()
            let panel = self.panel ?? InboxPanel(contentRect: NSRect(origin: .zero, size: inboxSize), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Notifications"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false; panel.level = .floating
            panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 360, height: 360); panel.maxSize = NSSize(width: 700, height: 1200)
            [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
            panel.contentViewController = controller; panel.delegate = self
            panel.onDrag = { [weak self] in self?.followsAnchor = false }
            self.panel = panel; model.detached = true
            placePanelContent(at: content)
            pinnedAnchor = menuBarAnchor?.rect; followsAnchor = true
            startAnchorTracking()
            panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            clearOpeningFocus()
        }
    }
    #if DEBUG
    private func writeGeometry(_ output: String) {
        func rect(_ value: NSRect?) -> String { value.map(NSStringFromRect) ?? "none" }
        let data: [String: Any] = ["pinned": model.detached, "visible": panel?.isVisible == true, "follows": followsAnchor, "content": rect(contentScreenFrame), "popover": rect(popover.contentViewController?.view.window?.frame), "panel": rect(panel?.frame), "anchor": rect(statusScreenFrame), "effectiveAnchor": rect(menuBarAnchor?.rect), "proxy": rect(anchorWindow?.frame), "statusVisible": statusItem.button?.window?.isVisible == true, "statusOccluded": statusItem.button?.window?.occlusionState.contains(.visible) != true, "menuVisible": NSMenu.menuBarVisible(), "screen": rect(menuBarAnchor?.screen.frame), "visibleScreen": rect(menuBarAnchor?.screen.visibleFrame)]
        try? JSON.data(data).write(to: URL(fileURLWithPath: output), options: .atomic)
    }
    private func verifyPanel(_ output: String) {
        do {
            func require(_ condition: Bool, _ message: String) throws {
                if !condition { throw NotifyError("internal_error", message) }
            }
            func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.25)) }
            func near(_ a: NSRect, _ b: NSRect) -> Bool {
                abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
            }
            let leftScreen = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
            let hidden = InboxGeometry.visibleAnchor(NSRect(x: -100, y: 1082, width: 22, height: 27), screen: leftScreen, topInset: 0)
            try require(hidden == NSRect(x: -100, y: 1079, width: 22, height: 1), "Hidden menu anchor escaped its negative-coordinate display.")
            let notched = InboxGeometry.visibleAnchor(NSRect(x: 1300, y: 982, width: 22, height: 27), screen: NSRect(x: 0, y: 0, width: 1512, height: 982), topInset: 38)
            try require(notched.maxY == 944, "Hidden menu anchor crossed the display's safe top edge.")
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            show()
            settle()
            var frames: [[String: String]] = []
            for _ in 0..<4 {
                guard let before = contentScreenFrame, let anchorBefore = menuBarAnchor else { throw NotifyError("internal_error", "No initial anchored content.") }
                try require(popover.isShown && popover.contentViewController === controller, "Popover failed to show its shared content.")
                try require(anchorBefore.screen.frame.contains(before), "Popover content escaped the display: \(before)")
                toggleDetached(); settle()
                guard let pinned = contentScreenFrame, let anchorPinned = menuBarAnchor else { throw NotifyError("internal_error", "No pinned content.") }
                let expected = before.offsetBy(dx: anchorPinned.rect.midX - anchorBefore.rect.midX, dy: anchorPinned.rect.minY - anchorBefore.rect.minY)
                try require(near(pinned, expected), "Pin moved content: before \(before), expected \(expected), got \(pinned)")
                try require(model.detached && panel?.isVisible == true && panel?.contentViewController === controller && !popover.isShown, "Pin lost the shared view.")
                try require(panel?.hidesOnDeactivate == false && panel?.isFloatingPanel == true, "Pinned panel hides when another app activates.")
                toggleDetached(); settle()
                guard let restored = contentScreenFrame, let anchorAfter = menuBarAnchor else { throw NotifyError("internal_error", "No restored popover content.") }
                let expectedRestore = before.offsetBy(dx: anchorAfter.rect.midX - anchorBefore.rect.midX, dy: anchorAfter.rect.minY - anchorBefore.rect.minY)
                try require(near(restored, expectedRestore), "Unpin moved content: expected \(expectedRestore), got \(restored)")
                try require(!model.detached && popover.isShown && popover.contentViewController === controller, "Unpin lost the shared view.")
                frames.append(["before": NSStringFromRect(before), "pinned": NSStringFromRect(pinned), "restored": NSStringFromRect(restored)])
            }
            // Drive the same real window positioning path with recorded menu
            // bar states, without changing the person's macOS preferences.
            guard let raw = statusScreenFrame, let screen = menuBarAnchor?.screen else { throw NotifyError("internal_error", "No menu bar for movement checks.") }
            let revealed = NSRect(x: raw.minX, y: screen.frame.maxY - raw.height, width: raw.width, height: raw.height)
            let contracted = revealed.offsetBy(dx: 0, dy: raw.height + 2)
            func moveAnchor(to raw: NSRect?) throws {
                guard let before = contentScreenFrame, let previous = menuBarAnchor?.rect else { throw NotifyError("internal_error", "No content before menu movement.") }
                verificationAnchor = raw; followMenuBar(); settle()
                guard let after = contentScreenFrame, let current = menuBarAnchor?.rect else { throw NotifyError("internal_error", "No content after menu movement.") }
                let expected = model.detached ? before.offsetBy(dx: current.midX - previous.midX, dy: current.minY - previous.minY) : before
                try require(near(after, expected), "Menu movement failed (pinned=\(model.detached)): expected \(expected), got \(after)")
                try require(model.detached || anchorTimer == nil, "Unpinned popover left anchor tracking active.")
            }
            try moveAnchor(to: revealed); try moveAnchor(to: contracted)
            toggleDetached(); settle()
            try moveAnchor(to: revealed); try moveAnchor(to: contracted); try moveAnchor(to: nil)
            toggleDetached(); settle()
            if let selected = model.visible.first { model.select(selected); try require(try service?.store.get(selected.id).readAt != nil, "Opening details failed to persist read state.") }
            toggleDetached(); settle()
            if let panel, let content = contentScreenFrame { try PreviewRenderer.capture(panel, directory.appendingPathComponent("native-detached.png"), width: content.width, height: content.height) }
            toggleDetached(); settle()
            closeSurface()
            try require(!popover.isShown && anchorTimer == nil && anchorWindow?.isVisible != true, "Closing left an anchor or tracker active.")
            let result: [String: Any] = ["ok": true, "checks": ["hidden and negative-coordinate menu anchors", "notched display safe top edge", "popover stays on display", "four pin/unpin cycles preserve content coordinates", "only pinned panel follows revealed/contracted menu geometry", "unpinned popover stays still with no anchor timer", "pinned window configured to persist across app deactivation", "shared content survives transitions", "closing stops anchor tracking"], "frames": frames, "notifications": model.items.count]
            try JSON.data(result).write(to: directory.appendingPathComponent("native-panel-check.json"))
            NSApp.terminate(nil)
        } catch { stderr("Native panel check failed: \(error.localizedDescription)"); exit(1) }
    }
    #endif
    func applicationWillTerminate(_ notification: Notification) {
        if let focusMonitor { NSEvent.removeMonitor(focusMonitor) }
        anchorTimer?.invalidate()
        #if DEBUG
        geometryTimer?.invalidate()
        #endif
        server?.stop(); service?.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
