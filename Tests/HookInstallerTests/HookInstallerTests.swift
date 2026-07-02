import Foundation
@testable import HookInstaller
import Testing

private let cli = "/opt/relay/relay-cli"

private func entries(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
    let hooks = settings["hooks"] as? [String: Any] ?? [:]
    return hooks[event] as? [[String: Any]] ?? []
}

private func ourEntries(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
    entries(settings, event).filter(ClaudeHookInstaller.entryIsOurs)
}

// MARK: - Trasformazioni pure

@Test func mergeAddsAllManagedHooks() {
    let merged = ClaudeHookInstaller.merge(into: [:], cliPath: cli)
    for spec in ClaudeHookInstaller.specs {
        let ours = ourEntries(merged, spec.event)
        #expect(ours.count == 1)
        let command = ((ours.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String) ??
            ""
        #expect(command.contains(ClaudeHookInstaller.marker))
        #expect(command.contains(cli))
        #expect(command.contains(spec.state))
    }
}

@Test func toolEventsHaveMatcherOthersDoNot() {
    let merged = ClaudeHookInstaller.merge(into: [:], cliPath: cli)
    #expect(ourEntries(merged, "PreToolUse").first?["matcher"] as? String == "*")
    #expect(ourEntries(merged, "PostToolUse").first?["matcher"] as? String == "*")
    #expect(ourEntries(merged, "Stop").first?["matcher"] == nil)
    #expect(ourEntries(merged, "PermissionRequest").first?["matcher"] == nil)
}

@Test func mergePreservesExistingUserHooks() {
    // Simula un hook di un altro tool (es. Otty) già presente.
    let existing: [String: Any] = [
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "/otty/hook stop"]]]],
        ],
        "model": "claude-sonnet-5",
    ]
    let merged = ClaudeHookInstaller.merge(into: existing, cliPath: cli)

    // La chiave non-hooks resta intatta.
    #expect(merged["model"] as? String == "claude-sonnet-5")
    // L'hook di Otty resta, il nostro si aggiunge.
    let stop = entries(merged, "Stop")
    #expect(stop.count == 2)
    #expect(stop.contains { !ClaudeHookInstaller.entryIsOurs($0) })
    #expect(ourEntries(merged, "Stop").count == 1)
}

@Test func mergeIsIdempotent() {
    let once = ClaudeHookInstaller.merge(into: [:], cliPath: cli)
    let twice = ClaudeHookInstaller.merge(into: once, cliPath: cli)
    for spec in ClaudeHookInstaller.specs {
        #expect(ourEntries(twice, spec.event).count == 1)
    }
}

@Test func removeOnlyStripsOurHooksAndPreservesOthers() {
    let existing: [String: Any] = [
        "hooks": ["Stop": [["hooks": [["type": "command", "command": "/otty/hook stop"]]]]],
    ]
    let merged = ClaudeHookInstaller.merge(into: existing, cliPath: cli)
    let cleaned = ClaudeHookInstaller.remove(from: merged)

    #expect(!ClaudeHookInstaller.isInstalled(in: cleaned))
    // Otty preservato.
    let stop = entries(cleaned, "Stop")
    #expect(stop.count == 1)
    #expect(stop.contains { !ClaudeHookInstaller.entryIsOurs($0) })
    // Gli eventi dove c'eravamo solo noi vengono ripuliti.
    #expect(entries(cleaned, "PreToolUse").isEmpty)
}

@Test func removeDropsEmptyHooksKey() {
    let merged = ClaudeHookInstaller.merge(into: [:], cliPath: cli)
    let cleaned = ClaudeHookInstaller.remove(from: merged)
    #expect(cleaned["hooks"] == nil)
}

@Test func isInstalledReflectsState() {
    #expect(!ClaudeHookInstaller.isInstalled(in: [:]))
    let merged = ClaudeHookInstaller.merge(into: [:], cliPath: cli)
    #expect(ClaudeHookInstaller.isInstalled(in: merged))
}

// MARK: - Round-trip su file

@Test func setupAndUninstallRoundTripOnDisk() throws {
    let fileManager = FileManager.default
    let dir = "\(NSTemporaryDirectory())relay-hooks-\(UInt64.random(in: 0 ..< 1_000_000_000))"
    try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(atPath: dir) }
    let settingsPath = "\(dir)/settings.json"

    // Settings preesistenti con un hook utente.
    let seed: [String: Any] = [
        "hooks": ["Stop": [["hooks": [["type": "command", "command": "/otty/hook stop"]]]]],
    ]
    let seedData = try JSONSerialization.data(withJSONObject: seed)
    try seedData.write(to: URL(fileURLWithPath: settingsPath))

    let installer = ClaudeHookInstaller()
    try installer.setup(cliPath: cli, settingsPath: settingsPath)
    #expect(installer.status(settingsPath: settingsPath))

    // Backup creato.
    let backups = try fileManager.contentsOfDirectory(atPath: dir)
        .filter { $0.contains("relay-backup") }
    #expect(!backups.isEmpty)

    // File valido e con hook nostro + Otty.
    let afterSetup = try JSONSerialization.jsonObject(
        with: Data(contentsOf: URL(fileURLWithPath: settingsPath))
    ) as? [String: Any] ?? [:]
    #expect(entries(afterSetup, "Stop").count == 2)

    try installer.uninstall(settingsPath: settingsPath)
    #expect(!installer.status(settingsPath: settingsPath))
    let afterUninstall = try JSONSerialization.jsonObject(
        with: Data(contentsOf: URL(fileURLWithPath: settingsPath))
    ) as? [String: Any] ?? [:]
    #expect(entries(afterUninstall, "Stop").count == 1)
}
