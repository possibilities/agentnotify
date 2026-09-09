import Foundation

/// AgentStart owns the PATH router. Every interface uses its existing installer.
public final class NotificationShim {
    private let home: URL
    private let installer: URL
    private let lock = NSLock()

    public init(home: URL? = nil, installer: URL? = nil) {
        let operatorHome = FileManager.default.homeDirectoryForCurrentUser
        // Disposable services must never modify the operator's PATH commands.
        let isolated = ProcessInfo.processInfo.environment["AGENTNOTIFY_STATE_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("shim-home") }
        self.home = home ?? isolated ?? operatorHome
        self.installer = installer ?? operatorHome.appendingPathComponent("code/agentstart/scripts/install-notification-shim")
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
                "path": target.path, "installer": installer.path]
    }

    public func install() throws -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
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
}
