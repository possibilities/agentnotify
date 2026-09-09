import Foundation
import NotifyCore

final class TestInterfaceController: NotifyInterfaceController {
    var calls: [(String, [String: Any])] = []
    func performInterface(_ method: String, params: [String: Any]) throws -> [String: Any] {
        calls.append((method, params))
        return ["method": method, "uiRevision": calls.count]
    }
}

final class InterfaceChecks: StoreTestsBase {
    func routingAndHeadlessFailure() throws {
        let service = NotifyService(store: store)
        expectThrows(try service.call("uiState"))
        let interface = TestInterfaceController()
        service.interfaceController = interface
        expectEqual(try service.call("uiState")["method"] as? String, "uiState")
        let shown = try service.call("show", ["id": try notificationID()])
        expectEqual((shown["state"] as? [String: Any])?["method"] as? String, "uiShow")
        expectEqual(interface.calls.last?.1["surface"] as? String, "inbox")
        let preferences = try service.call("showPreferences")
        expectEqual((preferences["state"] as? [String: Any])?["method"] as? String, "uiShow")
        expectEqual(interface.calls.last?.1["surface"] as? String, "preferences")
        expectEqual(try service.call("uiNavigate", ["direction": "next"])["method"] as? String, "uiNavigate")
    }

    private func notificationID() throws -> String {
        try store.perform("send", params: ["message": "Interface target"])["id"] as! String
    }
}
