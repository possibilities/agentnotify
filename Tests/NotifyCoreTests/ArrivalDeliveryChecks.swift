import NotifyCore

final class ArrivalDeliveryChecks: CheckCase {
    func testCompactIsPrimaryWhenNativeAlertsAreUnavailable() {
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "denied", alertsEnabled: false))
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "not-determined", alertsEnabled: false))
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "authorized", alertsEnabled: false))
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "provisional", alertsEnabled: false))
    }

    func testCompactRemainsPrimaryWhenNativeBannersAreEnabled() {
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "authorized", alertsEnabled: true))
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "provisional", alertsEnabled: true))
    }

    func testCompactDoesNotWaitForNativeSettings() {
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "checking", alertsEnabled: false))
        expectTrue(ArrivalDeliveryPolicy.shouldShowCompact(authorization: "unknown", alertsEnabled: false))
    }
}
