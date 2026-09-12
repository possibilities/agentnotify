#if DEBUG
import AppKit
import NotifyCore

enum InboxDragChecks {
    static func run(panel: InboxPanel) throws -> [String] {
        func findDragView(_ view: NSView) -> InboxDragRegion.DragView? {
            if let dragView = view as? InboxDragRegion.DragView { return dragView }
            return view.subviews.lazy.compactMap { findDragView($0) }.first
        }
        func findScrollView(_ view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView { return scrollView }
            return view.subviews.lazy.compactMap { findScrollView($0) }.first
        }
        func enclosingDragView(_ view: NSView?) -> InboxDragRegion.DragView? {
            var current = view
            while let candidate = current {
                if let dragView = candidate as? InboxDragRegion.DragView { return dragView }
                current = candidate.superview
            }
            return nil
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
        guard let scrollView = findScrollView(content) else {
            throw NotifyError("internal_error", "No notification scroll view in the actual panel.")
        }
        let clip = scrollView.contentView
        let blankPoint = clip.convert(NSPoint(x: clip.bounds.midX, y: clip.bounds.midY), to: content)
        let blankHit = content.hitTest(blankPoint)
        let blankHitName = blankHit.map { String(reflecting: type(of: $0)) } ?? "nil"
        let documentFrame = scrollView.documentView?.frame.debugDescription ?? "nil"
        guard let blankDragView = enclosingDragView(blankHit) else {
            throw NotifyError("internal_error", "Sparse blank space in the notification list is not draggable (hit \(blankHitName), clip \(clip.bounds), document \(documentFrame)).")
        }
        let blankOrigin = panel.frame.origin
        let blankWindowPoint = content.convert(blankPoint, to: nil)
        let blankInitialPointer = panel.convertPoint(toScreen: blankWindowPoint)
        let blankPointer = NSPoint(x: blankInitialPointer.x + 24, y: blankInitialPointer.y - 16)
        blankDragView.mouseDown(with: event(.leftMouseDown, blankInitialPointer))
        blankDragView.mouseDragged(with: event(.leftMouseDragged, blankPointer))
        try require(panel.frame.origin == NSPoint(x: blankOrigin.x + 24, y: blankOrigin.y - 16),
                    "Sparse blank-space drag did not move the panel through its hit region.")
        blankDragView.mouseUp(with: event(.leftMouseUp, blankPointer))
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
        return ["sparse scroll blank space reaches and moves through its drag region", "queued local coordinates cannot move the screen grab point", "repeated drag events do not accumulate movement", "direction reversals return to the starting position", "mouse-up ends dragging and a new grab resets the offset"]
    }
}
#endif
