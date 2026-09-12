import Foundation

/// AgentStart owns the PATH router. Every interface uses its existing installer.
public final class NotificationShim {
    private let home: URL
    private let installer: URL
    private let originalPrefixes: [URL]
    private let lock = NSLock()

    public static let defaultOriginalPrefixes = [
        URL(fileURLWithPath: "/opt/homebrew"),
        URL(fileURLWithPath: "/usr/local"),
    ]

    public init(home: URL? = nil, installer: URL? = nil, originalPrefixes: [URL]? = nil) {
        let operatorHome = FileManager.default.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        // Disposable services must never modify the operator's PATH commands.
        let isolated = environment["AGENTNOTIFY_STATE_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("shim-home") }
        self.home = home ?? isolated ?? operatorHome
        self.installer = installer ?? operatorHome.appendingPathComponent("code/agentstart/scripts/install-notification-shim")
        // Isolated stores (tests, AGENTNOTIFY_STATE_DIR) do not inspect the
        // operator Homebrew prefixes unless a caller injects them.
        self.originalPrefixes = originalPrefixes ?? (environment["AGENTNOTIFY_STATE_DIR"] == nil ? Self.defaultOriginalPrefixes : [])
    }

    public static func originalNotifierError(path: String) -> NotifyError {
        NotifyError(
            "original_notifier_present",
            "Homebrew terminal-notifier is still installed at \(path). Uninstall it with brew uninstall terminal-notifier, then install the shim. Otherwise launchd and scripts keep posting macOS banners."
        )
    }

    public func originalNotifierPath() -> String? {
        let target = home.appendingPathComponent(".local/bin/terminal-notifier")
        let agent = home.appendingPathComponent(".local/bin/agentnotify")
        for prefix in originalPrefixes {
            let candidate = prefix.appendingPathComponent("bin/terminal-notifier")
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            if sameFile(candidate, target) || sameFile(candidate, agent) { continue }
            return candidate.path
        }
        return nil
    }

    public func status() -> [String: Any] {
        let target = home.appendingPathComponent(".local/bin/terminal-notifier")
        let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
        let regular = attributes?[.type] as? FileAttributeType == .typeRegular
        let small = (attributes?[.size] as? NSNumber)?.intValue ?? Int.max < 32_768
        let contents = regular && small ? ((try? String(contentsOf: target, encoding: .utf8)) ?? "") : ""
        let owned = contents.split(separator: "\n").contains("# agentstart-installer-owned: terminal-notifier.router.v1")
        return ["installed": owned && FileManager.default.isExecutableFile(atPath: target.path),
                "available": FileManager.default.isExecutableFile(atPath: installer.path),
                "path": target.path, "installer": installer.path,
                "originalNotifier": originalNotifierPath() as Any? ?? NSNull()]
    }

    public func install() throws -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        if let path = originalNotifierPath() { throw Self.originalNotifierError(path: path) }
        guard FileManager.default.isExecutableFile(atPath: installer.path) else {
            throw NotifyError("installer_unavailable", "Install AgentStart to enable terminal-notifier integration. Its shim installer is missing at \(installer.path).")
        }
        let process = Process()
        process.executableURL = installer
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["AGENTSTART_INSTALL_BIN_DIR"] = home.appendingPathComponent(".local/bin").path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output; process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NotifyError("installation_failed", String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let result = status()
        guard result["installed"] as? Bool == true else { throw NotifyError("installation_failed", "The shim was not installed. Check AgentStart and try again.") }
        return result
    }

    private func sameFile(_ left: URL, _ right: URL) -> Bool {
        guard let leftID = try? left.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let rightID = try? right.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        else { return false }
        return leftID.isEqual(rightID)
    }
}
