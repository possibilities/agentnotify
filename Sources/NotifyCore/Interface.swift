import Foundation

/// Semantic control of the local native interface. Implementations own only
/// transient presentation state; durable notification changes still go through
/// Store operations such as status and respond.
public protocol NotifyInterfaceController: AnyObject {
    func performInterface(_ method: String, params: [String: Any]) throws -> [String: Any]
}
