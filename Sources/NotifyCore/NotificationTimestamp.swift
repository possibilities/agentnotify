import Foundation

/// Presentation of the persisted Unix-seconds creation time, independent of mutations.
public enum NotificationTimestamp {
    public static func relative(createdAt: Double, now: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let date = Date(timeIntervalSince1970: createdAt)
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        // Numeric zero is rendered as “in 0s”. Use the localized named present,
        // and suppress ticking seconds for notifications less than a minute old.
        if abs(date.timeIntervalSince(now)) < 60 {
            formatter.dateTimeStyle = .named
            return formatter.localizedString(from: DateComponents(second: 0))
        }
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: now)
    }

    public static func exact(createdAt: Double, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        return formatter.string(from: Date(timeIntervalSince1970: createdAt))
    }
}
