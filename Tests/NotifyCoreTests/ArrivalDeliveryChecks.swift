import NotifyCore

final class ArrivalDeliveryChecks: CheckCase {
    func testCompactOwnsVisualArrivalWhenNativeAlertsAreUnavailable() {
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "denied", alertsEnabled: false))
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "not-determined", alertsEnabled: false))
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "authorized", alertsEnabled: false))
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "provisional", alertsEnabled: false))
    }

    func testNativeBannerOwnsVisualArrivalWhenEnabled() {
        expectFalse(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "authorized", alertsEnabled: true))
        expectFalse(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "provisional", alertsEnabled: true))
    }

    func testUnknownSettingsDeferVisualOwnership() {
        expectFalse(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "checking", alertsEnabled: false))
        expectFalse(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "unknown", alertsEnabled: false))
    }
}
