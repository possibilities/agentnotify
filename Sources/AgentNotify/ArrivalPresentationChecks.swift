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
        let presenter = ArrivalPresentation(duration: 0.2)
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
        presenter.setHovered(true)
        presenter.receive([second], items: [first, second])
        settle(0.3)
        try require(presenter.isVisible && presenter.displayedID == first.id && presenter.newCount == 2,
            "A burst replaced the hovered target or expired under the pointer.")
        if let panel = presenter.panel { try PreviewRenderer.capture(panel, output.appendingPathComponent("native-arrival.png"), width: ArrivalView.preferredSize.width, height: ArrivalView.preferredSize.height) }
        presenter.setHovered(false)
        try require(presenter.displayedID == second.id, "Leaving did not reveal the newest arrival.")
        if !NSWorkspace.shared.isVoiceOverEnabled {
            settle(0.3)
            try require(!presenter.isVisible, "Unattended arrival did not expire.")
        }
        var opened: String?
        presenter.open = { opened = $0 }
        presenter.receive([first], items: [first, second])
        presenter.openDisplayed(first.id)
        try require(opened == first.id && !presenter.isVisible, "Opening did not pass the displayed identity and hide the preview.")
        try require(try store.cursor() == cursor && store.get(first.id).readAt == nil && store.get(first.id).response == nil,
            "Preview lifecycle changed durable task state.")
        presenter.receive([first], items: [first, second])
        presenter.setHovered(false)
        settle(0.1)
        presenter.dismiss()
        presenter.receive([second], items: [first, second])
        presenter.setHovered(false)
        settle(0.12)
        try require(presenter.isVisible && presenter.displayedID == second.id, "An old timer dismissed a newer presentation.")
        presenter.refresh([])
        try require(!presenter.isVisible, "Withdrawn notifications left a stale preview.")
        presenter.receive([first], items: [first])
        presenter.setHovered(true)
        var superseded = first; superseded.status = "superseded"
        presenter.receive([second], items: [superseded, second])
        try require(presenter.isVisible && presenter.displayedID == first.id && presenter.newCount == 1,
            "Group replacement lost the newest arrival or changed the hovered target.")
        presenter.setHovered(false)
        try require(presenter.displayedID == second.id, "Replacement did not advance after hover.")
        return ["arrival does not activate or take focus", "hover freezes target and pauses expiry", "bursts coalesce and advance on pointer exit", "unattended preview expires", "open passes displayed identity without a durable mutation", "old expiry cannot dismiss a new presentation", "withdrawal hides stale presentation", "group replacement preserves both hovered identity and the queued successor"]
    }
}
#endif
