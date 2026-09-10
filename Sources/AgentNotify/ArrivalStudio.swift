#if DEBUG
import AppKit
import SwiftUI
import NotifyCore

// A development-only native studio for comparing the production arrival
// renderer with two bounded alternatives. All content and inbox rows are
// synthetic; this surface never starts the socket or notification services.
@MainActor
enum ArrivalStudio {
    private static var retainedDelegate: ArrivalStudioDelegate?

    static func run(selections: [String]) throws {
        let state = ArrivalStudioState()
        if !selections.isEmpty {
            guard selections.count == 3,
                  let variant = ArrivalStyle(rawValue: selections[0]),
                  let scenario = ArrivalStudioScenario(rawValue: selections[1]),
                  let appearance = ArrivalStudioAppearance(rawValue: selections[2]) else {
                throw NotifyError("invalid_params", "arrival-studio [queue-peek|compact-toast|queue-shelf single|burst|long light|dark]")
            }
            state.variant = variant; state.scenario = scenario; state.appearance = appearance
            state.applyScenario()
        }
        let app = NSApplication.shared
        let delegate = ArrivalStudioDelegate(state: state)
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    static func render(to directory: String) throws {
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let state = ArrivalStudioState()
        let controller = NSHostingController(rootView: ArrivalStudioPreview(state: state))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ArrivalStyle.queuePeek.size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentViewController = controller
        window.isOpaque = false
        window.backgroundColor = .clear

        for appearance in ArrivalStudioAppearance.allCases {
            window.appearance = appearance.nativeAppearance
            for variant in ArrivalStyle.allCases {
                state.variant = variant
                for scenario in ArrivalStudioScenario.allCases {
                    state.scenario = scenario
                    state.applyScenario()
                    let name = "\(appearance.rawValue)-\(variant.rawValue)-\(scenario.rawValue).png"
                    try PreviewRenderer.capture(
                        window,
                        output.appendingPathComponent(name),
                        width: variant.size.width,
                        height: variant.size.height
                    )
                }
            }
        }
        window.close()
        stdout("Rendered native arrival views to \(output.path)\n")
    }
}

private enum ArrivalStudioScenario: String, CaseIterable, Identifiable {
    case single, burst, long
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var content: ArrivalContent {
        switch self {
        case .single:
            return ArrivalContent(
                id: "studio-single", title: "Build finished", subtitle: "",
                message: "All checks passed. AgentNotify is ready for a closer look.",
                group: "AgentNotify", newCount: 1, unreadCount: 2, waitingCount: 3
            )
        case .burst:
            return ArrivalContent(
                id: "studio-burst", title: "Three updates just arrived", subtitle: "Release train",
                message: "Build complete, review ready, and one decision is waiting for you.",
                group: "Agent fleet", newCount: 3, unreadCount: 5, waitingCount: 8
            )
        case .long:
            return ArrivalContent(
                id: "studio-long", title: "Research synthesis needs your review", subtitle: "AgentNotify workflow",
                message: "The design agency compared interruption levels, queue visibility, reduced motion, and the transition into the durable inbox.",
                group: "Design studio", newCount: 1, unreadCount: 10, waitingCount: 12
            )
        }
    }
}

private enum ArrivalStudioAppearance: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var nativeAppearance: NSAppearance? { NSAppearance(named: self == .light ? .aqua : .darkAqua) }
}

@MainActor
private final class ArrivalStudioState: ObservableObject {
    enum Surface { case preview, inbox, hidden }
    @Published var variant: ArrivalStyle = .queuePeek
    @Published var scenario: ArrivalStudioScenario = .single
    @Published var appearance: ArrivalStudioAppearance = .light
    @Published var surface: Surface = .preview
    @Published var pinned = true
    let arrival = ArrivalViewModel(content: ArrivalStudioScenario.single.content)
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?

    var presentationDescription: String {
        switch surface {
        case .inbox:
            return pinned ? "Inbox open · pinned. Try its rows, search, and filters." : "Inbox unpinned · closes after the pointer leaves."
        case .hidden:
            return "Notification dismissed. Show or replay the preview."
        case .preview:
            return "The latest arrival stays here until you dismiss it or open the inbox."
        }
    }

    func applyScenario() { arrival.style = variant; arrival.content = scenario.content }
}

@MainActor
private final class ArrivalStudioDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state: ArrivalStudioState
    private var preview: NSPanel?
    private var controls: NSWindow?
    private var inbox: InboxPanel?
    private var inboxModel: InboxModel?
    private var inboxRoot: URL?
    private var inboxScenario: ArrivalStudioScenario?
    private var presentationRevision = 0
    private lazy var hoverDismissal = PopoverDismissal(
        containsPointer: { [weak self] in self?.inbox?.frame.contains(NSEvent.mouseLocation) == true },
        allowsDismissal: { [weak self] in
            guard let self else { return false }
            return self.state.surface == .inbox && !self.state.pinned && !NSWorkspace.shared.isVoiceOverEnabled
                && !(self.inbox?.firstResponder is NSTextView)
        },
        dismiss: { [weak self] in self?.hideSurfaces() }
    )

    init(state: ArrivalStudioState) { self.state = state }

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.onOpen = { [weak self] in
            guard let self else { return }
            let revision = self.presentationRevision
            // Finish Button's mouse-up before moving focus to another window.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentationRevision == revision else { return }
                self.showInbox()
            }
        }
        state.onDismiss = { [weak self] in self?.hideSurfaces() }
        makePreview()
        makeControls()
        placeWindows()
        showPreview()
        controls?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hoverDismissal.stop()
        if let inboxRoot { try? FileManager.default.removeItem(at: inboxRoot) }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === controls { NSApp.terminate(nil) }
    }

    func windowDidMove(_ notification: Notification) {
        if notification.object as? NSWindow === controls { placeTargets() }
    }

    // AppKit owns these bounded window sizes. Hosting's content-driven sizing
    // can otherwise resize/reposition a borderless window during a view update.
    private func host<V: View>(_ view: V, in window: NSWindow, size: NSSize) {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(size)
        controller.view.setFrameOrigin(.zero)
        controller.view.setBoundsOrigin(.zero)
        controller.view.setFrameSize(size)
        controller.view.layoutSubtreeIfNeeded()
    }

    private func makePreview() {
        let size = state.variant.size
        let panel = ArrivalPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        host(ArrivalStudioPreview(state: state), in: panel, size: size)
        panel.title = "Arrival preview · synthetic"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.appearance = state.appearance.nativeAppearance
        preview = panel
    }

    private func makeControls() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 380),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Arrival Studio"
        host(ArrivalStudioControls(
            state: state,
            replay: { [weak self] in self?.replay() },
            openInbox: { [weak self] in self?.showInbox() },
            showPreview: { [weak self] in self?.showPreview() },
            arrange: { [weak self] in self?.placeWindows() },
            quit: { NSApp.terminate(nil) },
            designChanged: { [weak self] in self?.showPreview() },
            appearanceChanged: { [weak self] in self?.applyAppearance() }
        ), in: window, size: NSSize(width: 410, height: 380))
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        controls = window
    }

    private func placeWindows() {
        let screen = controls?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let controls {
            let top = min(screen.maxY - 24, screen.midY + 305)
            controls.setFrameTopLeftPoint(NSPoint(x: max(screen.minX + 16, screen.midX - 437), y: top))
        }
        placeTargets()
    }

    private func placeTargets() {
        guard let controls else { return }
        guard let screen = controls.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let right = min(screen.maxX - 16, controls.frame.maxX + 24 + 440)
        let top = min(screen.maxY - 16, controls.frame.maxY)
        for window in [preview, inbox].compactMap({ $0 }) {
            window.setFrameTopLeftPoint(NSPoint(x: right - window.frame.width, y: max(screen.minY + window.frame.height, top)))
        }
    }

    private func applyAppearance() {
        preview?.appearance = state.appearance.nativeAppearance
        inbox?.appearance = state.appearance.nativeAppearance
    }

    private func refreshPreview() {
        state.applyScenario()
        if inboxModel != nil, inboxScenario != state.scenario {
            do { try installSyntheticScenario() }
            catch { NSAlert(error: error).runModal() }
        }
        if let inboxModel {
            state.arrival.content.waitingCount = inboxModel.inboxCount
            state.arrival.content.unreadCount = inboxModel.unreadCount
        }
        applyAppearance()
        guard let preview else { return }
        let topRight = NSPoint(x: preview.frame.maxX, y: preview.frame.maxY)
        preview.setContentSize(state.variant.size)
        preview.contentView?.setFrameSize(state.variant.size)
        preview.contentView?.layoutSubtreeIfNeeded()
        preview.setFrameOrigin(NSPoint(x: topRight.x - preview.frame.width, y: topRight.y - preview.frame.height))
    }

    private func replay() {
        showPreview()
        guard let preview else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            preview.alphaValue = 1
        } else {
            preview.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                preview.animator().alphaValue = 1
            }
        }
    }

    private func hideSurfaces() {
        presentationRevision += 1
        hoverDismissal.stop()
        preview?.orderOut(nil)
        inbox?.orderOut(nil)
        state.surface = .hidden
        returnFocusToControls()
    }

    private func showPreview() {
        presentationRevision += 1
        hoverDismissal.stop()
        inbox?.orderOut(nil)
        refreshPreview()
        preview?.orderFrontRegardless()
        state.surface = .preview
        returnFocusToControls()
    }

    private func returnFocusToControls() {
        // A borderless panel can leave NSApp without a key window when hidden.
        // Keep the studio operable, without activating it over another app.
        if NSApp.isActive { controls?.makeKeyAndOrderFront(nil) }
    }

    private func showInbox() {
        presentationRevision += 1
        do {
            if inbox == nil { try makeSyntheticInbox() }
            preview?.orderOut(nil)
            inbox?.appearance = state.appearance.nativeAppearance
            if let preview, let inbox, !inbox.isVisible {
                inbox.setFrameTopLeftPoint(NSPoint(x: preview.frame.maxX - inbox.frame.width, y: preview.frame.maxY))
            }
            inbox?.makeKeyAndOrderFront(nil)
            state.surface = .inbox
            updatePin()
            NSApp.activate(ignoringOtherApps: true)
            if !NSWorkspace.shared.isVoiceOverEnabled { inbox?.makeFirstResponder(nil) }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func makeSyntheticInbox() throws {
        let model = InboxModel()
        model.detached = true
        model.presentedAsPanel = true
        model.onClose = { [weak self] in self?.hideSurfaces() }
        model.onDetach = { [weak self] in
            guard let self else { return }
            self.state.pinned.toggle()
            self.updatePin()
        }
        model.onChangeCount = { [weak self, weak model] count in
            self?.state.arrival.content.waitingCount = count
            self?.state.arrival.content.unreadCount = model?.unreadCount ?? 0
        }
        model.onQuit = { NSApp.terminate(nil) }
        inboxModel = model
        try installSyntheticScenario()
        let window = InboxPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 610),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false
        )
        window.title = "Notifications · synthetic"
        host(InboxView(model: model), in: window, size: NSSize(width: 440, height: 610))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isFloatingPanel = true
        window.level = .floating
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 360, height: 360)
        window.maxSize = NSSize(width: 700, height: 1200)
        window.isReleasedWhenClosed = false
        if let preview { window.setFrameTopLeftPoint(NSPoint(x: preview.frame.minX, y: preview.frame.maxY)) }
        inbox = window
    }

    private func updatePin() {
        inboxModel?.detached = state.pinned
        hoverDismissal.stop()
        if !state.pinned, let inbox, inbox.isVisible { hoverDismissal.start(window: inbox, statusButton: nil) }
    }

    private func installSyntheticScenario() throws {
        guard let model = inboxModel else { return }
        let previousRoot = inboxRoot

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agentnotify-arrival-studio-\(UUID().uuidString)")
        let store = try Store(paths: NotifyPaths(root: root))
        let service = NotifyService(store: store)
        let content = state.scenario.content
        let now = Date().timeIntervalSince1970
        let pendingCount = max(0, content.waitingCount)
        let supporting = [
            ("Build finished", "All checks passed. The next build is ready to inspect."),
            ("Review is ready", "A small change is waiting for your review."),
            ("Your research is saved", "The sources and findings are waiting in the wiki."),
            ("One detail before we continue", "Choose the next milestone when you have a moment.")
        ]
        for index in 0..<pendingCount {
            let sample = supporting[max(0, index - 1) % supporting.count]
            var params: [String: Any] = ["title": index == 0 ? content.title : sample.0, "message": index == 0 ? content.message : sample.1,
                                         "group": index == 0 ? content.group : "Sample \(index)"]
            if index == 0, !content.subtitle.isEmpty { params["subtitle"] = content.subtitle }
            _ = try store.perform("send", params: params, now: now - Double(index))
        }
        model.service = service
        model.filter = "inbox"
        model.group = nil
        model.query = ""
        model.period = "any"
        model.searchVisible = false
        model.undoItem = nil
        model.error = nil
        model.refresh()
        model.selected = model.items.max(by: { $0.createdAt < $1.createdAt })?.id
        if let id = model.selected { model.markRead(id) }
        inboxRoot = root
        inboxScenario = state.scenario
        if let previousRoot { try? FileManager.default.removeItem(at: previousRoot) }
    }
}

private struct ArrivalStudioPreview: View {
    @ObservedObject var state: ArrivalStudioState

    var body: some View {
        ArrivalSurface(
            model: state.arrival,
            open: { _ in state.onOpen?() },
            dismiss: { state.onDismiss?() }
        )
        .frame(width: state.variant.size.width, height: state.variant.size.height)
    }
}

private struct ArrivalStudioControls: View {
    @ObservedObject var state: ArrivalStudioState
    let replay: () -> Void
    let openInbox: () -> Void
    let showPreview: () -> Void
    let arrange: () -> Void
    let quit: () -> Void
    let designChanged: () -> Void
    let appearanceChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare arrivals").font(.system(size: 17, weight: .semibold))
                Text("Sample notifications · changes stay in this studio")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Picker("Design", selection: $state.variant) {
                ForEach(ArrivalStyle.allCases) { Text($0.title).tag($0) }
            }
            Picker("Scenario", selection: $state.scenario) {
                ForEach(ArrivalStudioScenario.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Appearance", selection: $state.appearance) {
                ForEach(ArrivalStudioAppearance.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            HStack(spacing: 8) {
                Button("Show preview", action: showPreview)
                    .disabled(state.surface == .preview)
                Button("Replay arrival", action: replay)
                Button("Open inbox", action: openInbox)
                    .disabled(state.surface == .inbox)
            }
            Text(state.presentationDescription)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Arrange windows", action: arrange)
                Spacer()
                Button("Quit", action: quit)
            }
        }
        .padding(22)
        .onChange(of: state.variant) { designChanged() }
        .onChange(of: state.scenario) { designChanged() }
        .onChange(of: state.appearance) { appearanceChanged() }
        .frame(width: 410, height: 380, alignment: .topLeading)
    }
}

#endif
