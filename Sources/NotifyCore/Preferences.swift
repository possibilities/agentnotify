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
    public var revision: Int = 1

    public init() {}
}
