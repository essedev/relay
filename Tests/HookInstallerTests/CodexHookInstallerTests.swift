import Foundation
@testable import HookInstaller
import Testing

private let codexCLI = "/opt/relay/relay-cli"

private func codexEntries(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
    let hooks = settings["hooks"] as? [String: Any] ?? [:]
    return hooks[event] as? [[String: Any]] ?? []
}

private func codexOurEntries(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
    codexEntries(settings, event).filter(CodexHookInstaller.entryIsOurs)
}

@Test func codexMergeAddsSupportedHooksWithoutInventingError() {
    let merged = CodexHookInstaller.merge(into: [:], cliPath: codexCLI)
    for spec in CodexHookInstaller.specs {
        #expect(codexOurEntries(merged, spec.event).count == 1)
    }
    #expect(codexEntries(merged, "StopFailure").isEmpty)
    let stop = (codexOurEntries(merged, "Stop").first?["hooks"] as? [[String: Any]])?
        .first?["command"] as? String
    #expect(stop?.hasSuffix("codex-hook idle") == true)
}

@Test func codexMergeIsIdempotentAndPreservesUserHooks() {
    let existing: [String: Any] = [
        "hooks": ["Stop": [["hooks": [["type": "command", "command": "/user/hook"]]]]],
        "model": "gpt-5",
    ]
    let once = CodexHookInstaller.merge(into: existing, cliPath: codexCLI)
    let twice = CodexHookInstaller.merge(into: once, cliPath: codexCLI)
    #expect(twice["model"] as? String == "gpt-5")
    #expect(codexEntries(twice, "Stop").count == 2)
    for spec in CodexHookInstaller.specs {
        #expect(codexOurEntries(twice, spec.event).count == 1)
    }
}

@Test func codexRemoveOnlyManagedHooks() {
    let existing: [String: Any] = [
        "hooks": ["Stop": [["hooks": [["type": "command", "command": "/user/hook"]]]]],
    ]
    let merged = CodexHookInstaller.merge(into: existing, cliPath: codexCLI)
    let cleaned = CodexHookInstaller.remove(from: merged)
    #expect(!CodexHookInstaller.isInstalled(in: cleaned))
    #expect(codexEntries(cleaned, "Stop").count == 1)
    #expect(codexEntries(cleaned, "Interrupt").isEmpty)
}

@Test func codexSetupRoundTripsOnDisk() throws {
    let manager = FileManager.default
    let dir = "\(NSTemporaryDirectory())relay-codex-hooks-\(UInt64.random(in: 0 ..< 1_000_000_000))"
    try manager.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? manager.removeItem(atPath: dir) }
    let path = "\(dir)/hooks.json"
    try Data("{}".utf8).write(to: URL(fileURLWithPath: path))

    let installer = CodexHookInstaller()
    try installer.setup(cliPath: codexCLI, settingsPath: path)
    #expect(installer.status(settingsPath: path))
    try installer.uninstall(settingsPath: path)
    #expect(!installer.status(settingsPath: path))
}
