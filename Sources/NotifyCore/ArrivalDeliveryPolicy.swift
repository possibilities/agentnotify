public enum ArrivalDeliveryPolicy {
    /// AgentNotify's own arrival is the primary presentation. Native banners
    /// are an optional additional projection and may be hidden by Focus,
    /// screen sharing, or other system presentation policy.
    public static func shouldShowCompact(authorization _: String, alertsEnabled _: Bool) -> Bool {
        true
    }
}
