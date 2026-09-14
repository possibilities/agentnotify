import Foundation
import NotifyCore

final class TimestampChecks {
    let locale = Locale(identifier: "en_US")
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    let now = Date(timeIntervalSince1970: 1_736_942_400) // 2025-01-15 12:00 UTC

    func testRelativeDirectionAndUnits() {
        func label(_ delta: Double) -> String {
            NotificationTimestamp.relative(createdAt: now.timeIntervalSince1970 + delta, now: now, locale: locale, calendar: calendar)
        }
        for delta in [-59.9, -0.1, 0, 0.1, 59.9] { expectEqual(label(delta), "now") }
        for (seconds, unit) in [(60.0, "m"), (3600, "h"), (86400, "d"), (604800, "w")] {
            expectEqual(label(-seconds), "1\(unit) ago")
            expectEqual(label(seconds), "in 1\(unit)")
        }
        for (component, unit) in [(Calendar.Component.month, "mo"), (.year, "y")] {
            let date = calendar.date(byAdding: component, value: -1, to: now)!
            expectEqual(NotificationTimestamp.relative(createdAt: date.timeIntervalSince1970, now: now, locale: locale, calendar: calendar), "1\(unit) ago")
        }
    }

    func testClockAdvancementAndTimeZones() {
        let created = now.timeIntervalSince1970
        expectEqual(NotificationTimestamp.relative(createdAt: created, now: now, locale: locale), "now")
        expectEqual(NotificationTimestamp.relative(createdAt: created, now: now.addingTimeInterval(120), locale: locale), "2m ago")
        let utc = NotificationTimestamp.exact(createdAt: created, locale: locale, timeZone: TimeZone(secondsFromGMT: 0)!)
        let newYork = NotificationTimestamp.exact(createdAt: created, locale: locale, timeZone: TimeZone(identifier: "America/New_York")!)
        expectTrue(utc.contains("January 15, 2025"))
        expectTrue(utc.contains("12:00:00"))
        expectTrue(newYork.contains("7:00:00"))
        expectTrue(newYork.contains("EST"))
    }

    func testMutationsPreserveCreationTime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("an-time-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(paths: NotifyPaths(root: root))
        let created = now.timeIntervalSince1970
        let item = try JSON.decode(NotificationRecord.self, store.perform("send", params: ["message": "Timestamp fixture"], now: created))
        for (index, state) in ["read", "done", "reopen"].enumerated() {
            let updated = created + Double(index + 1) * 120
            _ = try store.perform("status", params: ["id": item.id, "state": state], now: updated)
            let changed = try store.get(item.id)
            expectEqual(changed.createdAt, created)
            expectEqual(try JSON.decode(NotificationRecord.self, JSON.encode(changed)).createdAt, created)
            expectEqual(changed.updatedAt, updated)
            expectEqual(NotificationTimestamp.relative(createdAt: changed.createdAt, now: Date(timeIntervalSince1970: updated), locale: locale), "\((index + 1) * 2)m ago")
        }
    }
}
