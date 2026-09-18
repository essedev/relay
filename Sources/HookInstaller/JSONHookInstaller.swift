import Core
import Foundation

/// Descrizione dichiarativa di un hook gestito da Relay.
struct RelayHookSpec {
    let event: String
    let state: String
    let matcher: String?

    init(event: String, state: String, matcher: String? = nil) {
        self.event = event
        self.state = state
        self.matcher = matcher
    }
}

/// Motore condiviso per i file hook JSON di Claude Code e Codex. Le trasformazioni preservano
/// chiavi e hook dell'utente; il marker identifica esclusivamente le entry possedute da Relay.
struct JSONHookInstaller {
    static let maxBackups = 5

    let marker: String
    let commandName: String
    let specs: [RelayHookSpec]

    func setup(cliPath: String, settingsPath: String) throws {
        let fileManager = FileManager.default
        let directory = (settingsPath as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

        var settings: [String: Any] = [:]
        if fileManager.fileExists(atPath: settingsPath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw HookInstallerError.invalidSettings }
            settings = parsed
            try backup(settingsPath)
        }
        try write(merge(into: settings, cliPath: cliPath), to: settingsPath)
    }

    func uninstall(settingsPath: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: settingsPath) else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw HookInstallerError.invalidSettings }
        try backup(settingsPath)
        try write(remove(from: parsed), to: settingsPath)
    }

    func status(settingsPath: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return isInstalled(in: parsed)
    }

    func command(for spec: RelayHookSpec, cliPath: String) -> String {
        "\(marker) \(ShellEscape.path(cliPath)) \(commandName) \(spec.state)"
    }

    func merge(into settings: [String: Any], cliPath: String) -> [String: Any] {
        var settings = settings
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for spec in specs {
            var entries = (hooks[spec.event] as? [[String: Any]] ?? [])
                .filter { !entryIsOurs($0) }
            var entry: [String: Any] = [
                "hooks": [["type": "command", "command": command(for: spec, cliPath: cliPath)]],
            ]
            if let matcher = spec.matcher { entry["matcher"] = matcher }
            entries.append(entry)
            hooks[spec.event] = entries
        }
        settings["hooks"] = hooks
        return settings
    }

    func remove(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.filter { !entryIsOurs($0) }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        return settings
    }

    func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return specs.allSatisfy { spec in
            guard let entries = hooks[spec.event] as? [[String: Any]] else { return false }
            return entries.contains(where: entryIsOurs)
        }
    }

    func entryIsOurs(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    private func backup(_ path: String) throws {
        let backupPath = "\(path).relay-backup-\(Int(Date().timeIntervalSince1970))"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: backupPath) {
            try fileManager.removeItem(atPath: backupPath)
        }
        try fileManager.copyItem(atPath: path, toPath: backupPath)
        pruneBackups(of: path)
    }

    private func pruneBackups(of path: String) {
        let fileManager = FileManager.default
        let directory = (path as NSString).deletingLastPathComponent
        let prefix = (path as NSString).lastPathComponent + ".relay-backup-"
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
        for name in entries.filter({ $0.hasPrefix(prefix) }).sorted().dropLast(Self.maxBackups) {
            let backupPath = (directory as NSString).appendingPathComponent(name)
            try? fileManager.removeItem(atPath: backupPath)
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
