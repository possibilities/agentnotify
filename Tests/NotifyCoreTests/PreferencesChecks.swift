import Foundation
import NotifyCore

final class PreferencesChecks: StoreTestsBase {
    func shortcutMigrationPersistenceClearingAndValidation() throws {
        let legacy = try JSON.decode(AppPreferences.self, [
            "arrivalStyle": "compact-toast",
            "showBannerReminder": false,
            "revision": 8,
        ])
        expectEqual(legacy.completeAllShortcut, AppPreferences.defaultCompleteAllShortcut)
        let explicitlyCleared = try JSON.decode(AppPreferences.self, [
            "completeAllShortcut": NSNull(),
            "revision": 3,
        ])
        expectNil(explicitlyCleared.completeAllShortcut)
        let malformedStored = try JSON.decode(AppPreferences.self, [
            "completeAllShortcut": ["keyCode": -1, "key": "D", "modifiers": ["command", "option"]],
            "revision": 4,
        ])
        expectNil(malformedStored.completeAllShortcut)

        let initial = try store.perform("preferences", params: [:])
        expectEqual(try JSON.decode(AppPreferences.self, initial).completeAllShortcut,
            AppPreferences.defaultCompleteAllShortcut)
        let supplied: [String: Any] = [
            "keyCode": 53,
            "key": "⎋",
            "modifiers": ["command", "control"],
        ]
        let assigned = try store.perform("setPreferences", params: [
            "completeAllShortcut": supplied,
            "expectedRevision": 1,
        ])
        expectEqual(assigned["revision"] as? Int, 2)
        expectEqual((assigned["completeAllShortcut"] as? [String: Any])?["keyCode"] as? Int, 53)
        expectEqual((assigned["completeAllShortcut"] as? [String: Any])?["key"] as? String, "⎋")
        expectEqual((assigned["completeAllShortcut"] as? [String: Any])?["modifiers"] as? [String], ["control", "command"])

        store = try Store(paths: NotifyPaths(root: root))
        expectEqual(try store.preferences().completeAllShortcut, GlobalShortcut(
            keyCode: 53,
            key: "⎋",
            modifiers: ["control", "command"]
        ))
        expectEqual(try store.preferences().revision, 2)

        let unchanged = try store.perform("setPreferences", params: ["completeAllShortcut": supplied, "expectedRevision": 2])
        expectEqual(unchanged["revision"] as? Int, 2)
        let cleared = try store.perform("setPreferences", params: ["completeAllShortcut": NSNull(), "expectedRevision": 2])
        expectEqual(cleared["revision"] as? Int, 3)
        expectTrue(cleared["completeAllShortcut"] is NSNull)
        expectNil(try store.preferences().completeAllShortcut)
        let stillClear = try store.perform("setPreferences", params: ["completeAllShortcut": NSNull(), "expectedRevision": 3])
        expectEqual(stillClear["revision"] as? Int, 3)

        let invalid: [Any] = [
            "not-an-object",
            ["keyCode": 2, "key": "D"],
            ["keyCode": 2, "key": "D", "modifiers": ["option", "command"], "extra": true],
            ["keyCode": -1, "key": "D", "modifiers": ["option", "command"]],
            ["keyCode": 128, "key": "D", "modifiers": ["option", "command"]],
            ["keyCode": 2.5, "key": "D", "modifiers": ["option", "command"]],
            ["keyCode": true, "key": "D", "modifiers": ["option", "command"]],
            ["keyCode": 2, "key": "", "modifiers": ["option", "command"]],
            ["keyCode": 2, "key": "abcdefghijklmnopq", "modifiers": ["option", "command"]],
            ["keyCode": 2, "key": "D", "modifiers": ["command"]],
            ["keyCode": 2, "key": "D", "modifiers": ["command", "command"]],
            ["keyCode": 2, "key": "D", "modifiers": ["option", "hyper"]],
            ["keyCode": 2, "key": "D", "modifiers": "option,command"],
        ]
        for value in invalid {
            expectThrows(try store.perform("setPreferences", params: ["completeAllShortcut": value]))
        }
        expectEqual(try store.preferences().revision, 3)
        expectNil(try store.preferences().completeAllShortcut)
    }

    func bannerReminderMigrationAndIndependentUpdates() throws {
        let legacy = try JSON.decode(AppPreferences.self, ["arrivalStyle": "queue-shelf", "revision": 9])
        expectFalse(legacy.showBannerReminder)
        expectEqual(legacy.arrivalStyle, .queueShelf)
        let legacyEnabled = try JSON.decode(AppPreferences.self, ["showBannerReminder": true, "revision": 4])
        expectTrue(legacyEnabled.showBannerReminder)
        let retained = try store.perform("setPreferences", params: ["showBannerReminder": true, "expectedRevision": 1])
        expectEqual(retained["revision"] as? Int, 2)
        store = try Store(paths: NotifyPaths(root: root))
        expectTrue(try store.preferences().showBannerReminder)
        expectEqual(try store.preferences().arrivalStyle, .queuePeek)
        _ = try store.perform("setPreferences", params: ["arrivalStyle": "compact-toast", "expectedRevision": 2])
        expectTrue(try store.preferences().showBannerReminder)
        expectThrows(try store.perform("setPreferences", params: ["showBannerReminder": false, "expectedRevision": 2]))
        expectThrows(try store.perform("setPreferences", params: ["showBannerReminder": "false"]))
        expectThrows(try store.perform("setPreferences", params: ["expectedRevision": 3]))
        let same = try store.perform("setPreferences", params: ["showBannerReminder": true])
        expectEqual(same["revision"] as? Int, 3)
        let both = try store.perform("setPreferences", params: ["showBannerReminder": false, "arrivalStyle": "queue-shelf", "expectedRevision": 3])
        expectEqual(both["revision"] as? Int, 4)
        expectFalse(try store.preferences().showBannerReminder)
        expectEqual(try store.cursor(), 0)
    }

    func persistenceAndIsolation() throws {
        let notice = try store.perform("send", params: ["message": "Keep this task"])
        let cursor = try store.cursor()
        expectEqual(try store.preferences(), AppPreferences())
        let update = try store.perform("setPreferences", params: ["arrivalStyle": "compact-toast", "expectedRevision": 1, "requestId": "style-1"])
        expectEqual(update["revision"] as? Int, 2)
        store = try Store(paths: NotifyPaths(root: root))
        expectEqual(try store.preferences().arrivalStyle, .compactToast)
        expectEqual(try store.preferences().revision, 2)
        expectEqual(try store.cursor(), cursor)
        expectEqual(try store.all().count, 1)
        expectEqual(try store.get(notice["id"] as! String).revision, 1)
    }

    func conflictsAndReplay() throws {
        let first: [String: Any] = ["arrivalStyle": "compact-toast", "expectedRevision": 1, "requestId": "first"]
        _ = try store.perform("setPreferences", params: first)
        _ = try store.perform("setPreferences", params: ["arrivalStyle": "queue-shelf", "expectedRevision": 2])
        let replay = try store.perform("setPreferences", params: first)
        expectEqual(replay["arrivalStyle"] as? String, "compact-toast")
        expectEqual(try store.preferences().arrivalStyle, .queueShelf)
        expectEqual(try store.preferences().revision, 3)
        expectThrows(try store.perform("setPreferences", params: ["arrivalStyle": "queue-peek", "expectedRevision": 2]))
        expectThrows(try store.perform("setPreferences", params: ["arrivalStyle": "unknown"]))
        expectThrows(try store.perform("setPreferences", params: ["arrivalStyle": true]))
        expectThrows(try store.perform("setPreferences", params: ["arrivalStyle": "queue-peek", "invented": "setting"]))
        let unchanged = try store.perform("setPreferences", params: ["arrivalStyle": "queue-shelf", "expectedRevision": 3])
        expectEqual(unchanged["revision"] as? Int, 3)
        expectEqual(try store.cursor(), 0)
    }

    func concurrentClientsAndServiceRouting() throws {
        let service = NotifyService(store: store)
        var changed = 0, notificationsChanged = 0, shown = false
        service.onPreferencesChange = { changed += 1 }
        service.onChange = { notificationsChanged += 1 }
        expectThrows(try service.call("showPreferences"))
        service.onShowPreferences = { shown = true }
        _ = try service.call("showPreferences")
        expectTrue(shown)
        _ = try service.call("setPreferences", ["arrivalStyle": "queue-shelf"])
        expectEqual(changed, 1)
        expectEqual(notificationsChanged, 0)
        let resultLock = NSLock()
        var successes = 0
        DispatchQueue.concurrentPerform(iterations: 8) { index in
            do {
                let client = try Store(paths: NotifyPaths(root: root))
                _ = try client.perform("setPreferences", params: ["arrivalStyle": index % 2 == 0 ? "compact-toast" : "queue-peek", "expectedRevision": 2])
                resultLock.lock(); successes += 1; resultLock.unlock()
            } catch {}
        }
        expectEqual(successes, 1)
        expectEqual(try store.preferences().revision, 3)
    }
}

// One disposable store per check; never the operator's state directory.
class StoreTestsBase: CheckCase {
    var root: URL!
    var store: Store!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("an-preferences-\(UUID().uuidString)")
        store = try Store(paths: NotifyPaths(root: root))
    }
    override func tearDownWithError() throws { store = nil; try FileManager.default.removeItem(at: root) }
}
