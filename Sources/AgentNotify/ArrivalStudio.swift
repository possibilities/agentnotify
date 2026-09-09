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

    static func run() {
        let app = NSApplication.shared
        let delegate = ArrivalStudioDelegate()
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
            contentRect: NSRect(origin: .zero, size: ArrivalStudioVariant.queuePeek.size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentViewController = controller
        window.isOpaque = false
        window.backgroundColor = .clear

        for appearance in ArrivalStudioAppearance.allCases {
            window.appearance = appearance.nativeAppearance
            for variant in ArrivalStudioVariant.allCases {
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

private enum ArrivalStudioVariant: String, CaseIterable, Identifiable {
    case queuePeek = "queue-peek"
    case compactToast = "compact-toast"
    case queueShelf = "queue-shelf"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .queuePeek: return "Queue Peek · production"
        case .compactToast: return "Compact Toast · alternative"
        case .queueShelf: return "Queue Shelf · alternative"
        }
    }
    var size: NSSize {
        switch self {
        case .compactToast: return NSSize(width: 360, height: 96)
        case .queuePeek: return ArrivalView.preferredSize
        case .queueShelf: return NSSize(width: 440, height: 144)
        }
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
                group: "AgentNotify", newCount: 1, waitingCount: 3
            )
        case .burst:
            return ArrivalContent(
                id: "studio-burst", title: "Three updates just arrived", subtitle: "Release train",
                message: "Build complete, review ready, and one decision is waiting for you.",
                group: "Agent fleet", newCount: 3, waitingCount: 8
            )
        case .long:
            return ArrivalContent(
                id: "studio-long", title: "Research synthesis needs your review", subtitle: "Native notifications",
                message: "The design agency compared interruption levels, queue visibility, reduced motion, and the transition into the durable inbox.",
                group: "Design studio", newCount: 1, waitingCount: 12
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
    @Published var variant: ArrivalStudioVariant = .queuePeek
    @Published var scenario: ArrivalStudioScenario = .single
    @Published var appearance: ArrivalStudioAppearance = .light
    @Published var isHovering = false
    let arrival = ArrivalViewModel(content: ArrivalStudioScenario.single.content)
    var onOpen: (() -> Void)?
    var onDismiss: (() -> Void)?

    func applyScenario() { arrival.content = scenario.content }
}

@MainActor
private final class ArrivalStudioDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = ArrivalStudioState()
    private var preview: NSPanel?
    private var controls: NSWindow?
    private var inbox: InboxPanel?
    private var inboxModel: InboxModel?
    private var inboxRoot: URL?
    private var inboxScenario: ArrivalStudioScenario?
    private var presentationRevision = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.onOpen = { [weak self] in self?.showInbox() }
        state.onDismiss = { [weak self] in self?.dismissPreview() }
        makePreview()
        makeControls()
        placeWindows()
        preview?.orderFront(nil)
        controls?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let inboxRoot { try? FileManager.default.removeItem(at: inboxRoot) }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === controls { NSApp.terminate(nil) }
    }

    private func makePreview() {
        let size = state.variant.size
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.contentViewController = NSHostingController(rootView: ArrivalStudioPreview(state: state))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.appearance = state.appearance.nativeAppearance
        preview = panel
    }

    private func makeControls() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 352),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Arrival Studio · transient preview"
        window.contentViewController = NSHostingController(rootView: ArrivalStudioControls(
            state: state,
            replay: { [weak self] in self?.replay() },
            openInbox: { [weak self] in self?.showInbox() },
            collapse: { [weak self] in self?.collapse() },
            quit: { NSApp.terminate(nil) },
            changed: { [weak self] in self?.refreshPreview() }
        ))
        window.isReleasedWhenClosed = false
        window.delegate = self
        controls = window
    }

    private func placeWindows() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let preview {
            preview.setFrameOrigin(NSPoint(x: screen.maxX - preview.frame.width - 24, y: screen.maxY - preview.frame.height - 24))
        }
        if let controls {
            controls.setFrameOrigin(NSPoint(x: max(screen.minX + 24, screen.midX - 460), y: screen.midY - controls.frame.height / 2))
        }
    }

    private func refreshPreview() {
        presentationRevision += 1
        state.applyScenario()
        if inboxModel != nil, inboxScenario != state.scenario {
            do { try installSyntheticScenario() }
            catch { NSAlert(error: error).runModal() }
        }
        preview?.appearance = state.appearance.nativeAppearance
        inbox?.appearance = state.appearance.nativeAppearance
        guard let preview else { return }
        let topRight = NSPoint(x: preview.frame.maxX, y: preview.frame.maxY)
        preview.setContentSize(state.variant.size)
        preview.setFrameOrigin(NSPoint(x: topRight.x - preview.frame.width, y: topRight.y - preview.frame.height))
        if !preview.isVisible && inbox?.isVisible != true { preview.orderFront(nil) }
    }

    private func replay() {
        inbox?.orderOut(nil)
        refreshPreview()
        preview?.orderOut(nil)
        let revision = presentationRevision
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.presentationRevision == revision else { return }
            self.preview?.orderFront(nil)
        }
    }

    private func dismissPreview() { presentationRevision += 1; preview?.orderOut(nil) }

    private func collapse() {
        inbox?.orderOut(nil)
        refreshPreview()
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
            NSApp.activate(ignoringOtherApps: true)
            if !NSWorkspace.shared.isVoiceOverEnabled { inbox?.makeFirstResponder(nil) }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func makeSyntheticInbox() throws {
        let model = InboxModel()
        model.authorization = "authorized"
        model.detached = true
        model.presentedAsPanel = true
        model.onClose = { [weak self] in self?.collapse() }
        model.onQuit = { NSApp.terminate(nil) }
        inboxModel = model
        try installSyntheticScenario()
        let window = InboxPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 610),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false
        )
        window.title = "Notifications · synthetic"
        window.contentViewController = NSHostingController(rootView: InboxView(model: model))
        window.setContentSize(NSSize(width: 440, height: 610))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 360, height: 360)
        window.isReleasedWhenClosed = false
        if let preview { window.setFrameTopLeftPoint(NSPoint(x: preview.frame.minX, y: preview.frame.maxY)) }
        inbox = window
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
            var params: [String: Any] = ["title": index == 0 ? content.title : sample.0, "message": index == 0 ? content.message : sample.1]
            if index == 0, !content.subtitle.isEmpty { params["subtitle"] = content.subtitle }
            _ = try store.perform("send", params: params, now: now - Double(index))
        }
        model.service = service
        model.filter = "inbox"
        model.group = nil
        model.query = ""
        model.period = "any"
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
        Group {
            switch state.variant {
            case .queuePeek:
                ArrivalView(
                    model: state.arrival,
                    open: { _ in state.onOpen?() },
                    dismiss: { state.onDismiss?() },
                    hover: { state.isHovering = $0 }
                )
            case .compactToast:
                CompactToastAlternative(content: state.arrival.content, open: { state.onOpen?() })
            case .queueShelf:
                QueueShelfAlternative(content: state.arrival.content, open: { state.onOpen?() })
            }
        }
        .frame(width: state.variant.size.width, height: state.variant.size.height)
    }
}

private struct ArrivalStudioControls: View {
    @ObservedObject var state: ArrivalStudioState
    let replay: () -> Void
    let openInbox: () -> Void
    let collapse: () -> Void
    let quit: () -> Void
    let changed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transient comparison").font(.system(size: 17, weight: .semibold))
                Text("Synthetic content · no notifications, callbacks, or saved settings")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Picker("Design", selection: $state.variant) {
                ForEach(ArrivalStudioVariant.allCases) { Text($0.title).tag($0) }
            }
            Picker("Scenario", selection: $state.scenario) {
                ForEach(ArrivalStudioScenario.allCases) { Text($0.title).tag($0) }
            }
            Picker("Appearance", selection: $state.appearance) {
                ForEach(ArrivalStudioAppearance.allCases) { Text($0.title).tag($0) }
            }
            HStack(spacing: 10) {
                Button("Replay", action: replay)
                Button("Open inbox", action: openInbox).buttonStyle(.borderedProminent)
                Button("Collapse", action: collapse)
                Spacer()
                Button("Quit", action: quit)
            }
            Text(state.isHovering ? "Pointer is over the production preview" : "Pointer is outside the production preview")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(22)
        .onChange(of: state.variant) { changed() }
        .onChange(of: state.scenario) { changed() }
        .onChange(of: state.appearance) { changed() }
        .frame(width: 410, height: 352, alignment: .topLeading)
    }
}

private struct CompactToastAlternative: View {
    let content: ArrivalContent
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(content.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(content.waitingCount == 1 ? "1 waiting" : "\(content.waitingCount) waiting")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text(content.message).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(content.title). \(content.message). \(content.waitingCount) waiting. Open notifications.")
    }
}

private struct QueueShelfAlternative: View {
    let content: ArrivalContent
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(content.group.isEmpty ? "Notification" : content.group)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text(content.newCount > 1 ? "+\(content.newCount) new" : "New")
                        .font(.system(size: 11, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(content.message).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 7) {
                    Circle().frame(width: 5, height: 5)
                    Text(content.waitingCount == 1 ? "1 item stays in your inbox" : "\(content.waitingCount) items stay in your inbox")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(content.title). \(content.message). \(content.waitingCount) waiting. Open notifications.")
    }
}
#endif
