import AppKit
import Combine
import SwiftUI
import NotifyCore

final class InboxPanel: NSPanel {
    // Match the native popover body's continuous corner, without a titled
    // window's different corner mask and edge highlight.
    static let cornerRadius: CGFloat = 20
    var onDrag: (() -> Void)?
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NotifyInterfaceController {
    private var statusItem: NSStatusItem!
    private var panel: InboxPanel?
    private var controller: NSViewController!
    private var server: SocketServer?
    private var service: NotifyService?
    private var focusMonitor: Any?
    private var inboxSize = NSSize(width: 440, height: 610)
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var selectionGeneration = 0
    private let arrivals = ArrivalPresentation()
    private let completeAllShortcut = GlobalShortcutController()
    private var arrivalTracker: ArrivalTracker?
    private var pendingArrivalIDs: [String] = []
    private var arrivalAnchor: NSRect?
    private var openingAnchor: NSRect?
    private let interfaceInstanceID = UUID().uuidString.lowercased()
    private var interfaceRevision = 1
    private var interfaceObservation: AnyCancellable?
    private var interfaceRequests: [String: (fingerprint: String, result: [String: Any])] = [:]
    private var interfaceRequestOrder: [String] = []
    private var inboxIsVisible: Bool { panel?.isVisible == true }
    private lazy var hoverDismissal = PopoverDismissal(
        containsPointer: { [weak self] in
            guard let self else { return false }
            let point = NSEvent.mouseLocation
            return self.controller.view.window?.frame.contains(point) == true
                || self.statusScreenFrame?.contains(point) == true
        },
        allowsDismissal: { [weak self] in
            guard let self else { return false }
            return self.inboxIsVisible && !self.model.detached && !NSWorkspace.shared.isVoiceOverEnabled
                && !(self.controller.view.window?.firstResponder is NSTextView)
                && self.controller.view.window?.attachedSheet == nil
        },
        dismiss: { [weak self] in self?.closeSurface() }
    )
    #if DEBUG
    private var verificationAnchor: NSRect?
    #endif
    private let model = InboxModel()
    private let preferencesModel = PreferencesModel()
    private var preferencesWindow: PreferencesWindowController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let service = NotifyService(store: try Store(paths: NotifyPaths()))
            let server = try SocketServer(paths: service.store.paths, handler: service.handle)
            self.service = service; self.server = server; model.service = service
            service.interfaceController = self
            interfaceObservation = model.objectWillChange.sink { [weak self] in self?.bumpInterfaceRevision() }
            preferencesModel.service = service
            completeAllShortcut.action = { [weak self] in self?.showCompleteAllConfirmation() }
            preferencesModel.onApplyShortcut = { [weak self] shortcut in self?.completeAllShortcut.apply(shortcut) }
            preferencesModel.activeShortcut = { [weak self] in self?.completeAllShortcut.current }
            preferencesModel.onChange = { [weak self] preferences in
                self?.arrivals.style = preferences.arrivalStyle
            }
            preferencesModel.refresh()
            service.onPreferencesChange = { [weak self] in DispatchQueue.main.async { self?.preferencesModel.refresh() } }
            service.onShowPreferences = { [weak self] in DispatchQueue.main.async { self?.showPreferences() } }
            // AgentNotify owns arrival presentation. Remove any native requests
            // left by earlier releases, but never register new system banners.
            if ProcessInfo.processInfo.environment["AGENTNOTIFY_STATE_DIR"] == nil {
                LegacySystemNotificationCleanup.removeAll()
            }
            // Seed before timers or clients can create a new event. Existing
            // active rows remain waiting without replaying them as arrivals.
            arrivalTracker = ArrivalTracker(cursor: try service.store.cursor())
            service.onChange = { [weak self] in DispatchQueue.main.async { self?.refreshNotifications() } }
            service.onShow = { [weak self] id, detached in DispatchQueue.main.async {
                guard let self else { return }
                self.model.reveal(id)
                if let detached, detached != self.model.detached { self.toggleDetached() }
                self.show()
            } }
            model.onDetach = { [weak self] in self?.toggleDetached() }
            model.onClose = { [weak self] in self?.closeSurface() }
            model.onPreferences = { [weak self] in self?.showPreferences() }
            model.onQuit = { NSApplication.shared.terminate(nil) }
            model.onChangeCount = { [weak self] count in self?.updateStatus(count) }
            model.onOpenArrivals = { [weak self] in
                guard let self, let id = self.model.arrivalIDs.last else { return }
                self.model.arrivalIDs.removeAll()
                self.model.revealArrival(id)
                self.model.markRead(id)
            }
            arrivals.placement = { [weak self] size in self?.arrivalFrame(size) }
            arrivals.onChange = { [weak self] in self?.bumpInterfaceRevision() }
            arrivals.open = { [weak self] id in
                // Finish the compact panel's mouse-up before creating a
                // inbox panel, so the original click finishes on its owner.
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.openingAnchor = self.arrivalAnchor
                    defer { self.openingAnchor = nil }
                    self.model.revealArrival(id)
                    self.show()
                    self.model.markRead(id)
                }
            }
            arrivals.complete = { [weak self] item in
                guard let self, self.model.done(item) else { return nil }
                return self.model.items
            }
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
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
            statusItem.button?.sendAction(on: [.leftMouseUp])
            configurePanel()
            updateStatus(0)
            try service.start(); server.start(); model.refresh()
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
        let name = count > 0 ? "tray.circle.fill" : "tray.circle"
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Notifications")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true; statusItem?.button?.image = image
        // Let AppKit apply the native menu-extra padding around both the icon
        // and its optional count instead of drawing inside a fixed-width slot.
        statusItem?.length = NSStatusItem.variableLength
        statusItem?.button?.imagePosition = count > 0 ? .imageLeading : .imageOnly
        statusItem?.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusItem?.button?.title = count > 0 ? " \(count > 99 ? "99+" : String(count))" : ""
        let label = count > 0 ? "Notifications, \(count) waiting, \(model.unreadCount) unread" : "Notifications"
        statusItem?.button?.toolTip = label
        statusItem?.button?.setAccessibilityLabel(label)
        updateStatusHighlight()
    }
    private func updateStatusHighlight() {
        selectionGeneration += 1
        let generation = selectionGeneration
        if !inboxIsVisible { statusItem?.button?.isHighlighted = false; return }
        // Use the same native renderer for pressed and selected states. Like
        // Maccy's panel, restore selection after the button action has returned.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selectionGeneration == generation, self.inboxIsVisible else { return }
            self.statusItem?.button?.isHighlighted = true
        }
    }
    private func refreshNotifications() {
        guard let service, let tracker = arrivalTracker else { return }
        do {
            // Consume committed events rather than diffing broad UI snapshots:
            // multiple changes (including a complete snooze cycle) can coalesce.
            var hasMore = true
            while hasMore {
                let page = try service.store.perform("changes", params: ["after": tracker.cursor, "limit": 100])
                let changes = page["changes"] as? [[String: Any]] ?? []
                let batch = try tracker.consume(changes)
                for change in changes where change["kind"] as? String == "read" {
                    if let item = change["notification"] as? [String: Any], let id = item["id"] as? String {
                        model.arrivalIDs.removeAll { $0 == id }
                    }
                }
                for item in batch {
                    pendingArrivalIDs.removeAll { $0 == item.id }
                    pendingArrivalIDs.append(item.id)
                }
                hasMore = page["hasMore"] as? Bool ?? false
            }
            model.refresh()
            model.arrivalIDs.removeAll { id in !model.items.contains { $0.id == id && $0.isInbox && $0.presentable } }
            if pendingArrivalIDs.isEmpty { arrivals.refresh(model.items) }
            else { presentPendingArrivals() }
        } catch { model.error = "Could not read new notifications. \(error.localizedDescription)" }
    }

    private func presentPendingArrivals() {
        model.refresh()
        let records = Dictionary(uniqueKeysWithValues: model.items.filter { $0.isInbox && $0.presentable }.map { ($0.id, $0) })
        let batch = pendingArrivalIDs.compactMap { records[$0] }
        pendingArrivalIDs.removeAll()
        if inboxIsVisible {
            arrivals.dismiss()
            for item in batch where !model.arrivalIDs.contains(item.id) { model.arrivalIDs.append(item.id) }
        } else if !batch.isEmpty { arrivals.receive(batch, items: model.items) }
    }

    private func arrivalFrame(_ size: NSSize) -> NSRect? {
        guard let anchor = menuBarAnchor else { return nil }
        arrivalAnchor = anchor.rect
        let size = NSSize(width: arrivals.style == .compactToast ? size.width : inboxSize.width, height: size.height)
        // Sample the safe menu anchor once per appearance. No auto-hide
        // tracking: a visible arrival stays still, just like the full inbox.
        let screen = anchor.screen.visibleFrame
        // Keep the same screen-edge clearance as the full inbox.
        let x = max(screen.minX + 13, min(anchor.rect.midX - size.width / 2, screen.maxX - size.width - 13))
        let top = min(anchor.rect.minY - 13, screen.maxY - 8)
        return NSRect(x: x, y: max(screen.minY + 8, top - size.height), width: size.width, height: size.height)
    }
    @objc private func toggle() {
        if inboxIsVisible { closeSurface() } else { show() }
    }
    private func showPreferences() {
        let wasVisible = preferencesWindow?.window?.isVisible == true
        if !model.detached { closeSurface() }
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(model: preferencesModel)
            preferencesWindow?.onVisibilityChange = { [weak self] in self?.bumpInterfaceRevision() }
        }
        preferencesWindow?.present()
        if !wasVisible { bumpInterfaceRevision() }
        if let window = preferencesWindow?.window { offerShimSetup(in: window) }
    }
    private func showCompleteAllConfirmation() {
        model.refresh()
        guard model.inboxCount > 0 else { return }
        show()
        model.confirmingCompleteAll = true
    }
    private func offerShimSetup(in window: NSWindow) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["AGENTNOTIFY_SELF_CHECK_DIR"] != nil { return }
        #endif
        preferencesModel.offerShimSetup(in: window) { [weak self] in
            self?.showPreferences(); self?.preferencesModel.installShim()
        }
    }
    func show() {
        arrivals.dismiss()
        pendingArrivalIDs.removeAll()
        let wasVisible = inboxIsVisible
        if !wasVisible { model.arrivalIDs.removeAll() }
        model.refresh()
        guard let panel else { return }
        if !wasVisible && !model.detached {
            if let size = contentScreenFrame?.size { inboxSize = size }
            guard let anchor = menuBarAnchor else { return }
            let screen = anchor.screen.visibleFrame
            let rect = openingAnchor ?? anchor.rect
            let size = NSSize(width: min(inboxSize.width, screen.width - 26),
                              height: min(inboxSize.height, screen.height - 26))
            let x = max(screen.minX + 13, min(rect.midX - size.width / 2, screen.maxX - size.width - 13))
            let top = min(rect.minY - 13, screen.maxY - 8)
            placePanelContent(at: NSRect(x: x, y: max(screen.minY + 8, top - size.height),
                                        width: size.width, height: size.height))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        if !wasVisible {
            clearOpeningFocus()
            startDismissal()
            bumpInterfaceRevision()
        }
        offerShimSetup(in: panel)
        updateStatusHighlight()
    }
    private func startDismissal() {
        stopDismissal()
        guard !model.detached, let panel else { return }
        hoverDismissal.start(window: panel, statusButton: statusItem.button)
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // A different app's menu extra may not activate its application or
        // take key status. Its mouse-down is still an immediate outside click.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.dismissForOutsideClick()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel && event.window !== self.statusItem.button?.window {
                // Let the inbox's own menus and sheets keep their normal input.
                if event.window?.sheetParent !== self.panel && event.window?.level != .popUpMenu {
                    self.dismissForOutsideClick()
                }
            }
            return event
        }
    }
    private func stopDismissal() {
        hoverDismissal.stop()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = nil; localClickMonitor = nil
    }
    private func dismissForOutsideClick() {
        guard inboxIsVisible, !model.detached, panel?.attachedSheet == nil else { return }
        closeSurface()
    }
    private func panelResignedKey() {
        guard inboxIsVisible, !model.detached, panel?.attachedSheet == nil else { return }
        // Our own activator owns its toggle, including the mouse-up. Do not
        // close on mouse-down and then reopen on that same click's mouse-up.
        if NSEvent.pressedMouseButtons != 0,
           statusScreenFrame?.contains(NSEvent.mouseLocation) == true { return }
        closeSurface()
    }
    private func clearOpeningFocus() {
        if !NSWorkspace.shared.isVoiceOverEnabled, !model.searchVisible { controller.view.window?.makeFirstResponder(nil) }
    }
    private func closeSurface() {
        let wasVisible = inboxIsVisible
        model.arrivalIDs.removeAll()
        stopDismissal()
        panel?.orderOut(nil)
        if wasVisible { bumpInterfaceRevision() }
        // Clear native selection only after the panel has gone away.
        updateStatusHighlight()
    }
    private func configurePanel() {
        if let screen = menuBarAnchor?.screen {
            inboxSize.width = min(inboxSize.width, max(360, screen.visibleFrame.width - 32))
            inboxSize.height = min(inboxSize.height, max(340, screen.visibleFrame.height - 32))
        }
        model.presentedAsPanel = true
        let panel = InboxPanel(contentRect: NSRect(origin: .zero, size: inboxSize),
                               styleMask: [.borderless, .nonactivatingPanel, .resizable],
                               backing: .buffered, defer: false)
        panel.title = "Notifications"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovableByWindowBackground = false; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 360, height: 340); panel.maxSize = NSSize(width: 700, height: 1200)
        panel.contentViewController = controller
        // Installing the hosting controller can replace the requested frame
        // with its empty-content fitting size. Keep the initial inbox size.
        panel.setContentSize(inboxSize)
        panel.onResignKey = { [weak self] in self?.panelResignedKey() }
        self.panel = panel
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
    private func placePanelContent(at target: NSRect) {
        guard let panel else { return }
        panel.setContentSize(target.size)
        controller.view.layoutSubtreeIfNeeded()
        guard let actual = contentScreenFrame else { return }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + target.minX - actual.minX, y: panel.frame.minY + target.minY - actual.minY))
    }
    private func toggleDetached() {
        if !inboxIsVisible { show() }
        model.detached.toggle()
        if model.detached { stopDismissal() } else { startDismissal() }
        clearOpeningFocus()
        updateStatusHighlight()
        bumpInterfaceRevision()
    }
    #if DEBUG
    private func verifyPanel(_ output: String) {
        show()
        // Give the native button's deferred selection a real main-queue turn.
        DispatchQueue.main.async { self.verifyVisiblePanel(output) }
    }
    private func verifyVisiblePanel(_ output: String) {
        do {
            func require(_ condition: Bool, _ message: String) throws {
                if !condition { throw NotifyError("internal_error", message) }
            }
            func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let panel, let initial = contentScreenFrame, let screen = menuBarAnchor?.screen else {
                throw NotifyError("internal_error", "No visible inbox panel.")
            }
            try require(inboxIsVisible && panel.contentViewController === controller, "Inbox lost its shared content.")
            try require(statusItem.button?.isHighlighted == true, "Native status selection is missing.")
            try require(statusItem.length == NSStatusItem.variableLength, "Status item lost intrinsic sizing.")
            try require(screen.frame.contains(initial), "Inbox escaped the screen.")
            try require(initial.size == inboxSize, "Hosting content collapsed the initial inbox size.")
            try require(panel.styleMask.contains(.nonactivatingPanel), "Inbox activates the application.")
            for _ in 0..<4 {
                toggleDetached()
                try require(model.detached && contentScreenFrame == initial, "Pin moved the inbox.")
                panelResignedKey()
                dismissForOutsideClick()
                try require(inboxIsVisible, "Pinned inbox dismissed on outside input.")
                toggleDetached()
                try require(!model.detached && contentScreenFrame == initial, "Unpin moved the inbox.")
            }
            // The open window must not track menu-bar reveal/hide movements.
            guard let raw = statusScreenFrame else { throw NotifyError("internal_error", "Missing status anchor.") }
            for offset: CGFloat in [30, -30, 0] {
                verificationAnchor = raw.offsetBy(dx: 0, dy: offset)
                show()
                try require(contentScreenFrame == initial, "Repeated show/menu movement repositioned the inbox.")
            }
            verificationAnchor = nil
            toggleDetached()
            settle()
            let dragChecks = try InboxDragChecks.run(panel: panel)
            let moved = contentScreenFrame
            toggleDetached()
            try require(contentScreenFrame == moved, "Unpin repositioned a manually dragged inbox.")
            dismissForOutsideClick()
            try require(!inboxIsVisible, "Unpinned inbox ignored an outside mouse-down.")
            try require(statusItem.button?.isHighlighted == false, "Closed inbox left native selection on.")
            show()
            panelResignedKey()
            try require(!inboxIsVisible, "Unpinned inbox ignored key-window loss.")
            // A queued opening highlight must not survive a close.
            show()
            closeSurface()
            DispatchQueue.main.async {
                do {
                    try require(self.statusItem.button?.isHighlighted == false, "Stale opening restored selection after closing.")
                    let result: [String: Any] = [
                        "ok": true,
                        "checks": ["native status selection", "nonactivating panel", "four stationary pin/unpin cycles",
                                   "pinned focus-loss and outside-click persistence", "stable open geometry",
                                   "drag and unpin preserve position", "outside-click dismissal", "key-loss dismissal",
                                   "stale selection cannot outlive the inbox"],
                        "dragChecks": dragChecks
                    ]
                    try JSON.data(result).write(to: directory.appendingPathComponent("native-panel-check.json"))
                    NSApp.terminate(nil)
                } catch { stderr("Native panel check failed: \(error.localizedDescription)"); exit(1) }
            }
        } catch { stderr("Native panel check failed: \(error.localizedDescription)"); exit(1) }
    }
    #endif
    func applicationWillTerminate(_ notification: Notification) {
        arrivals.dismiss()
        stopDismissal()
        if let focusMonitor { NSEvent.removeMonitor(focusMonitor) }
        server?.stop(); service?.stop()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func bumpInterfaceRevision() {
        if Thread.isMainThread { interfaceRevision += 1 }
        else { DispatchQueue.main.async { [weak self] in self?.interfaceRevision += 1 } }
    }

    func performInterface(_ method: String, params: [String: Any]) throws -> [String: Any] {
        if Thread.isMainThread { return try performInterfaceOnMain(method, params: params) }
        return try DispatchQueue.main.sync { try performInterfaceOnMain(method, params: params) }
    }

    private func performInterfaceOnMain(_ method: String, params: [String: Any]) throws -> [String: Any] {
        dispatchPrecondition(condition: .onQueue(.main))
        if method == "uiState" { return try interfaceSnapshot() }
        let fingerprint = JSON.string(["method": method, "params": params])
        if let requestID = params["requestId"] as? String, let cached = interfaceRequests[requestID] {
            guard cached.fingerprint == fingerprint else { throw NotifyError("request_conflict", "requestId was already used for a different interface command.") }
            return cached.result
        }
        if let instance = params["expectedInstanceId"] as? String, instance != interfaceInstanceID {
            throw NotifyError("revision_conflict", "AgentNotify restarted. Read uiState before controlling the interface.")
        }
        if let expected = params["expectedUIRevision"] as? Int, expected != interfaceRevision {
            throw NotifyError("revision_conflict", "The native interface changed. Read uiState and retry against its current UI revision.")
        }

        var resultFields: [String: Any] = [:]
        switch method {
        case "uiShow":
            if params["surface"] as? String == "preferences" { showPreferences() }
            else {
                if let id = params["id"] as? String {
                    _ = try service?.store.get(id)
                    model.reveal(id)
                }
                show()
                if let pinned = params["pinned"] as? Bool, pinned != model.detached { toggleDetached() }
            }
        case "uiClose":
            switch params["surface"] as? String ?? "inbox" {
            case "preferences": preferencesWindow?.close()
            case "arrival": arrivals.dismiss()
            case "all": closeSurface(); preferencesWindow?.close(); arrivals.dismiss()
            default: closeSurface()
            }
        case "uiSetView": try setInterfaceView(params)
        case "uiNavigate": navigateInterface(params["direction"] as! String)
        case "uiSetPinned":
            let pinned = params["pinned"] as! Bool
            if !inboxIsVisible { show() }
            if pinned != model.detached { toggleDetached() }
        case "uiDismissArrival":
            if let id = params["id"] as? String, arrivals.displayedID != id {
                throw NotifyError("revision_conflict", "The displayed arrival changed. Read uiState before dismissing it.")
            }
            arrivals.dismiss()
        case "uiCopy":
            let id = (params["id"] as? String) ?? model.selected
            guard let id else { throw NotifyError("invalid_state", "Select a notification or supply its exact id before copying.") }
            let item = try service!.store.get(id)
            let content = params["content"] as! String
            let value = content == "id" ? item.id : [item.title, item.subtitle, item.message].filter { !$0.isEmpty }.joined(separator: "\n")
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
            resultFields = ["copied": content, "id": id]
        default: throw NotifyError("unknown_method", "Unknown interface operation: \(method).")
        }
        bumpInterfaceRevision()
        var result = try interfaceSnapshot()
        for (key, value) in resultFields { result[key] = value }
        if let requestID = params["requestId"] as? String {
            interfaceRequests[requestID] = (fingerprint, result); interfaceRequestOrder.append(requestID)
            if interfaceRequestOrder.count > 200, let oldest = interfaceRequestOrder.first {
                interfaceRequestOrder.removeFirst(); interfaceRequests.removeValue(forKey: oldest)
            }
        }
        return result
    }

    private func setInterfaceView(_ params: [String: Any]) throws {
        let filter = params["filter"] as? String ?? model.filter
        let query = params["query"] as? String ?? model.query
        let group: String? = (params["group"] as? String).map { $0.isEmpty ? nil : $0 } ?? model.group
        let period = params["period"] as? String ?? model.period
        let details = params["details"] as? String ?? "preserve"
        let selected: String?
        if let id = params["id"] as? String {
            if id.isEmpty { selected = nil }
            else {
                _ = try service?.store.get(id)
                guard model.matching(filter: filter, query: query, group: group, period: period).contains(where: { $0.id == id }) else { throw NotifyError("invalid_state", "The notification does not match the requested native view.") }
                selected = details == "collapse" ? nil : id
            }
        } else if details == "collapse" { selected = nil }
        else { selected = model.selected }
        if details == "expand", selected == nil { throw NotifyError("invalid_state", "Select a notification before expanding details.") }
        model.filter = filter; model.query = query; model.searchVisible = !query.isEmpty
        model.group = group; model.period = period; model.selected = selected
    }

    private func navigateInterface(_ direction: String) {
        let items = model.visible
        guard !items.isEmpty else { model.selected = nil; return }
        let current = model.selected.flatMap { id in items.firstIndex(where: { $0.id == id }) }
        let index: Int
        switch direction {
        case "last": index = items.count - 1
        case "previous": index = current.map { max(0, $0 - 1) } ?? (items.count - 1)
        case "next": index = current.map { min(items.count - 1, $0 + 1) } ?? 0
        default: index = 0
        }
        model.selected = items[index].id
    }

    private func interfaceSnapshot() throws -> [String: Any] {
        let visible = model.visible
        let preferencesVisible = preferencesWindow?.window?.isVisible == true
        let surface: String
        if inboxIsVisible && preferencesVisible { surface = "multiple" }
        else if inboxIsVisible { surface = "inbox" }
        else if preferencesVisible { surface = "preferences" }
        else { surface = "hidden" }
        let rows: [[String: Any]] = visible.prefix(100).map { item in
            ["id": item.id, "title": item.title, "group": item.group, "status": item.status,
             "read": item.readAt != nil, "revision": item.revision]
        }
        var selection: Any = NSNull()
        if let id = model.selected, let index = visible.firstIndex(where: { $0.id == id }), let item = model.items.first(where: { $0.id == id }) {
            var selected = try JSON.encode(item)
            selected["position"] = index + 1; selected["matchingCount"] = visible.count; selected["expanded"] = true
            selection = selected
        }
        let undo: Any = model.undoItem.map { ["id": $0.id, "expectedRevision": $0.revision] as [String: Any] } ?? NSNull()
        return [
            "instanceId": interfaceInstanceID, "uiRevision": interfaceRevision, "surface": surface,
            "inbox": ["visible": inboxIsVisible, "presentation": inboxIsVisible ? "panel" : "hidden", "pinned": model.detached],
            "preferencesVisible": preferencesVisible,
            "view": ["filter": model.filter, "query": model.query, "group": model.group ?? "", "period": model.period],
            "selection": selection, "matchingCount": visible.count, "visibleItems": rows, "hasMore": visible.count > rows.count,
            "arrival": ["visible": arrivals.isVisible, "id": arrivals.displayedID ?? "", "newCount": arrivals.newCount],
            "undo": undo
        ]
    }
}
