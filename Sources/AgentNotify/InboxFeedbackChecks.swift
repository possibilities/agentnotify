#if DEBUG
import AppKit
import NotifyCore

enum InboxFeedbackChecks {
    static func run() throws -> [String] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-feedback-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(paths: NotifyPaths(root: root))
        let model = InboxModel(undoDuration: 0.2)
        model.service = NotifyService(store: store)
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NotifyError("internal_error", message) }
        }
        func wait(_ duration: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
        let first = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["title": "First task", "message": "Test one"]))
        let second = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["title": "Second task", "message": "Test two"]))
        model.done(first)
        wait(0.12)
        model.done(second)
        let cursor = try store.cursor()
        wait(0.12)
        try require(model.undoItem?.id == second.id, "An earlier timeout hid a newer completion.")
        wait(0.12)
        try require(model.undoItem == nil, "Completion confirmation did not expire.")
        try require(try store.get(first.id).status == "done" && store.get(second.id).status == "done" && store.cursor() == cursor,
            "Hiding expired feedback changed durable task state.")
        _ = try store.perform("status", params: ["id": first.id, "state": "reopen"])
        model.done(try store.get(first.id)); model.undo()
        wait(0.24)
        try require(try model.undoItem == nil && store.get(first.id).status == "active", "Undo failed or left a stale confirmation timer.")
        model.done(try store.get(first.id)); model.undoItem = nil
        wait(0.24)
        try require(try model.undoItem == nil && store.get(first.id).status == "done", "Hiding confirmation reopened a task.")
        _ = try store.perform("status", params: ["id": first.id, "state": "reopen"])
        _ = try store.perform("status", params: ["id": second.id, "state": "reopen"])
        let prompt = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["message": "Choose", "actions": ["Keep"]]))
        let scheduled = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["message": "Later", "in": "1h"]))
        model.refresh()
        try require(model.inboxCount == 3, "Complete All fixture has the wrong Inbox scope.")
        model.completeAll()
        let completedFirst = try store.get(first.id), completedSecond = try store.get(second.id)
        let completedPrompt = try store.get(prompt.id), untouchedSchedule = try store.get(scheduled.id)
        try require(model.inboxCount == 0 && completedFirst.status == "done" && completedSecond.status == "done",
            "Complete All did not clear the active Inbox.")
        try require(completedPrompt.response?.kind == "close" && untouchedSchedule.status == "scheduled",
            "Complete All ran or skipped the wrong lifecycle transitions.")
        return ["completion confirmation expires", "new completion resets expiry", "expiry changes no durable notification state", "undo and explicit hide cancel expiry", "complete all clears only the active inbox and closes prompts"]
    }
}
#endif
