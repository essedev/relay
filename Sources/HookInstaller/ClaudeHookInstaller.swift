import Foundation

public enum HookInstallerError: Error, Equatable {
    /// Il file hook esistente non è JSON valido: non lo tocchiamo per non corromperlo.
    case invalidSettings
}

/// Installa/rimuove gli hook Relay in `~/.claude/settings.json`, preservando configurazione e
/// hook preesistenti. Le API pure restano esposte al test target; l'I/O è condiviso con Codex.
public struct ClaudeHookInstaller {
    public static let marker = "RELAY_MANAGED_HOOK=1"

    public static var defaultSettingsPath: String {
        let override = ProcessInfo.processInfo.environment["RELAY_CLAUDE_SETTINGS"]
        if let override, !override.isEmpty { return override }
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude")
            .appending("/settings.json")
    }

    typealias HookSpec = RelayHookSpec
    static let specs: [HookSpec] = [
        HookSpec(event: "SessionStart", state: "idle"),
        HookSpec(event: "UserPromptSubmit", state: "running"),
        HookSpec(event: "PreToolUse", state: "running", matcher: "*"),
        HookSpec(event: "PostToolUse", state: "running", matcher: "*"),
        HookSpec(event: "PermissionRequest", state: "needs_input"),
        HookSpec(event: "Stop", state: "idle"),
        HookSpec(event: "StopFailure", state: "error"),
        HookSpec(event: "SessionEnd", state: "unknown"),
    ]

    static let maxBackups = JSONHookInstaller.maxBackups
    private static let engine = JSONHookInstaller(
        marker: marker,
        commandName: "claude-hook",
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

    /// Come `status`, ma distingue "mai installati" da "installati e rimasti indietro" e dice
    /// quali eventi mancano.
    public func state(settingsPath: String = defaultSettingsPath) -> RelayHookState {
        Self.engine.state(settingsPath: settingsPath)
    }

    static func command(for spec: HookSpec, cliPath: String) -> String {
        engine.command(for: spec, cliPath: cliPath)
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

    static func state(in settings: [String: Any]) -> RelayHookState {
        engine.state(in: settings)
    }

    static func entryIsOurs(_ entry: [String: Any]) -> Bool {
        engine.entryIsOurs(entry)
    }
}
