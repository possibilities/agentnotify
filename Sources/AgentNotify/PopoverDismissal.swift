import AppKit

// Event-driven hover dismissal. This never changes window geometry or polls
// the menu bar; the only timer is the grace period after the pointer leaves.
final class PopoverDismissal: NSResponder {
    private let delay: TimeInterval
    private let containsPointer: () -> Bool
    private let allowsDismissal: () -> Bool
    private let dismiss: () -> Void
    private let observesPointerEvents: Bool
    private var timer: Timer?
    private var areas: [(NSView, NSTrackingArea)] = []
    private var inputMonitor: Any?
    private var outsideInputMonitor: Any?
    private weak var window: NSWindow?
    private var acceptedMouseMovement = false
    private var menuObservers: [NSObjectProtocol] = []
    private var trackingMenus = Set<ObjectIdentifier>()
    private var keyboardActive = false
    private var hasEntered = false

    init(delay: TimeInterval = 1, observesPointerEvents: Bool = true, containsPointer: @escaping () -> Bool,
         allowsDismissal: @escaping () -> Bool, dismiss: @escaping () -> Void) {
        self.delay = delay; self.containsPointer = containsPointer
        self.allowsDismissal = allowsDismissal; self.dismiss = dismiss
        self.observesPointerEvents = observesPointerEvents
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start(window: NSWindow, statusButton: NSView?) {
        stop()
        self.window = window
        acceptedMouseMovement = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        hasEntered = containsPointer()
        // Include the native pointer and window edges, as well as the tray
        // button, so moving from the icon into the inbox has a grace period.
        let frameView = window.contentView?.superview ?? window.contentView
        for view in [frameView, statusButton].compactMap({ $0 }) {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
            view.addTrackingArea(area); areas.append((view, area))
        }
        let pointerEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        if observesPointerEvents {
            inputMonitor = NSEvent.addLocalMonitorForEvents(matching: pointerEvents.union(.keyDown)) { [weak self, weak window] event in
                guard let self else { return event }
                if event.type == .keyDown {
                    if event.window === window { self.keyDown(with: event) }
                } else {
                    self.mouseMoved(with: event)
                }
                return event
            }
            // Moving into another app does not necessarily deliver an exit event
            // to an AppKit popover's frame tracking area. Observe those mouse events
            // too, without polling or changing any window/menu-bar position.
            outsideInputMonitor = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents) { [weak self] event in
                self?.mouseMoved(with: event)
            }
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
            },
            center.addObserver(forName: NSWindow.didEndSheetNotification, object: window, queue: .main) { [weak self] _ in
                self?.scheduleIfOutside()
            },
            center.addObserver(forName: NSControl.textDidEndEditingNotification, object: nil, queue: .main) { [weak self] _ in
                // Give SwiftUI/AppKit time to release the field editor.
                DispatchQueue.main.async { self?.scheduleIfOutside() }
            }
        ]
        // Opening alone does not start a countdown. The pointer must leave
        // the inbox or its tray button before hover dismissal is armed.
    }

    override func mouseEntered(with event: NSEvent) {
        mouseMoved(with: event)
    }
    override func mouseExited(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) {
        guard window != nil else { return }
        // Pointer activity returns control from keyboard navigation, including
        // an exit without another entry after the last key press.
        keyboardActive = false
        if containsPointer() { hasEntered = true }
        scheduleIfOutside()
    }
    override func keyDown(with event: NSEvent) { keyboardActive = true; cancel() }

    private func scheduleIfOutside() {
        guard window != nil, hasEntered, !containsPointer(), !keyboardActive, trackingMenus.isEmpty, allowsDismissal() else { cancel(); return }
        // Outside movement must not postpone a countdown already in progress.
        guard timer == nil else { return }
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
        if let outsideInputMonitor { NSEvent.removeMonitor(outsideInputMonitor) }; outsideInputMonitor = nil
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers.removeAll(); trackingMenus.removeAll(); keyboardActive = false; hasEntered = false
        window?.acceptsMouseMovedEvents = acceptedMouseMovement; window = nil
    }
    deinit { stop() }
}
