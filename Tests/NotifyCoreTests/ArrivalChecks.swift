import Foundation
import NotifyCore

final class ArrivalChecks: CheckCase {
    private func record(
        id: String,
        createdAt: Double,
        status: String = "active",
        scheduledAt: Double? = nil,
        snoozedUntil: Double? = nil,
        readAt: Double? = nil,
        revision: Int = 1,
        response: Response? = nil,
        delivery: String = "pending",
        nativeRegistered: Bool = false,
        presentable: Bool = true
    ) throws -> NotificationRecord {
        var value: [String: Any] = [
            "id": id,
            "title": "Build",
            "subtitle": "",
            "message": "Build finished",
            "group": "",
            "actions": [],
            "timeSensitive": false,
            "createdAt": createdAt,
            "updatedAt": createdAt,
            "status": status,
            "revision": revision,
            "delivery": delivery,
            "nativeRegistered": nativeRegistered,
            "presentable": presentable
        ]
        if let scheduledAt { value["scheduledAt"] = scheduledAt }
        if let snoozedUntil { value["snoozedUntil"] = snoozedUntil }
        if let readAt { value["readAt"] = readAt }
        if let response { value["response"] = try JSON.encode(response) }
        return try JSON.decode(NotificationRecord.self, value)
    }

    private func change(_ cursor: Int, _ kind: String, _ record: NotificationRecord) throws -> [String: Any] {
        ["cursor": cursor, "kind": kind, "notification": try JSON.encode(record)]
    }

    func testStartupCursorDoesNotReplayBacklog() throws {
        let tracker = ArrivalTracker(cursor: 8)
        let old = try record(id: "old", createdAt: 10)
        expectTrue(try tracker.consume([change(8, "created", old)]).isEmpty)
        expectEqual(tracker.cursor, 8)
    }

    func testFreshArrivalsCoalesceInEventOrderAndReplaySafely() throws {
        let tracker = ArrivalTracker(cursor: 0)
        let older = try record(id: "older", createdAt: 10)
        let newer = try record(id: "newer", createdAt: 11)
        let page = try [change(1, "created", older), change(2, "created", newer)]
        expectEqual(try tracker.consume(page).map(\.id), ["older", "newer"])
        expectEqual(tracker.cursor, 2)
        expectTrue(try tracker.consume(page).isEmpty)
    }

    func testReadAndDeliveryChangesStaySilent() throws {
        let tracker = ArrivalTracker(cursor: 4)
        let read = try record(id: "one", createdAt: 10, readAt: 11, revision: 2)
        let delivered = try record(id: "one", createdAt: 10, readAt: 11, revision: 3, delivery: "accepted", nativeRegistered: true)
        expectTrue(try tracker.consume([change(5, "read", read), change(6, "delivery", delivered)]).isEmpty)
        expectEqual(tracker.cursor, 6)
    }

    func testGroupReplacementEmitsOnlyCreatedReplacement() throws {
        let tracker = ArrivalTracker(cursor: 10)
        let old = try record(id: "old", createdAt: 10, status: "superseded", revision: 2)
        let replacement = try record(id: "new", createdAt: 11)
        expectEqual(try tracker.consume([change(11, "superseded", old), change(12, "created", replacement)]).map(\.id), ["new"])
    }

    func testFutureScheduleStaysSilentUntilDurableDueChange() throws {
        let tracker = ArrivalTracker(cursor: 0)
        let scheduled = try record(id: "later", createdAt: 10, status: "scheduled", scheduledAt: 20)
        let due = try record(id: "later", createdAt: 10, scheduledAt: 20, revision: 2)
        expectTrue(try tracker.consume([change(1, "created", scheduled)]).isEmpty)
        expectEqual(try tracker.consume([change(2, "due", due)]).map(\.id), ["later"])
    }

    func testDueSnoozedTaskCanArriveWithExistingResponse() throws {
        let tracker = ArrivalTracker(cursor: 20)
        let timeout = try JSON.decode(Response.self, [
            "kind": "timeout", "value": "@TIMEOUT", "exitCode": 6, "at": 10
        ])
        let due = try record(id: "todo", createdAt: 1, revision: 4, response: timeout, presentable: true)
        expectEqual(try tracker.consume([change(21, "due", due)]).map(\.id), ["todo"])
    }

    func testReopenAndResolvedOrHiddenChangesStaySilent() throws {
        let tracker = ArrivalTracker(cursor: 0)
        let reopened = try record(id: "reopened", createdAt: 1, revision: 2)
        let done = try record(id: "done", createdAt: 2, status: "done")
        let hidden = try record(id: "hidden", createdAt: 3, presentable: false)
        let page = try [
            change(1, "reopen", reopened),
            change(2, "created", done),
            change(3, "created", hidden)
        ]
        expectTrue(try tracker.consume(page).isEmpty)
    }

    func testCursorGapFailsWithoutAdvancing() throws {
        let tracker = ArrivalTracker(cursor: 5)
        let item = try record(id: "gap", createdAt: 10)
        expectThrows(try tracker.consume([change(7, "created", item)]))
        expectEqual(tracker.cursor, 5)
    }
}
