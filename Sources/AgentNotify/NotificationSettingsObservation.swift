import AppKit

/// macOS publishes no notification-settings change event. Recheck when apps
/// activate or the Mac wakes, and briefly poll only while relevant UI is open.
final class NotificationSettingsObservation {
    private let center: NotificationCenter
    private let shouldPoll: () -> Bool
    private let refresh: () -> Void
    private let interval: TimeInterval
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
         interval: TimeInterval = 3, shouldPoll: @escaping () -> Bool,
         refresh: @escaping () -> Void) {
        self.center = center; self.interval = interval
        self.shouldPoll = shouldPoll; self.refresh = refresh
    }

    func start() {
        stop()
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh(); self?.updatePolling()
            })
        }
        updatePolling()
    }

    func updatePolling() {
        guard shouldPoll() else { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.shouldPoll() else { self.updatePolling(); return }
            self.refresh()
        }
        timer?.tolerance = interval / 3
    }

    func stop() {
        timer?.invalidate(); timer = nil
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }
    deinit { stop() }
}
