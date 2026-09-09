#if DEBUG
import AppKit
import NotifyCore

enum PopoverDismissalChecks {
    static func run(window: NSWindow) throws -> [String] {
        var inside = false, allowed = true, dismissals = 0
        let hover = PopoverDismissal(delay: 0.08, containsPointer: { inside }, allowsDismissal: { allowed }, dismiss: { dismissals += 1 })
        hover.start(window: window, statusButton: nil)
        defer { hover.stop() }
        func wait(_ seconds: TimeInterval = 0.12) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NotifyError("internal_error", message) }
        }
        let event = NSEvent()
        hover.mouseExited(with: event)
        wait()
        try require(dismissals == 0, "Opening started an unwanted dismissal countdown.")
        inside = true; hover.mouseEntered(with: event)
        inside = false; hover.mouseExited(with: event); wait(0.02)
        try require(dismissals == 0, "Popover dismissed before its grace period.")
        inside = true; hover.mouseEntered(with: event); wait()
        try require(dismissals == 0, "Returning to the popover did not cancel dismissal.")
        inside = false; hover.mouseExited(with: event); wait()
        try require(dismissals == 1, "Leaving the popover did not dismiss after the delay.")

        allowed = false; hover.mouseExited(with: event); wait()
        try require(dismissals == 1, "Protected interaction allowed hover dismissal.")
        allowed = true; hover.mouseExited(with: event)
        let menu = NSMenu()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        wait()
        try require(dismissals == 1, "A menu did not pause a pending dismissal.")
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        wait()
        try require(dismissals == 2, "Leaving a menu did not resume the grace period.")

        hover.mouseExited(with: event); hover.keyDown(with: event); wait()
        try require(dismissals == 2, "Keyboard navigation did not cancel dismissal.")
        inside = true; hover.mouseEntered(with: event)
        inside = false; hover.mouseExited(with: event); hover.stop(); wait()
        try require(dismissals == 2, "Closing or pinning left a dismissal timer active.")
        return ["hover grace period", "re-entry cancels dismissal", "menus pause dismissal", "keyboard and protected interactions stay open", "closing or pinning cancels pending dismissal"]
    }
}
#endif
