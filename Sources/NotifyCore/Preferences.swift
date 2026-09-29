import Foundation

public enum ArrivalStyle: String, Codable, CaseIterable, Identifiable {
    case queuePeek = "queue-peek"
    case compactToast = "compact-toast"
    case queueShelf = "queue-shelf"

    public var id: String { rawValue }
}

/// A layout-stable global shortcut captured by the native app. The virtual
/// key code drives registration; `key` preserves the human-readable label
/// from the keyboard layout used when it was recorded.
public struct GlobalShortcut: Codable, Equatable {
    public var keyCode: Int
    public var key: String
    public var modifiers: [String]

    public init(keyCode: Int, key: String, modifiers: [String]) {
        self.keyCode = keyCode
        self.key = key
        let supplied = Set(modifiers)
        self.modifiers = ["control", "option", "shift", "command"].filter(supplied.contains)
    }

    public var isValid: Bool {
        (0...127).contains(keyCode) && !key.isEmpty && key.utf8.count <= 16
            && (2...4).contains(modifiers.count)
            && Set(modifiers).count == modifiers.count
            && Set(modifiers).isSubset(of: ["control", "option", "shift", "command"])
    }

    private enum CodingKeys: String, CodingKey { case keyCode, key, modifiers }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(keyCode: try values.decode(Int.self, forKey: .keyCode),
            key: try values.decode(String.self, forKey: .key),
            modifiers: try values.decode([String].self, forKey: .modifiers))
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .modifiers, in: values,
                debugDescription: "Invalid global shortcut.")
        }
    }
}

/// Preferences belong to this Mac's service, independently of notification state.
public struct AppPreferences: Codable, Equatable {
    public static let defaultCompleteAllShortcut = GlobalShortcut(
        keyCode: 2, key: "D", modifiers: ["option", "shift", "command"]
    )
    public static let defaultShowInboxShortcut = GlobalShortcut(
        keyCode: 34, key: "I", modifiers: ["option", "shift", "command"]
    )
    public var arrivalStyle: ArrivalStyle = .queuePeek
    public var showBannerReminder: Bool = false
    public var completeAllShortcut: GlobalShortcut? = Self.defaultCompleteAllShortcut
    public var showInboxShortcut: GlobalShortcut? = Self.defaultShowInboxShortcut
    public var revision: Int = 1

    public init() {}
    private enum CodingKeys: String, CodingKey { case arrivalStyle, showBannerReminder, completeAllShortcut, showInboxShortcut, revision }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        arrivalStyle = try values.decodeIfPresent(ArrivalStyle.self, forKey: .arrivalStyle) ?? .queuePeek
        showBannerReminder = try values.decodeIfPresent(Bool.self, forKey: .showBannerReminder) ?? false
        if values.contains(.completeAllShortcut) {
            do { completeAllShortcut = try values.decodeIfPresent(GlobalShortcut.self, forKey: .completeAllShortcut) }
            catch { completeAllShortcut = nil }
        } else { completeAllShortcut = Self.defaultCompleteAllShortcut }
        if values.contains(.showInboxShortcut) {
            do { showInboxShortcut = try values.decodeIfPresent(GlobalShortcut.self, forKey: .showInboxShortcut) }
            catch { showInboxShortcut = nil }
        } else {
            let proposed = Self.defaultShowInboxShortcut
            showInboxShortcut = completeAllShortcut?.keyCode == proposed.keyCode
                && completeAllShortcut?.modifiers == proposed.modifiers ? nil : proposed
        }
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(arrivalStyle, forKey: .arrivalStyle)
        try values.encode(showBannerReminder, forKey: .showBannerReminder)
        if let completeAllShortcut { try values.encode(completeAllShortcut, forKey: .completeAllShortcut) }
        else { try values.encodeNil(forKey: .completeAllShortcut) }
        if let showInboxShortcut { try values.encode(showInboxShortcut, forKey: .showInboxShortcut) }
        else { try values.encodeNil(forKey: .showInboxShortcut) }
        try values.encode(revision, forKey: .revision)
    }
}
