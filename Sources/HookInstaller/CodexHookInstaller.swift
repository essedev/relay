import Foundation

/// Installa/rimuove gli hook Relay in `~/.codex/hooks.json`. Codex non espone attualmente un
/// equivalente hook di `StopFailure`: gli errori API esatti non sono quindi deducibili dagli hook.
public struct CodexHookInstaller {
    public static let marker = "RELAY_MANAGED_CODEX_HOOK=1"

    public static var defaultSettingsPath: String {
        let override = ProcessInfo.processInfo.environment["RELAY_CODEX_HOOKS"]
        if let override, !override.isEmpty { return override }
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let base = codexHome.flatMap { $0.isEmpty ? nil : $0 }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".codex")
        return (base as NSString).appendingPathComponent("hooks.json")
    }

    typealias HookSpec = RelayHookSpec
    static let specs: [HookSpec] = [
        HookSpec(event: "SessionStart", state: "idle"),
        HookSpec(event: "UserPromptSubmit", state: "running"),
        HookSpec(event: "PreToolUse", state: "running", matcher: "*"),
        HookSpec(event: "PostToolUse", state: "running", matcher: "*"),
        HookSpec(event: "PermissionRequest", state: "needs_input"),
        HookSpec(event: "Stop", state: "idle"),
        HookSpec(event: "Interrupt", state: "idle"),
        HookSpec(event: "SessionEnd", state: "unknown"),
    ]

    static let maxBackups = JSONHookInstaller.maxBackups
    private static let engine = JSONHookInstaller(
        marker: marker,
        commandName: "codex-hook",
        specs: specs
    )

    public init() {}

    public func setup(cliPath: String, settingsPath: String = defaultSettingsPath) throws {
        try Self.engine.setup(cliPath: cliPath, settingsPath: settingsPath)
    }

    public func uninstall(settingsPath: String = defaultSettingsPath) throws {
        try Self.engine.uninstall(settingsPath: settingsPath)
    }

    public func status(settingsPath: String = defaultSettingsPath) -> Bool {
        Self.engine.status(settingsPath: settingsPath)
    }

    static func merge(into settings: [String: Any], cliPath: String) -> [String: Any] {
        engine.merge(into: settings, cliPath: cliPath)
    }

    static func remove(from settings: [String: Any]) -> [String: Any] {
        engine.remove(from: settings)
    }

    static func isInstalled(in settings: [String: Any]) -> Bool {
        engine.isInstalled(in: settings)
    }

    static func entryIsOurs(_ entry: [String: Any]) -> Bool {
        engine.entryIsOurs(entry)
    }
}
