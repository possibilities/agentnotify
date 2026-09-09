#if DEBUG
import AppKit
import NotifyCore

enum InboxDragChecks {
    static func run(panel: InboxPanel) throws -> [String] {
        func findDragView(_ view: NSView) -> InboxDragRegion.DragView? {
            if let dragView = view as? InboxDragRegion.DragView { return dragView }
            return view.subviews.lazy.compactMap { findDragView($0) }.first
        }
        guard let content = panel.contentView, let dragView = findDragView(content) else {
            throw NotifyError("internal_error", "No header drag region in the actual panel.")
        }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NotifyError("internal_error", message) }
        }
        func event(_ type: CGEventType, _ pointer: NSPoint) -> NSEvent {
            let quartz = CGPoint(x: pointer.x, y: NSScreen.screens[0].frame.maxY - pointer.y)
            // Event objects only: invoke the actual view without posting input
            // to the user's desktop or moving the physical pointer.
            return NSEvent(cgEvent: CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartz, mouseButton: .left)!)!
        }
        try require(!panel.isMovableByWindowBackground && !dragView.mouseDownCanMoveWindow, "Native background dragging competes with the header.")
        let initialOrigin = panel.frame.origin
        let localStart = NSPoint(x: 180, y: panel.frame.height - 32)
        let initialPointer = panel.convertPoint(toScreen: localStart)
        var pointer = initialPointer
        defer { dragView.mouseUp(with: event(.leftMouseUp, pointer)) }
        dragView.mouseDown(with: event(.leftMouseDown, pointer))
        // Repeat an event captured before the window moved. Its local position
        // is stale, but the physical pointer has not moved again.
        for delta in [NSPoint(x: -80, y: -90), NSPoint(x: 60, y: -20), .zero, NSPoint(x: -30, y: -120), NSPoint(x: -80, y: -90)] {
            pointer = NSPoint(x: initialPointer.x + delta.x, y: initialPointer.y + delta.y)
            let queuedEvent = event(.leftMouseDragged, pointer)
            let expected = NSPoint(x: initialOrigin.x + delta.x, y: initialOrigin.y + delta.y)
            for _ in 0..<3 {
                dragView.mouseDragged(with: queuedEvent)
                try require(hypot(panel.frame.minX - expected.x, panel.frame.minY - expected.y) <= 1,
                            "Queued drag event moved the grab point: expected \(expected), got \(panel.frame.origin)")
            }
        }
        dragView.mouseUp(with: event(.leftMouseUp, pointer))
        let releasedOrigin = panel.frame.origin
        pointer.x += 50
        dragView.mouseDragged(with: event(.leftMouseDragged, pointer))
        try require(panel.frame.origin == releasedOrigin, "Mouse-up left a drag active.")

        // A second grab must capture a fresh offset, including after layout
        // changes or a different header grab location.
        pointer = panel.convertPoint(toScreen: NSPoint(x: 210, y: panel.frame.height - 30))
        dragView.mouseDown(with: event(.leftMouseDown, pointer))
        pointer.x -= 45; pointer.y += 20
        dragView.mouseDragged(with: event(.leftMouseDragged, pointer))
        try require(panel.frame.origin == NSPoint(x: releasedOrigin.x - 45, y: releasedOrigin.y + 20), "A new drag reused the previous grab offset.")
        return ["queued local coordinates cannot move the screen grab point", "repeated drag events do not accumulate movement", "direction reversals return to the starting position", "mouse-up ends dragging and a new grab resets the offset"]
    }
}
#endif
