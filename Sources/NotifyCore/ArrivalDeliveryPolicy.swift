public enum ArrivalDeliveryPolicy {
    /// Chooses the compact in-app arrival surface only when macOS cannot own
    /// the visual arrival. Unknown authorization is held until settings load.
    public static func shouldShowCompact(authorization: String, alertsEnabled: Bool) -> Bool {
        switch authorization {
        case "authorized", "provisional":
            return !alertsEnabled
        case "denied", "not-determined":
            return true
        default:
            return false
        }
    }
}
