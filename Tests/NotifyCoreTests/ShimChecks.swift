import Foundation
import NotifyCore

final class ShimChecks: StoreTestsBase {
    func offerDurabilityAndUnavailableInstaller() throws {
        let shim = NotificationShim(home: root, installer: root.appendingPathComponent("missing-installer"))
        let service = NotifyService(store: store, shim: shim)
        var notificationChanges = 0
        service.onChange = { notificationChanges += 1 }
        let initial = try service.call("shimStatus")
        expectEqual(initial["installed"] as? Bool, false)
        expectEqual(initial["available"] as? Bool, false)
        expectEqual(initial["promptHandled"] as? Bool, false)
        expectThrows(try service.call("installShim"))
        expectFalse(try store.shimPromptHandled())
        _ = try service.call("dismissShimSetup")
        _ = try service.call("dismissShimSetup")
        store = try Store(paths: NotifyPaths(root: root))
        expectTrue(try store.shimPromptHandled())
        expectEqual(try store.cursor(), 0)
        expectEqual(notificationChanges, 0)
    }

    func installerDelegationAndDetection() throws {
        let helper = root.appendingPathComponent("installer")
        // Simulate the owner contract without needing AgentStart on this host.
        let script = """
        #!/bin/bash
        set -euo pipefail
        [ "$AGENTSTART_INSTALL_BIN_DIR" = "$HOME/.local/bin" ]
        mkdir -p "$AGENTSTART_INSTALL_BIN_DIR"
        printf '#!/bin/bash\\n# agentstart-installer-owned: terminal-notifier.router.v1\\n' > "$AGENTSTART_INSTALL_BIN_DIR/terminal-notifier"
        chmod 755 "$AGENTSTART_INSTALL_BIN_DIR/terminal-notifier"
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let shim = NotificationShim(home: root, installer: helper)
        let service = NotifyService(store: store, shim: shim)
        let result = try service.call("installShim")
        expectEqual(result["installed"] as? Bool, true)
        expectEqual(result["promptHandled"] as? Bool, true)
        expectTrue(try store.shimPromptHandled())
        expectEqual(try store.cursor(), 0)
        let target = root.appendingPathComponent(".local/bin/terminal-notifier")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        expectEqual(shim.status()["installed"] as? Bool, false)
        try "foreign command".write(to: target, atomically: true, encoding: .utf8)
        expectEqual(shim.status()["installed"] as? Bool, false)
    }
}
