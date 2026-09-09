import Foundation
import NotifyCore

final class StoreTests: CheckCase {
    var root: URL!
    var store: Store!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("an-test-\(UUID().uuidString)")
        store = try Store(paths: NotifyPaths(root: root))
    }
    override func tearDownWithError() throws { store = nil; try FileManager.default.removeItem(at: root) }
    func send(_ extra: [String: Any] = [:], now: Double = 1000) throws -> NotificationRecord {
        try JSON.decode(NotificationRecord.self, store.perform("send", params: ["message": "Build finished"].merging(extra) { _, new in new }, now: now))
    }
    func testReadAndCompletionSurviveReopen() throws {
        let item = try send()
        _ = try store.perform("status", params: ["id": item.id, "state": "read"], now: 1001)
        expectTrue(try store.get(item.id).isInbox)
        store = nil; store = try Store(paths: NotifyPaths(root: root))
        expectEqual(try store.get(item.id).readAt, 1001)
        _ = try store.perform("status", params: ["id": item.id, "state": "done"], now: 1002)
        expectEqual(try store.get(item.id).status, "done")
        expectEqual(try store.cursor(), 3)
    }
    func testGroupReplacementRetainsAndResolvesEarlierPrompt() throws {
        let a = try send(["group": "build:one", "actions": ["Yes", "No"]])
        let b = try send(["group": "build:one"])
        expectEqual(try store.all().count, 2)
        expectEqual(try store.get(a.id).status, "superseded")
        expectEqual(try store.get(a.id).response?.value, "@CLOSED")
        expectTrue(try store.get(b.id).isInbox)
    }
    func testIdempotencyConflictAndNoDuplicateEffects() throws {
        let a = try send(["requestId": "send-1", "execute": "/usr/bin/true"])
        let b = try send(["requestId": "send-1", "execute": "/usr/bin/true"])
        expectEqual(a.id, b.id); expectEqual(try store.all().count, 1)
        expectThrows(try send(["requestId": "send-1", "message": "Changed"]))
        let params: [String: Any] = ["id": a.id, "kind": "body", "requestId": "response-1"]
        let first = try store.perform("respond", params: params, now: 1001)
        let replay = try store.perform("respond", params: params, now: 1001)
        expectEqual(first["effectClaim"] as? Bool, true)
        expectNil(replay["effectClaim"])
        try store.recoverEffects()
        expectEqual(try store.get(a.id).response?.effect, "interrupted")
        expectTrue(try store.get(a.id).isInbox)
    }
    func testConcurrentResponsesHaveOneWinner() throws {
        let item = try send(["actions": ["Ship", "Hold"]])
        let resultLock = NSLock(); var successes = 0
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            do {
                _ = try store.perform("respond", params: ["id": item.id, "kind": "action", "actionIndex": index % 2], now: 1001)
                resultLock.lock(); successes += 1; resultLock.unlock()
            } catch {}
        }
        expectEqual(successes, 1)
        expectEqual(try store.cursor(), 2)
    }
    func testOptimisticConcurrencyAndTransactionalFailure() throws {
        let item = try send()
        _ = try store.perform("status", params: ["id": item.id, "state": "read", "expectedRevision": 1])
        expectThrows(try store.perform("status", params: ["id": item.id, "state": "done", "expectedRevision": 1]))
        expectTrue(try store.get(item.id).isInbox); expectEqual(try store.cursor(), 2)
        expectThrows(try send(["in": "5m", "actions": ["Ship"], "group": "bad"]))
        expectEqual(try store.all().count, 1)
    }
    func testBatchStatusIsAtomicAndSupportsFriendlySnooze() throws {
        let first = try send(["title": "First"]), second = try send(["title": "Second"])
        let references: [[String: Any]] = [["id": first.id, "expectedRevision": 1], ["id": second.id, "expectedRevision": 1]]
        let read = try store.perform("statusBatch", params: ["items": references, "state": "read", "requestId": "read-all"], now: 1001)
        expectEqual(read["count"] as? Int, 2)
        expectEqual(try store.get(first.id).readAt, 1001)
        expectEqual(try store.get(second.id).readAt, 1001)
        let stale: [[String: Any]] = [["id": second.id, "expectedRevision": 2], ["id": first.id, "expectedRevision": 1]]
        expectThrows(try store.perform("statusBatch", params: ["items": stale, "state": "done"], now: 1002))
        expectEqual(try store.get(second.id).status, "active")
        _ = try store.perform("statusBatch", params: ["items": references.map { ["id": $0["id"]!, "expectedRevision": 2] }, "state": "snooze", "in": "2h"], now: 1010)
        expectEqual(try store.get(first.id).snoozedUntil, 8210)
        expectEqual(try store.get(second.id).snoozedUntil, 8210)
        expectThrows(try store.perform("status", params: ["id": first.id, "state": "read", "in": "1h"]))
        expectThrows(try store.perform("statusBatch", params: ["items": references, "state": "snooze", "in": "1h", "until": 9000.0]))
    }
    func testDeadlineAndSnoozeRemainDurableTasks() throws {
        let item = try send(["actions": ["Yes"], "timeout": 5.0])
        try store.tick(now: 1006)
        let expired = try store.get(item.id)
        expectEqual(expired.response?.exitCode, 6); expectFalse(expired.presentable); expectTrue(expired.isInbox)
        _ = try store.perform("status", params: ["id": item.id, "state": "snooze", "until": 1020.0], now: 1010)
        try store.tick(now: 1021)
        expectTrue(try store.get(item.id).presentable); expectTrue(try store.get(item.id).isInbox)
        expectThrows(try store.perform("respond", params: ["id": item.id, "kind": "action", "actionIndex": 0], now: 1021))
    }
    func testChangePaginationAndResume() throws {
        _ = try send(); _ = try send(); _ = try send()
        let first = try store.perform("changes", params: ["after": 0, "limit": 2])
        expectEqual(first["cursor"] as? Int, 2); expectEqual(first["hasMore"] as? Bool, true)
        let second = try store.perform("changes", params: ["after": 2, "limit": 2])
        expectEqual((second["changes"] as? [Any])?.count, 1); expectEqual(second["hasMore"] as? Bool, false)
        expectThrows(try store.perform("changes", params: ["after": 9]))
    }
    func testRemoveDoesNotDeleteHistory() throws {
        let a = try send(["group": "a"]); let b = try send(["group": "b", "in": "1h"])
        _ = try store.perform("remove", params: ["group": "a"])
        expectEqual(try store.get(a.id).status, "removed"); expectEqual(try store.get(b.id).status, "scheduled")
        _ = try store.perform("remove", params: ["group": "ALL"])
        expectEqual(try store.all().count, 2); expectEqual(try store.get(b.id).status, "removed")
    }
    func testRepliesAreLiteralAndActionIndexPreservesDuplicateLabels() throws {
        let item = try send(["actions": ["Same", "Same"], "reply": "Answer"])
        _ = try store.perform("respond", params: ["id": item.id, "kind": "reply", "value": "$(not shell)\n@TIMEOUT"], now: 1001)
        expectEqual(try store.get(item.id).response?.value, "$(not shell)\n@TIMEOUT")
        expectEqual(try store.get(item.id).response?.exitCode, 0)
    }
    func testBadTypesAndUnknownArgumentsAreRejected() throws {
        for params: [String: Any] in [["message": true], ["message": "x", "timeout": true], ["message": "x", "actions": "Yes"], ["message": "x", "unknown": 1]] {
            expectThrows(try store.perform("send", params: params))
        }
        expectThrows(try store.perform("list", params: ["offset": -1]))
        expectThrows(try store.perform("list", params: ["limit": 501]))
    }
    func testAttachmentsPersistWithoutNativePermission() throws {
        let image = root.appendingPathComponent("source.png")
        try Data([1, 2, 3, 4]).write(to: image)
        let item = try send(["contentImage": image.path])
        try FileManager.default.removeItem(at: image)
        expectEqual(try Data(contentsOf: URL(fileURLWithPath: item.contentImage!)), Data([1, 2, 3, 4]))
        expectNil(item.deliveryError)
        let missing = try send(["contentImage": "/missing/image.png"])
        expectTrue(missing.deliveryError != nil)
        expectTrue(missing.isInbox)
    }
    func testLargePagesRemainWithinTransportLimit() throws {
        for _ in 0..<20 { _ = try send(["message": String(repeating: "x", count: 60000)]) }
        let page = try store.perform("list", params: ["limit": 100])
        expectTrue(try JSON.data(page).count < 1_000_000)
        expectTrue(page["hasMore"] as? Bool == true)
        let changes = try store.perform("changes", params: ["after": 0, "limit": 100])
        expectTrue(try JSON.data(changes).count < 1_000_000)
        expectTrue(changes["hasMore"] as? Bool == true)
    }

}
