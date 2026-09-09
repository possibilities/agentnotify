import AppKit
import SwiftUI
import NotifyCore

final class InboxPanel: NSPanel {
    // Match the native popover body's continuous corner, without a titled
    // window's different corner mask and edge highlight.
    static let cornerRadius: CGFloat = 20
    var onDrag: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var panel: InboxPanel?
    private var controller: NSViewController!
    private var server: SocketServer?
    private var service: NotifyService?
    private var native: NativeNotifications?
    private var focusMonitor: Any?
    private var anchorWindow: NSWindow?
    private var inboxSize = NSSize(width: 440, height: 610)
    private var manuallyPlaced = false
    private var usesPanel: Bool { model.detached || manuallyPlaced }
    private lazy var hoverDismissal = PopoverDismissal(
        containsPointer: { [weak self] in
            guard let self else { return false }
            let point = NSEvent.mouseLocation
            return self.controller.view.window?.frame.contains(point) == true
                || (self.popover.isShown && self.statusScreenFrame?.contains(point) == true)
        },
        allowsDismissal: { [weak self] in
            guard let self else { return false }
            return (self.popover.isShown || self.panel?.isVisible == true) && !self.model.detached && !NSWorkspace.shared.isVoiceOverEnabled
                && !(self.controller.view.window?.firstResponder is NSTextView)
        },
        dismiss: { [weak self] in self?.closeSurface() }
    )
    #if DEBUG
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
        let wasVisible = usesPanel ? panel?.isVisible == true : popover.isShown
        if usesPanel {
            panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            if !wasVisible { clearOpeningFocus(); startHoverDismissal() }
            return
        }
        if !wasVisible {
            if model.presentedAsPanel { restorePopover() }
            guard let anchor = updatePopoverAnchor(), let anchorView = anchor.contentView else { return }
            anchor.orderFront(nil)
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible {
            clearOpeningFocus()
            startHoverDismissal()
        }
    }
    private func startHoverDismissal() {
        guard !model.detached, let window = controller.view.window else { return }
        hoverDismissal.start(window: window, statusButton: usesPanel ? nil : statusItem.button)
    }
    private func clearOpeningFocus() {
        if !NSWorkspace.shared.isVoiceOverEnabled, !model.searchVisible { controller.view.window?.makeFirstResponder(nil) }
    }
    private func closeSurface() {
        hoverDismissal.stop()
        if usesPanel {
            panel?.orderOut(nil)
            if !model.detached { manuallyPlaced = false }
        } else { popover.performClose(nil) }
    }
    func popoverDidClose(_ notification: Notification) {
        hoverDismissal.stop()
        anchorWindow?.orderOut(nil)
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
    private func placePanelContent(at target: NSRect) {
        guard let panel else { return }
        panel.setContentSize(target.size)
        controller.view.layoutSubtreeIfNeeded()
        guard let actual = contentScreenFrame else { return }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + target.minX - actual.minX, y: panel.frame.minY + target.minY - actual.minY))
    }
    private func restorePopover() {
        if let size = contentScreenFrame?.size { inboxSize = size }
        panel?.orderOut(nil); panel?.contentViewController = nil
        controller.view.removeFromSuperview()
        model.presentedAsPanel = false; manuallyPlaced = false
        configurePopover()
    }
    private func toggleDetached() {
        if model.detached {
            model.detached = false
            if manuallyPlaced {
                clearOpeningFocus(); startHoverDismissal()
            } else { restorePopover(); show() }
        } else if manuallyPlaced {
            hoverDismissal.stop(); model.detached = true; clearOpeningFocus()
        } else {
            if !popover.isShown { show() }
            guard let content = contentScreenFrame else { return }
            inboxSize = content.size
            popover.close(); popover.contentViewController = nil
            controller.view.removeFromSuperview()
            let panel = self.panel ?? InboxPanel(contentRect: NSRect(origin: .zero, size: inboxSize), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            panel.title = "Notifications"
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            // The header owns dragging; AppKit background dragging must not
            // compete with its screen-coordinate movement.
            panel.isMovableByWindowBackground = false; panel.isReleasedWhenClosed = false; panel.level = .floating
            panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 360, height: 360); panel.maxSize = NSSize(width: 700, height: 1200)
            panel.contentViewController = controller
            panel.onDrag = { [weak self] in self?.manuallyPlaced = true }
            self.panel = panel; model.detached = true; model.presentedAsPanel = true
            placePanelContent(at: content)
            panel.invalidateShadow()
            panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            clearOpeningFocus()
        }
    }
    #if DEBUG
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
                guard let before = contentScreenFrame, let screen = menuBarAnchor?.screen, let openingAnchor = anchorWindow?.frame else { throw NotifyError("internal_error", "No initial anchored content.") }
                try require(popover.isShown && popover.contentViewController === controller, "Popover failed to show its shared content.")
                try require(screen.frame.contains(before), "Popover content escaped the display: \(before)")
                toggleDetached(); settle()
                guard let pinned = contentScreenFrame else { throw NotifyError("internal_error", "No pinned content.") }
                try require(near(pinned, before), "Pin moved content: expected \(before), got \(pinned)")
                try require(model.detached && panel?.isVisible == true && panel?.contentViewController === controller && !popover.isShown, "Pin lost the shared view.")
                try require(panel?.hidesOnDeactivate == false && panel?.isFloatingPanel == true, "Pinned panel hides when another app activates.")
                toggleDetached(); settle()
                guard let restored = contentScreenFrame, let anchorAfter = menuBarAnchor else { throw NotifyError("internal_error", "No restored popover content.") }
                let expectedRestore = before.offsetBy(dx: anchorAfter.rect.midX - openingAnchor.midX, dy: anchorAfter.rect.minY - openingAnchor.minY)
                try require(near(restored, expectedRestore), "Unpin moved content: expected \(expectedRestore), got \(restored)")
                try require(!model.detached && popover.isShown && popover.contentViewController === controller, "Unpin lost the shared view.")
                frames.append(["before": NSStringFromRect(before), "pinned": NSStringFromRect(pinned), "restored": NSStringFromRect(restored)])
            }
            // Changing menu geometry and showing an already-visible inbox
            // must not move either surface or its popover positioning window.
            guard let raw = statusScreenFrame, let screen = menuBarAnchor?.screen else { throw NotifyError("internal_error", "No menu bar for movement checks.") }
            let revealed = NSRect(x: raw.minX, y: screen.frame.maxY - raw.height, width: raw.width, height: raw.height)
            let contracted = revealed.offsetBy(dx: 0, dy: raw.height + 2)
            func moveAnchor(to raw: NSRect?) throws {
                guard let before = contentScreenFrame, let openingAnchor = anchorWindow?.frame else { throw NotifyError("internal_error", "No content before menu movement.") }
                verificationAnchor = raw; settle(); show(); settle()
                guard let after = contentScreenFrame else { throw NotifyError("internal_error", "No content after menu movement.") }
                try require(near(after, before), "Menu movement shifted the inbox (pinned=\(model.detached)): expected \(before), got \(after)")
                try require(anchorWindow?.frame == openingAnchor, "An open inbox changed its popover anchor.")
            }
            try moveAnchor(to: revealed); try moveAnchor(to: contracted)
            toggleDetached(); settle()
            try moveAnchor(to: revealed); try moveAnchor(to: contracted); try moveAnchor(to: nil)
            toggleDetached(); settle()
            toggleDetached(); settle()
            guard let movedPanel = panel else { throw NotifyError("internal_error", "No panel to place manually.") }
            let dragChecks = try InboxDragChecks.run(panel: movedPanel)
            guard let placed = contentScreenFrame else { throw NotifyError("internal_error", "No manually placed content.") }
            for _ in 0..<3 {
                toggleDetached(); settle(); show(); settle()
                try require(!model.detached && model.presentedAsPanel && movedPanel.isVisible && !popover.isShown, "Unpin replaced the manually placed panel with a popover.")
                try require(contentScreenFrame.map { near($0, placed) } == true, "Unpin moved the manually placed panel.")
                toggleDetached(); settle()
                try require(model.detached && contentScreenFrame.map { near($0, placed) } == true, "Repinning moved the manually placed panel.")
            }
            toggleDetached(); settle(); closeSurface(); show(); settle()
            try require(popover.isShown && !model.presentedAsPanel && panel?.isVisible != true, "A fresh opening failed to restore the menu-bar popover.")
            if let selected = model.visible.first { model.select(selected); try require(try service?.store.get(selected.id).readAt != nil, "Opening details failed to persist read state.") }
            toggleDetached(); settle()
            if let panel, let content = contentScreenFrame { try PreviewRenderer.capture(panel, directory.appendingPathComponent("native-detached.png"), width: content.width, height: content.height) }
            guard let panel else { throw NotifyError("internal_error", "No panel for hover checks.") }
            let hoverChecks = try PopoverDismissalChecks.run(window: panel)
            toggleDetached(); settle()
            closeSurface()
            try require(!popover.isShown && anchorWindow?.isVisible != true, "Closing left the popover or positioning window visible.")
            let result: [String: Any] = ["ok": true, "checks": ["hidden and negative-coordinate menu anchors", "notched display safe top edge", "popover stays on display", "four pin/unpin cycles preserve content coordinates", "both surfaces stay still across revealed/contracted menu geometry and repeated show", "manually placed panel stays in place without a triangle through three pin/unpin cycles", "fresh opening restores the menu-bar popover", "pinned window configured to persist across app deactivation", "shared content survives transitions", "closing hides the positioning window"], "frames": frames, "notifications": model.items.count]
            try JSON.data(result.merging(["hoverChecks": hoverChecks, "dragChecks": dragChecks]) { _, new in new }).write(to: directory.appendingPathComponent("native-panel-check.json"))
            NSApp.terminate(nil)
        } catch { stderr("Native panel check failed: \(error.localizedDescription)"); exit(1) }
    }
    #endif
    func applicationWillTerminate(_ notification: Notification) {
        hoverDismissal.stop()
        if let focusMonitor { NSEvent.removeMonitor(focusMonitor) }
        server?.stop(); service?.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
