import AppKit

// Event-driven hover dismissal. This never changes window geometry or polls
// the menu bar; the only timer is the grace period after the pointer leaves.
final class PopoverDismissal: NSResponder {
    private let delay: TimeInterval
    private let containsPointer: () -> Bool
    private let allowsDismissal: () -> Bool
    private let dismiss: () -> Void
    private var timer: Timer?
    private var areas: [(NSView, NSTrackingArea)] = []
    private var inputMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var trackingMenus = Set<ObjectIdentifier>()
    private var keyboardActive = false
    private var hasEntered = false

    init(delay: TimeInterval = 1, containsPointer: @escaping () -> Bool,
         allowsDismissal: @escaping () -> Bool, dismiss: @escaping () -> Void) {
        self.delay = delay; self.containsPointer = containsPointer
        self.allowsDismissal = allowsDismissal; self.dismiss = dismiss
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start(window: NSWindow, statusButton: NSView?) {
        stop()
        hasEntered = containsPointer()
        // Include the native pointer and window edges, as well as the tray
        // button, so moving from the icon into the inbox has a grace period.
        let frameView = window.contentView?.superview ?? window.contentView
        for view in [frameView, statusButton].compactMap({ $0 }) {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
            view.addTrackingArea(area); areas.append((view, area))
        }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self, weak window] event in
            guard let self, event.window === window else { return event }
            if event.type == .keyDown {
                self.keyDown(with: event)
            } else {
                self.keyboardActive = false
                self.scheduleIfOutside()
            }
            return event
        }
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let menu = note.object as? NSMenu else { return }
                self.trackingMenus.insert(ObjectIdentifier(menu)); self.cancel()
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let menu = note.object as? NSMenu else { return }
                self.trackingMenus.remove(ObjectIdentifier(menu)); self.scheduleIfOutside()
            }
        ]
        // Opening alone does not start a countdown. The pointer must leave
        // the inbox or its tray button before hover dismissal is armed.
    }

    override func mouseEntered(with event: NSEvent) {
        if containsPointer() { hasEntered = true; keyboardActive = false }
        cancel()
    }
    override func mouseExited(with event: NSEvent) { scheduleIfOutside() }
    override func keyDown(with event: NSEvent) { keyboardActive = true; cancel() }

    private func scheduleIfOutside() {
        cancel()
        guard hasEntered, !containsPointer(), !keyboardActive, trackingMenus.isEmpty, allowsDismissal() else { return }
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = nil
            guard !self.containsPointer(), !self.keyboardActive, self.trackingMenus.isEmpty,
                  NSEvent.pressedMouseButtons == 0, self.allowsDismissal() else { return }
            self.dismiss()
        }
    }
    private func cancel() { timer?.invalidate(); timer = nil }
    func stop() {
        cancel()
        for (view, area) in areas { view.removeTrackingArea(area) }
        areas.removeAll()
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }; inputMonitor = nil
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers.removeAll(); trackingMenus.removeAll(); keyboardActive = false; hasEntered = false
    }
}
