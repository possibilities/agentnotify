import Foundation

/// Consumes the durable change stream and finds lifecycle events that merit a compact
/// arrival presentation. Seed `cursor` from the store before starting change delivery;
/// this makes the existing inbox a baseline rather than replaying it at launch.
public final class ArrivalTracker {
    public private(set) var cursor: Int

    public init(cursor: Int) {
        self.cursor = cursor
    }

    /// Consumes a contiguous, ascending page returned by the `changes` operation.
    /// Replayed changes at or behind the current cursor are harmless. Results preserve event
    /// order so a presenter can coalesce the batch and choose its final item as the lead.
    public func consume(_ changes: [[String: Any]]) throws -> [NotificationRecord] {
        var nextCursor = cursor
        var arrivals: [NotificationRecord] = []

        for change in changes {
            guard let changeCursor = change["cursor"] as? Int else {
                throw NotifyError("invalid_request", "A notification change is missing its integer cursor.")
            }
            if changeCursor <= nextCursor { continue }
            guard changeCursor == nextCursor + 1 else {
                throw NotifyError("invalid_cursor", "Notification changes must be consumed in contiguous cursor order.")
            }
            guard let kind = change["kind"] as? String,
                  let value = change["notification"] as? [String: Any] else {
                throw NotifyError("invalid_request", "A notification change is missing its kind or snapshot.")
            }
            let record = try JSON.decode(NotificationRecord.self, value)
            nextCursor = changeCursor

            guard (kind == "created" || kind == "due"),
                  record.status == "active",
                  record.presentable else { continue }
            arrivals.append(record)
        }

        cursor = nextCursor
        return arrivals
    }
}
