import AppKit
import SwiftUI
import NotifyCore

final class PreferencesModel: ObservableObject {
    @Published private(set) var current = AppPreferences()
    @Published var error: String?
    @Published private(set) var shimInstalled = false
    @Published private(set) var shimAvailable = false
    @Published private(set) var installingShim = false
    let preview = ArrivalViewModel(content: ArrivalContent(
        id: "preferences-sample", title: "Build finished", subtitle: "AgentNotify",
        message: "All checks passed. The next step is ready when you are.",
        group: "AgentNotify", newCount: 1, waitingCount: 3
    ))
    var service: NotifyService?
    var onChange: ((AppPreferences) -> Void)?

    func refresh() {
        do {
            guard let service else { return }
            let value = try service.store.preferences()
            current = value
            preview.style = value.arrivalStyle
            let shim = try service.call("shimStatus")
            shimInstalled = shim["installed"] as? Bool == true
            shimAvailable = shim["available"] as? Bool == true
            onChange?(value)
        } catch { self.error = "Could not load preferences. \(error.localizedDescription)" }
    }

    func installShim() {
        guard !installingShim, let service else { return }
        installingShim = true; error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try service.call("installShim") }
            DispatchQueue.main.async {
                self.installingShim = false
                if case .failure(let error) = result { self.error = "Could not install the shim. \(error.localizedDescription)" }
                self.refresh()
            }
        }
    }

    func offerShimSetup(in window: NSWindow, install: @escaping () -> Void) {
        guard let service, let status = try? service.call("shimStatus"), status["promptHandled"] as? Bool != true else { return }
        // Record presentation first so a skipped offer or interrupted session
        // never becomes a recurring interruption. Preferences remains available.
        guard (try? service.call("dismissShimSetup")) != nil else { return }
        guard status["installed"] as? Bool != true, status["available"] as? Bool == true else { return }
        let alert = NSAlert()
        alert.messageText = "Use AgentNotify from your terminal?"
        alert.informativeText = "Install a terminal-notifier shim so your existing scripts send notifications to AgentNotify. The original notifier stays available as a fallback.\n\nThe shim goes in ~/.local/bin. Keep that folder before Homebrew on your shell’s PATH. You can also install it later in Preferences."
        alert.addButton(withTitle: "Install shim")
        alert.addButton(withTitle: "Not now")
        alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { install() } }
    }

    func select(_ style: ArrivalStyle) {
        guard style != current.arrivalStyle, let service else { return }
        do {
            _ = try service.call("setPreferences", ["arrivalStyle": style.rawValue,
                "expectedRevision": current.revision, "requestId": UUID().uuidString])
            error = nil
            // Read the authoritative value, including any newer concurrent write.
            refresh()
        } catch {
            self.error = "Could not save this choice. \(error.localizedDescription)"
            refresh()
        }
    }
}

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    let model: PreferencesModel

    init(model: PreferencesModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 512, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        window.level = .floating
        let host = NSHostingController(rootView: PreferencesView(model: model))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 512, height: 560))
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        model.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !NSWorkspace.shared.isVoiceOverEnabled { window?.makeFirstResponder(nil) }
    }
    func windowDidBecomeKey(_ notification: Notification) { model.refresh() }
}

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            Text("Appearance").font(.system(size: 18, weight: .semibold))
            arrivalAppearance
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Terminal integration").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(model.installingShim ? "Installing…" : (model.shimInstalled ? "Reinstall shim" : "Install shim")) { model.installShim() }
                        .disabled(model.installingShim || !model.shimAvailable)
                }
                Text("Send terminal-notifier calls to AgentNotify. The original stays available as a fallback.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(model.shimInstalled ? "Installed in ~/.local/bin. Keep it first on your shell’s PATH." : (model.shimAvailable ? "Installs in ~/.local/bin. Keep it first on your shell’s PATH." : "Install AgentStart to enable this integration."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(error)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        }
        .frame(width: 512, height: 560, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.primary)
    }

    private var arrivalAppearance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Arrival style").font(.system(size: 13, weight: .semibold))
            Picker("Arrival style", selection: Binding(get: { model.current.arrivalStyle }, set: model.select)) {
                ForEach(ArrivalStyle.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Text(model.current.arrivalStyle.detail)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(height: 30, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview").font(.system(size: 11)).foregroundStyle(.secondary)
                ArrivalSurface(model: model.preview, open: { _ in }, dismiss: {}, hover: { _ in })
                    .frame(width: model.current.arrivalStyle.size.width, height: model.current.arrivalStyle.size.height)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Visual sample of \(model.current.arrivalStyle.title)")
                    .frame(maxWidth: .infinity, minHeight: 144, alignment: .top)
            }
            Text("Applies to new compact arrivals. macOS manages system banners.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
