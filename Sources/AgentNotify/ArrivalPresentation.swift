import AppKit
import SwiftUI
import NotifyCore

final class ArrivalPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A compact projection of the durable inbox. It remains until dismissed or opened.
/// Dismissal never writes a response or changes read/task state, and presenting
/// never activates the application.
final class ArrivalPresentation {
    private let model = ArrivalViewModel(content: ArrivalContent(id: "", title: "", subtitle: "", message: "", group: "", newCount: 0, unreadCount: 0, waitingCount: 0))
    private(set) var panel: ArrivalPanel?
    private var order: [String] = []
    private var records: [String: NotificationRecord] = [:]
    private var pressedID: String?
    private var inputMonitor: Any?
    private var generation = 0
    // Changing preferences must never move the target under a held pointer.
    // Adopt the choice when the next distinct presentation begins.
    var style: ArrivalStyle = .queuePeek
    var displayedStyle: ArrivalStyle { model.style }
    var placement: ((NSSize) -> NSRect?)?
    var open: ((String) -> Void)?
    /// Completes the displayed durable notification through the shared service
    /// contract and returns the refreshed Inbox on success.
    var complete: ((NotificationRecord) -> [NotificationRecord]?)?
    var onChange: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }
    var displayedID: String? { isVisible ? model.content.id : nil }
    var newCount: Int { order.count }

    func receive(_ arrivals: [NotificationRecord], items: [NotificationRecord]) {
        synchronize(items)
        for item in arrivals where item.isInbox && item.presentable {
            order.removeAll { $0 == item.id }
            order.append(item.id)
            records[item.id] = item
        }
        guard !order.isEmpty else { dismiss(); return }
        let wasVisible = isVisible
        if pressedID == nil || !wasVisible { selectLatest() }
        updateCounts(items)
        if !wasVisible { present() }
        onChange?()
    }

    func refresh(_ items: [NotificationRecord]) {
        synchronize(items)
        guard !order.isEmpty else { dismiss(); return }
        // Freeze the displayed text only during a press. Clicking still opens
        // that exact durable history item even if a replacement arrives.
        if records[model.content.id] == nil && isVisible && pressedID == nil { selectLatest() }
        updateCounts(items)
    }

    private func synchronize(_ items: [NotificationRecord]) {
        let eligible = Dictionary(uniqueKeysWithValues: items.filter { $0.isInbox && $0.presentable }.map { ($0.id, $0) })
        order.removeAll { eligible[$0] == nil }
        records = eligible.filter { order.contains($0.key) }
    }

    private func updateCounts(_ items: [NotificationRecord]) {
        model.content.newCount = order.count
        model.content.unreadCount = items.filter { $0.isInbox && $0.readAt == nil }.count
        model.content.waitingCount = items.filter(\.isInbox).count
    }

    private func selectLatest() {
        guard let id = order.last, let item = records[id] else { return }
        model.content = ArrivalContent(id: item.id, title: item.title, subtitle: item.subtitle,
            message: item.message, group: item.group, newCount: order.count,
            unreadCount: model.content.unreadCount, waitingCount: model.content.waitingCount)
    }

    private func present() {
        model.style = style
        guard let frame = placement?(style.size) else { return }
        if panel == nil {
            let panel = ArrivalPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "New notification"
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.level = .statusBar; panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true; panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let controller = NSHostingController(rootView: ArrivalSurface(model: model,
                open: { [weak self] id in self?.openDisplayed(id) },
                dismiss: { [weak self] in self?.dismiss() },
                complete: { [weak self] in self?.completeDisplayed() }))
            controller.sizingOptions = []
            panel.contentViewController = controller
            self.panel = panel
            inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self, weak panel] event in
                guard let self, event.window === panel else { return event }
                if event.type == .leftMouseDown {
                    self.pressedID = self.model.content.id
                } else {
                    let expected = self.generation
                    // Let Button finish its release against the pressed content
                    // before advancing a burst to its newest notification.
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == expected else { return }
                        self.pressedID = nil
                        if self.isVisible { self.selectLatest() }
                    }
                }
                return event
            }
        }
        guard let panel else { return }
        generation += 1
        panel.setFrame(frame, display: true)
        panel.contentView?.setFrameSize(frame.size)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
        if NSWorkspace.shared.isVoiceOverEnabled, let view = panel.contentView {
            NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
                .announcement: "\(model.content.title). \(model.content.queueAccessibilitySummary).",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ])
        }
    }

    func openDisplayed(_ id: String) {
        let id = pressedID ?? id
        guard isVisible, id == model.content.id else { return }
        dismiss()
        open?(id)
    }

    func completeDisplayed() {
        let id = pressedID ?? model.content.id
        guard isVisible, id == model.content.id, let item = records[id],
              let items = complete?(item) else { return }
        refresh(items)
    }

    func dismiss() {
        let changed = isVisible || !order.isEmpty
        generation += 1
        panel?.orderOut(nil)
        order.removeAll(); records.removeAll(); pressedID = nil
        if changed { onChange?() }
    }

    deinit { if let inputMonitor { NSEvent.removeMonitor(inputMonitor) } }
}
