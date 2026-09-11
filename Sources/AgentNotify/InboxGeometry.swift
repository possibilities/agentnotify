import AppKit

enum InboxGeometry {
    static func nearestScreen(to anchor: NSRect) -> NSScreen? {
        func distance(_ screen: NSScreen) -> CGFloat {
            let x = max(screen.frame.minX - anchor.midX, 0, anchor.midX - screen.frame.maxX)
            let y = max(screen.frame.minY - anchor.midY, 0, anchor.midY - screen.frame.maxY)
            return x * x + y * y
        }
        return NSScreen.screens.min { distance($0) < distance($1) }
    }

    // Auto-hide moves the real status-item window above the screen and clears
    // its `screen`. Project an on-screen anchor for the panel and its pointer,
    // even when the item is hidden; no positioning window is needed.
    static func visibleAnchor(_ raw: NSRect, screen: NSRect, topInset: CGFloat) -> NSRect {
        let top = screen.maxY - topInset
        let width = min(max(raw.width, 1), screen.width)
        let y = min(max(raw.minY, screen.minY), top - 1)
        return NSRect(x: min(max(raw.minX, screen.minX), screen.maxX - width), y: y,
                      width: width, height: max(1, min(raw.height, top - y)))
    }
}
