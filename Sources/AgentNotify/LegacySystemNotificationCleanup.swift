import UserNotifications

/// Earlier AgentNotify releases projected Inbox items into Notification Center.
/// The app now owns its only arrival surface, so purge those legacy projections
/// without requesting authorization and never create replacements.
enum LegacySystemNotificationCleanup {
    static func removeAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        center.setNotificationCategories([])
    }
}
