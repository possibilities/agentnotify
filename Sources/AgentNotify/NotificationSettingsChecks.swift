#if DEBUG
import AppKit
import NotifyCore

enum NotificationSettingsChecks {
    static func run() throws -> [String] {
        let center = NotificationCenter()
        var visible = false, reads = 0
        let observation = NotificationSettingsObservation(center: center, interval: 0.02,
            shouldPoll: { visible }, refresh: { reads += 1 })
        defer { observation.stop() }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.12)) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NotifyError("internal_error", message) }
        }
        observation.start()
        settle()
        try require(reads == 0, "Settings observation polled while no relevant UI was visible.")
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        try require(reads == 1, "App activation did not refresh notification settings.")
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try require(reads == 2, "Wake did not refresh notification settings.")
        visible = true
        observation.updatePolling()
        settle()
        try require(reads > 2, "Visible UI did not refresh notification settings without an app switch.")
        visible = false
        let beforeHidden = reads
        settle()
        try require(reads == beforeHidden, "Closing relevant UI left settings polling active.")
        visible = true
        observation.start()
        observation.start()
        let beforeActivation = reads
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        try require(reads == beforeActivation + 1, "Restarting settings observation duplicated observers.")
        observation.stop()
        let beforeStop = reads
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        settle()
        try require(reads == beforeStop, "Stopping observation left a timer or observer active.")
        return ["activation and wake refresh notification settings", "visible UI polls for external settings changes", "hidden UI stops polling", "observation restart and cleanup do not leak callbacks"]
    }
}
#endif
