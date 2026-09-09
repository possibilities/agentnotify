import Foundation
import NotifyCore

final class PreferencesChecks: StoreTestsBase {
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
