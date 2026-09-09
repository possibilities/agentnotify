import Foundation

public enum ArrivalStyle: String, Codable, CaseIterable, Identifiable {
    case queuePeek = "queue-peek"
    case compactToast = "compact-toast"
    case queueShelf = "queue-shelf"

    public var id: String { rawValue }
}

/// Preferences belong to this Mac's service, independently of notification state.
public struct AppPreferences: Codable, Equatable {
    public var arrivalStyle: ArrivalStyle = .queuePeek
    public var showBannerReminder: Bool = true
    public var revision: Int = 1

    public init() {}
    private enum CodingKeys: String, CodingKey { case arrivalStyle, showBannerReminder, revision }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        arrivalStyle = try values.decodeIfPresent(ArrivalStyle.self, forKey: .arrivalStyle) ?? .queuePeek
        showBannerReminder = try values.decodeIfPresent(Bool.self, forKey: .showBannerReminder) ?? true
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 1
    }
}
