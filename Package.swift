// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentNotify",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "agentnotify", targets: ["AgentNotify"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "NotifyCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "AgentNotify", dependencies: ["NotifyCore"]),
        .executableTarget(name: "NotifyCoreChecks", dependencies: ["NotifyCore"], path: "Tests/NotifyCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
