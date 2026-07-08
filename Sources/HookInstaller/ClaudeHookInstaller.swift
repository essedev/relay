import Core
import Foundation

public enum HookInstallerError: Error, Equatable {
    /// Il settings.json esistente non è JSON valido: non lo tocchiamo per non corromperlo.
    case invalidSettings
}

/// Installa/rimuove gli hook Claude in `~/.claude/settings.json` in modo idempotente, con backup e
/// validazione JSON, senza rompere Otty o altri hook utente.
///
/// Convivenza: gli hook nostri sono marcati (`marker` nel comando) e vengono solo aggiunti agli
/// array esistenti; setup ripetuto non duplica; uninstall rimuove solo i nostri.
///
/// La manipolazione JSON è divisa in trasformazioni pure (`merge`/`remove`/`isInstalled`),
/// testabili
/// senza I/O, e wrapper di file (`setup`/`uninstall`/`status`).
public struct ClaudeHookInstaller {
    /// Prefisso env inline che marca i comandi gestiti da Relay (per idempotenza e uninstall).
    public static let marker = "RELAY_MANAGED_HOOK=1"

    /// Path di `settings.json`. Override via `RELAY_CLAUDE_SETTINGS` (test/automazioni: così i
    /// comandi `hooks` non toccano mai il vero `~/.claude`).
    public static var defaultSettingsPath: String {
        let override = ProcessInfo.processInfo.environment["RELAY_CLAUDE_SETTINGS"]
        if let override, !override.isEmpty { return override }
        return (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude")
            .appending("/settings.json")
    }

    /// Mapping evento Claude -> stato prodotto. Unico posto da aggiornare se cambiano i nomi hook.
    /// `isToolEvent`: gli eventi tool (`PreToolUse`/`PostToolUse`) usano un `matcher`; gli altri
    /// no.
    struct HookSpec {
        let event: String
        let state: String
        let isToolEvent: Bool
    }

    static let specs: [HookSpec] = [
        HookSpec(event: "SessionStart", state: "idle", isToolEvent: false),
        HookSpec(event: "UserPromptSubmit", state: "running", isToolEvent: false),
        HookSpec(event: "PreToolUse", state: "running", isToolEvent: true),
        HookSpec(event: "PostToolUse", state: "running", isToolEvent: true),
        HookSpec(event: "PermissionRequest", state: "needs_input", isToolEvent: false),
        HookSpec(event: "Stop", state: "idle", isToolEvent: false),
        HookSpec(event: "SessionEnd", state: "unknown", isToolEvent: false),
    ]

    public init() {}

    // MARK: - API file

    public func setup(cliPath: String, settingsPath: String = defaultSettingsPath) throws {
        let fileManager = FileManager.default
        let directory = (settingsPath as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]
        if fileManager.fileExists(atPath: settingsPath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookInstallerError.invalidSettings
            }
            settings = parsed
            try backup(settingsPath)
        }

        let merged = Self.merge(into: settings, cliPath: cliPath)
        try write(merged, to: settingsPath)
    }

    public func uninstall(settingsPath: String = defaultSettingsPath) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: settingsPath) else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstallerError.invalidSettings
        }
        try backup(settingsPath)
        let cleaned = Self.remove(from: parsed)
        try write(cleaned, to: settingsPath)
    }

    public func status(settingsPath: String = defaultSettingsPath) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return Self.isInstalled(in: parsed)
    }

    // MARK: - Trasformazioni pure (testabili senza I/O)

    /// Comando hook per uno spec: `RELAY_MANAGED_HOOK=1 <cli> claude-hook <state>`. Il path
    /// dell'eseguibile è shell-escaped (`Core.ShellEscape`, backslash sui caratteri non sicuri) e
    /// non solo racchiuso tra apici: spazi o metacaratteri (`$`, backtick) nel path del bundle non
    /// possono rompere il comando o iniettare nel `settings.json` dell'utente.
    static func command(for spec: HookSpec, cliPath: String) -> String {
        "\(marker) \(ShellEscape.path(cliPath)) claude-hook \(spec.state)"
    }

    /// Aggiunge/rimpiazza i nostri hook nel dizionario settings, preservando tutto il resto.
    static func merge(into settings: [String: Any], cliPath: String) -> [String: Any] {
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for spec in specs {
            var entries = (hooks[spec.event] as? [[String: Any]] ?? []).filter { !entryIsOurs($0) }
            var entry: [String: Any] = [
                "hooks": [["type": "command", "command": command(for: spec, cliPath: cliPath)]],
            ]
            if spec.isToolEvent {
                entry["matcher"] = "*"
            }
            entries.append(entry)
            hooks[spec.event] = entries
        }

        settings["hooks"] = hooks
        return settings
    }

    /// Rimuove solo i nostri hook; ripulisce array/chiavi rimasti vuoti.
    static func remove(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }

        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.filter { !entryIsOurs($0) }
            if kept.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = kept
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        return settings
    }

    static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        for value in hooks.values {
            guard let entries = value as? [[String: Any]] else { continue }
            if entries.contains(where: entryIsOurs) { return true }
        }
        return false
    }

    /// Una entry è nostra se un suo comando contiene il marker.
    static func entryIsOurs(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    // MARK: - I/O privato

    /// Quanti backup di `settings.json` conservare: abbastanza per recuperare da un paio di
    /// operazioni sbagliate, senza accumularne uno per ogni setup/uninstall all'infinito.
    static let maxBackups = 5

    private func backup(_ path: String) throws {
        let stamp = String(Int(Date().timeIntervalSince1970))
        let backupPath = "\(path).relay-backup-\(stamp)"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: backupPath) {
            try fileManager.removeItem(atPath: backupPath)
        }
        try fileManager.copyItem(atPath: path, toPath: backupPath)
        pruneBackups(of: path)
    }

    /// Elimina i backup più vecchi oltre `maxBackups`. I nomi finiscono con l'epoch a lunghezza
    /// fissa, quindi l'ordine lessicografico coincide con quello cronologico.
    private func pruneBackups(of path: String) {
        let fileManager = FileManager.default
        let directory = (path as NSString).deletingLastPathComponent
        let prefix = (path as NSString).lastPathComponent + ".relay-backup-"
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
        let backups = entries.filter { $0.hasPrefix(prefix) }.sorted()
        for name in backups.dropLast(Self.maxBackups) {
            try? fileManager.removeItem(
                atPath: (directory as NSString).appendingPathComponent(name)
            )
        }
    }

    private func write(_ settings: [String: Any], to path: String) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
