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

    static func arrivalFrame(size: NSSize, on screen: NSRect) -> NSRect {
        let width = min(size.width, screen.width - 26)
        let height = min(size.height, screen.height - 26)
        return NSRect(x: screen.midX - width / 2, y: screen.maxY - 13 - height,
                      width: width, height: height)
    }

    // Center the inbox horizontally and put its center slightly above the
    // display's midpoint, without letting a tall window escape the safe area.
    static func inboxFrame(size: NSSize, on screen: NSRect) -> NSRect {
        let width = min(size.width, screen.width - 26)
        let height = min(size.height, screen.height - 26)
        let idealY = screen.midY + screen.height * 0.1 - height / 2
        let y = max(screen.minY + 13, min(idealY, screen.maxY - 13 - height))
        return NSRect(x: screen.midX - width / 2, y: y, width: width, height: height)
    }
}
