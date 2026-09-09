import AppKit
import SwiftUI
import NotifyCore

final class ArrivalPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A transient projection of the durable inbox. Dismissal never writes a response
/// or changes read/task state, and presenting never activates the application.
final class ArrivalPresentation {
    private let model = ArrivalViewModel(content: ArrivalContent(id: "", title: "", subtitle: "", message: "", group: "", newCount: 0, waitingCount: 0))
    private(set) var panel: ArrivalPanel?
    private var order: [String] = []
    private var records: [String: NotificationRecord] = [:]
    private var hovered = false
    private var pressedID: String?
    private var inputMonitor: Any?
    private var timer: Timer?
    private var expiresAt: Date?
    private var remaining: TimeInterval = 5
    private var generation = 0
    private let duration: TimeInterval
    // Changing preferences must never move the target under a held pointer.
    // Adopt the choice when the next distinct presentation begins.
    var style: ArrivalStyle = .queuePeek
    var displayedStyle: ArrivalStyle { model.style }
    var placement: ((NSSize) -> NSRect?)?
    var open: ((String) -> Void)?

    init(duration: TimeInterval = 5) { self.duration = duration }
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
        if (!hovered && pressedID == nil) || !wasVisible { selectLatest() }
        updateCounts(items)
        if !wasVisible { present() }
        remaining = duration
        if !hovered && pressedID == nil { schedule(duration) }
    }

    func refresh(_ items: [NotificationRecord]) {
        synchronize(items)
        guard !order.isEmpty else { dismiss(); return }
        // Freeze the displayed text through hover/press, even if its group was
        // replaced. Clicking still opens that exact durable history item; only
        // the full inbox ever exposes its current response/action state.
        if records[model.content.id] == nil && isVisible && !hovered && pressedID == nil { selectLatest() }
        updateCounts(items)
    }

    private func synchronize(_ items: [NotificationRecord]) {
        let eligible = Dictionary(uniqueKeysWithValues: items.filter { $0.isInbox && $0.presentable }.map { ($0.id, $0) })
        order.removeAll { eligible[$0] == nil }
        records = eligible.filter { order.contains($0.key) }
    }

    private func updateCounts(_ items: [NotificationRecord]) {
        model.content.newCount = order.count
        model.content.waitingCount = items.filter(\.isInbox).count
    }

    private func selectLatest() {
        guard let id = order.last, let item = records[id] else { return }
        model.content = ArrivalContent(id: item.id, title: item.title, subtitle: item.subtitle,
            message: item.message, group: item.group, newCount: order.count, waitingCount: model.content.waitingCount)
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
                hover: { [weak self] in self?.setHovered($0) }))
            controller.sizingOptions = []
            panel.contentViewController = controller
            self.panel = panel
            inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self, weak panel] event in
                guard let self, event.window === panel else { return event }
                if event.type == .leftMouseDown {
                    self.pressedID = self.model.content.id
                    self.cancelTimer()
                } else {
                    let expected = self.generation
                    // Let Button finish its release against the pressed content
                    // before advancing a burst to its newest notification.
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == expected else { return }
                        self.pressedID = nil
                        if !self.hovered && self.isVisible { self.selectLatest(); self.schedule(self.duration) }
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
        hovered = panel.frame.contains(NSEvent.mouseLocation)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
        if NSWorkspace.shared.isVoiceOverEnabled, let view = panel.contentView {
            NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
                .announcement: "\(model.content.title). \(model.content.waitingCount) notifications waiting.",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ])
        }
    }

    func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        if value {
            remaining = max(1.5, expiresAt?.timeIntervalSinceNow ?? duration)
            cancelTimer()
        } else if isVisible {
            guard pressedID == nil else { return }
            let changed = model.content.id != order.last
            selectLatest()
            schedule(changed ? duration : max(1.5, remaining))
        }
    }

    private func schedule(_ delay: TimeInterval) {
        cancelTimer()
        guard isVisible, !hovered, pressedID == nil, !NSWorkspace.shared.isVoiceOverEnabled else { return }
        expiresAt = Date().addingTimeInterval(delay)
        let expected = generation
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.generation == expected, !self.hovered else { return }
            if NSEvent.pressedMouseButtons != 0 { self.schedule(1.5); return }
            self.dismiss()
        }
    }

    func openDisplayed(_ id: String) {
        let id = pressedID ?? id
        guard isVisible, id == model.content.id else { return }
        dismiss()
        open?(id)
    }

    func dismiss() {
        generation += 1
        cancelTimer()
        panel?.orderOut(nil)
        order.removeAll(); records.removeAll(); hovered = false; pressedID = nil
    }

    private func cancelTimer() { timer?.invalidate(); timer = nil; expiresAt = nil }
    deinit { timer?.invalidate(); if let inputMonitor { NSEvent.removeMonitor(inputMonitor) } }
}
