#if DEBUG
import AppKit
import NotifyCore

enum PopoverDismissalChecks {
    static func run(window: NSWindow) throws -> [String] {
        var inside = false, allowed = true, dismissals = 0
        let originalMovement = window.acceptsMouseMovedEvents
        let hover = PopoverDismissal(delay: 0.08, observesPointerEvents: false, containsPointer: { inside }, allowsDismissal: { allowed }, dismiss: { dismissals += 1 })
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
        inside = true; hover.mouseEntered(with: event); hover.keyDown(with: event)
        inside = false; hover.mouseExited(with: event); wait()
        try require(dismissals == 3, "Leaving after keyboard navigation kept hover dismissal paused.")

        inside = true; hover.mouseMoved(with: event)
        inside = false; hover.mouseMoved(with: event)
        wait(0.03); hover.mouseMoved(with: event)
        wait(0.03); hover.mouseMoved(with: event)
        wait(0.04)
        try require(dismissals == 4, "Missing exit events or continued outside movement prevented dismissal.")

        inside = true; hover.mouseMoved(with: event)
        allowed = false; inside = false; hover.mouseExited(with: event); wait()
        try require(dismissals == 4, "An open sheet did not protect the popover.")
        allowed = true
        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: window)
        wait()
        try require(dismissals == 5, "Closing a sheet did not resume hover dismissal.")

        inside = true; hover.mouseEntered(with: event)
        inside = false; hover.mouseExited(with: event); hover.stop(); wait()
        hover.mouseMoved(with: event); wait()
        try require(dismissals == 5, "Closing or pinning left a dismissal timer active.")
        try require(window.acceptsMouseMovedEvents == originalMovement, "Stopping changed the window's original input policy.")
        return ["hover grace period", "re-entry cancels dismissal", "menus pause dismissal", "keyboard and protected interactions stay open", "pointer exit resumes dismissal after keyboard use", "mouse movement recovers a missed exit without restarting the deadline", "ending a sheet resumes dismissal", "closing or pinning cancels pending dismissal and restores input policy"]
    }
}
#endif
