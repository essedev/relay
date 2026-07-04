// swift-tools-version: 6.0
import PackageDescription

/// Monolite modulare: un solo repo, molti moduli. Le dipendenze tra moduli sono imposte dal
/// compilatore (vedi docs/ARCHITECTURE.md). Regola: solo verso il basso, mai risalire.
let package = Package(
    name: "relay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "relay", targets: ["RelayApp"]),
        .executable(name: "relay-cli", targets: ["CLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", branch: "main"),
    ],
    targets: [
        // Livello 0: primitivi condivisi, nessuna dipendenza.
        .target(name: "Core"),

        // Livello 1: protocollo agente puro (tipi, niente I/O).
        .target(name: "AgentProtocol", dependencies: ["Core"]),

        // Livello 2: runtime e model.
        .target(name: "AgentRuntime", dependencies: ["Core", "AgentProtocol"]),
        .target(name: "WorkspaceModel", dependencies: ["Core", "AgentProtocol"]),
        .target(
            name: "TerminalEngine",
            dependencies: ["Core", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .target(name: "HookInstaller", dependencies: ["Core", "AgentProtocol"]),
        .target(name: "LayoutStore", dependencies: ["Core", "WorkspaceModel"]),

        // Livello 3: UI (AppKit sul path caldo, SwiftUI nei pannelli isolati).
        .target(name: "TerminalHostUI", dependencies: ["Core", "TerminalEngine", "WorkspaceModel"]),
        .target(
            name: "Panels",
            dependencies: ["Core", "AgentProtocol", "WorkspaceModel", "AgentRuntime"]
        ),

        // Eseguibili.
        .executableTarget(
            name: "RelayApp",
            dependencies: [
                "Core", "AgentProtocol", "AgentRuntime", "WorkspaceModel",
                "TerminalEngine", "TerminalHostUI", "Panels", "HookInstaller", "LayoutStore",
            ],
            path: "Sources/relay"
        ),
        .executableTarget(
            name: "CLI",
            dependencies: ["Core", "AgentProtocol", "AgentRuntime", "HookInstaller"],
            path: "Sources/relay-cli"
        ),

        // Test (logica pura, veloce, senza AppKit).
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "AgentProtocolTests", dependencies: ["AgentProtocol"]),
        .testTarget(name: "WorkspaceModelTests", dependencies: ["WorkspaceModel", "AgentProtocol"]),
        .testTarget(name: "AgentRuntimeTests", dependencies: ["AgentRuntime", "AgentProtocol"]),
        .testTarget(name: "HookInstallerTests", dependencies: ["HookInstaller", "AgentProtocol"]),
        .testTarget(name: "TerminalHostUITests", dependencies: ["TerminalHostUI"]),
        .testTarget(
            name: "LayoutStoreTests",
            dependencies: ["LayoutStore", "WorkspaceModel", "AgentProtocol"]
        ),
        .testTarget(
            name: "PanelsTests",
            dependencies: ["Panels", "WorkspaceModel", "AgentProtocol"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
