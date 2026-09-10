#if DEBUG
import AppKit
import NotifyCore

enum ArrivalPresentationChecks {
    static func run(output: URL) throws -> [String] {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NotifyError("internal_error", message) }
        }
        func settle(_ duration: Double) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("arrival-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(paths: NotifyPaths(root: root))
        let first = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["title": "Build finished", "message": "All checks passed. Ready for a closer look.", "group": "AgentNotify"]))
        let second = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["title": "Review is ready", "message": "The final diff is waiting for you."]))
        let cursor = try store.cursor()
        let presenter = ArrivalPresentation()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        presenter.placement = { size in NSRect(x: screen.minX + 12, y: screen.minY + 12, width: size.width, height: size.height) }
        defer { presenter.dismiss() }
        let keyWindow = NSApp.keyWindow
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        presenter.receive([first], items: [first, second])
        try require(presenter.isVisible && presenter.displayedID == first.id, "Arrival failed to appear.")
        try require(presenter.panel?.canBecomeKey == false && NSApp.keyWindow === keyWindow,
            "Arrival took keyboard focus.")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost, "Arrival activated the app.")
        presenter.receive([second], items: [first, second])
        settle(0.3)
        try require(presenter.isVisible && presenter.displayedID == second.id && presenter.newCount == 2,
            "A burst did not reuse the visible panel for its latest arrival.")
        if let panel = presenter.panel { try PreviewRenderer.capture(panel, output.appendingPathComponent("native-arrival.png"), width: ArrivalView.preferredSize.width, height: ArrivalView.preferredSize.height) }
        settle(0.3)
        try require(presenter.isVisible, "An unattended arrival expired without being dismissed.")
        var opened: String?
        presenter.open = { opened = $0 }
        presenter.openDisplayed(second.id)
        try require(opened == second.id && !presenter.isVisible, "Opening did not pass the displayed identity and hide the preview.")
        try require(try store.cursor() == cursor && store.get(first.id).readAt == nil && store.get(first.id).response == nil,
            "Preview lifecycle changed durable task state.")
        presenter.receive([first], items: [first, second])
        presenter.dismiss()
        try require(!presenter.isVisible, "Explicit dismissal left the arrival visible.")
        presenter.receive([second], items: [first, second])
        settle(0.12)
        try require(presenter.isVisible && presenter.displayedID == second.id, "A new arrival did not appear after explicit dismissal.")
        presenter.refresh([])
        try require(!presenter.isVisible, "Withdrawn notifications left a stale preview.")
        presenter.receive([first], items: [first])
        var superseded = first; superseded.status = "superseded"
        presenter.receive([second], items: [superseded, second])
        try require(presenter.isVisible && presenter.displayedID == second.id && presenter.newCount == 1,
            "Group replacement did not advance the shared panel to its latest arrival.")
        let unreadOnly = ArrivalContent(id: "summary", title: "", subtitle: "", message: "", group: "",
            newCount: 1, unreadCount: 10, waitingCount: 10)
        try require(unreadOnly.queueSummary == "10 unread notifications", "Unread-only summary is not concise.")
        let mixed = ArrivalContent(id: "summary", title: "", subtitle: "", message: "", group: "",
            newCount: 3, unreadCount: 10, waitingCount: 12)
        try require(mixed.queueSummary == "Latest of 3 arrivals  ·  10 unread notifications  ·  2 read still need attention",
            "Burst summary does not distinguish unread and read items needing attention.")
        let sharedPanel = presenter.panel
        for style in ArrivalStyle.allCases {
            presenter.dismiss()
            presenter.style = style
            presenter.receive([first], items: [first, second])
            settle(0.03)
            try require(presenter.displayedStyle == style && presenter.panel?.frame.size == style.size, "Arrival style has the wrong renderer or dimensions.")
            try require(presenter.panel === sharedPanel && presenter.panel?.canBecomeKey == false, "Switching styles replaced the panel or allowed focus.")
            let frame = presenter.panel?.frame
            let next: ArrivalStyle = style == .queuePeek ? .compactToast : .queuePeek
            presenter.style = next
            presenter.receive([second], items: [first, second])
            try require(presenter.displayedStyle == style && presenter.panel?.frame == frame && presenter.displayedID == second.id,
                "Changing preference moved the panel or kept it from showing the latest arrival.")
            if let panel = presenter.panel { try PreviewRenderer.capture(panel, output.appendingPathComponent("native-arrival-\(style.rawValue).png"), width: style.size.width, height: style.size.height) }
            presenter.openDisplayed(second.id)
            try require(opened == second.id && !presenter.isVisible, "A styled arrival opened the wrong notification.")
            presenter.receive([second], items: [first, second])
            try require(presenter.displayedStyle == next, "The next arrival did not adopt the saved preference.")
        }
        try require(try store.cursor() == cursor, "Style preferences mutated notification state.")
        return ["arrival does not activate or take focus", "bursts reuse one panel and show the latest arrival", "unattended preview remains until dismissal", "open passes displayed identity without a durable mutation", "explicit dismissal allows the next arrival", "withdrawal hides stale presentation", "group replacement advances to the latest eligible arrival", "summary distinguishes unread from read items still needing attention", "all three designs share one nonactivating panel at their intended dimensions", "preference changes preserve the active panel and apply to the next presentation"]
    }
}
#endif
