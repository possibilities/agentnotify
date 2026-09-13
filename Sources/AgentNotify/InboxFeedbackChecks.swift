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
        try require(model.undoCompletion?.items.count == 3, "Whole-Inbox completion did not retain its exact Undo batch.")
        model.undo()
        try require(model.inboxCount == 3 && (try store.get(prompt.id)).response?.kind == "close",
            "Undo must reopen completed tasks without erasing a durable prompt response.")

        // Combine category, query, group and time filters; a newly arriving item
        // after the snapshot must not be swept into completion or its Undo.
        _ = try store.perform("status", params: ["id": first.id, "state": "unread"])
        _ = try store.perform("status", params: ["id": second.id, "state": "unread"])
        let filtered = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["title": "Scoped task", "message": "target", "group": "scope"]))
        let old = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["message": "target", "group": "old"], now: 1000))
        model.refresh(); model.filter = "unread"; model.query = "target"; model.group = "scope"; model.period = "today"
        let newcomer = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["message": "target new"]))
        model.completeVisible()
        try require(model.undoCompletion?.items.map(\.id) == [filtered.id], "Completion ignored visible filters.")
        model.filter = "all"; model.group = nil; model.query = ""; model.period = "any"
        model.undo()
        try require(try store.get(filtered.id).isInbox && store.get(newcomer.id).revision == newcomer.revision && store.get(old.id).revision == old.revision,
            "Undo changed a notification outside its exact completion batch.")

        // Later and history can be visible in All but never become bulk targets.
        model.refresh(); model.filter = "all"
        model.completeVisible()
        try require(try store.get(scheduled.id).status == "scheduled", "Visible Later notification was completed.")
        _ = try store.perform("status", params: ["id": first.id, "state": "reopen"])
        _ = try store.perform("status", params: ["id": first.id, "state": "done"])
        let intervening = try store.get(first.id)
        model.undo()
        try require(try store.get(first.id).revision == intervening.revision && store.get(first.id).status == "done" && store.get(second.id).isInbox,
            "Undo overwrote an intervening completion or skipped unchanged batch members.")
        try require(model.error?.contains("left unchanged") == true, "Conflicting Undo gave no feedback.")

        // A stale visible snapshot fails atomically and retains the prior Undo.
        model.error = nil; model.filter = "inbox"; model.refresh()
        let prior = model.items.first { $0.isInbox }!
        model.done(prior)
        let previousUndo = model.undoItem
        let stale = model.visible.first!
        _ = try store.perform("status", params: ["id": stale.id, "state": "read"])
        let beforeFailure = try store.cursor()
        model.completeVisible()
        try require(try store.cursor() == beforeFailure && model.undoItem?.id == previousUndo?.id && model.error != nil,
            "A failed bulk transaction changed state or replaced earlier Undo feedback.")

        // More than the service's 100-reference cap still has one exact Undo.
        model.undoCompletion = nil; model.query = "large fixture"; model.group = nil
        for i in 0..<105 { _ = try store.perform("send", params: ["message": "large fixture \(i)"]) }
        model.refresh(); model.completeVisible()
        try require(model.undoCompletion?.items.count == 105 && model.visible.isEmpty, "Large completion was truncated at the service batch limit.")
        model.undo()
        try require(model.visible.count == 105 && model.undoCompletion == nil, "One Undo did not restore the entire large completion.")
        // Race the second transaction after the first 100 completions commit.
        let laterBatchID = model.visible.last!.id
        var injected = false
        var injectionError: Error?
        model.service?.onChange = {
            guard !injected else { return }
            injected = true
            do { _ = try store.perform("status", params: ["id": laterBatchID, "state": "read"]) }
            catch { injectionError = error }
        }
        model.error = nil; model.completeVisible(); model.service?.onChange = nil
        try require(injectionError == nil && model.undoCompletion?.items.count == 100 && model.visible.count == 5 && model.error != nil,
            "A later batch conflict lost successful completions or their Undo.")
        model.undo()
        try require(model.visible.count == 105, "Undo did not restore successful work after a partial bulk failure.")

        // A conflict arriving during Undo retains the unfinished references.
        model.completeVisible()
        let duringUndoID = model.undoCompletion!.items.last!.id
        injected = false
        model.service?.onChange = {
            guard !injected else { return }
            injected = true
            do { _ = try store.perform("status", params: ["id": duringUndoID, "state": "read"]) }
            catch { injectionError = error }
        }
        model.undo(); model.service?.onChange = nil
        try require(injectionError == nil && model.visible.count == 100 && model.undoCompletion?.items.count == 5,
            "A conflict during Undo discarded the unfinished batch.")
        model.undo()
        try require(model.visible.count == 104 && model.undoCompletion == nil && (try store.get(duringUndoID)).status == "done",
            "Retrying Undo overwrote an intervening change or missed unchanged remaining items.")
        model.filter = "later"; model.refresh(); model.completeVisible()
        try require(model.undoCompletion == nil, "A view with no active notifications created false completion feedback.")
        return ["completion confirmation expires", "new completion resets expiry", "expiry changes no durable notification state", "undo and explicit hide cancel expiry", "complete all clears only the active inbox and closes prompts", "filtered completion and exact batch Undo", "Undo preserves durable prompt responses", "Undo preserves intervening changes", "stale completion is atomic and retains earlier Undo", "large batch completion and one Undo", "empty eligible scope is a no-op", "partial completion retains exact successful Undo", "Undo race retains unfinished references"]
    }
}
#endif
