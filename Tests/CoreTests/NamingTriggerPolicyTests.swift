import Core
import Foundation
import Testing

/// Base temporale fissa: la policy è pura, il tempo si avanza a mano (nessuna sleep).
private let t0 = Date(timeIntervalSince1970: 1_000_000)

// MARK: - Agente attivo

@Test func agentActiveNamesImmediately() {
    var policy = NamingTriggerPolicy()
    let decision = policy.observe(
        agent: "claude",
        command: "vim main.swift",
        cwd: "/x/proj",
        now: t0
    )
    #expect(decision == .name(WorkspaceNameSignals(
        directory: "/x/proj", command: "vim main.swift", agent: "claude"
    )))
}

@Test func agentTickDoesNotMutateCommandStreak() {
    var policy = NamingTriggerPolicy()
    // Un tick con agente attivo nomina subito senza toccare lo streak del comando...
    _ = policy.observe(agent: "claude", command: "make", cwd: nil, now: t0)
    // ...quindi il primo tick successivo senza agente riparte da streak 1 (aspetta, non nomina).
    #expect(policy.observe(agent: nil, command: "make", cwd: nil, now: t0) == .wait)
}

// MARK: - Streak del comando

@Test func commandNamesAfterTwoConsecutiveTicks() {
    var policy = NamingTriggerPolicy()
    #expect(policy.observe(agent: nil, command: "brew update", cwd: nil, now: t0) == .wait)
    #expect(policy.observe(agent: nil, command: "brew update", cwd: nil, now: t0)
        == .name(WorkspaceNameSignals(command: "brew update")))
}

@Test func changedCommandResetsStreak() {
    var policy = NamingTriggerPolicy()
    _ = policy.observe(agent: nil, command: "brew update", cwd: nil, now: t0)
    #expect(policy.observe(agent: nil, command: "npm install", cwd: nil, now: t0) == .wait)
}

@Test func nilCommandClearsStreak() {
    var policy = NamingTriggerPolicy()
    _ = policy.observe(agent: nil, command: "brew update", cwd: nil, now: t0)
    _ = policy.observe(agent: nil, command: nil, cwd: nil, now: t0)
    #expect(policy.observe(agent: nil, command: "brew update", cwd: nil, now: t0) == .wait)
}

// MARK: - Stabilizzazione della cwd

@Test func stableCwdNamesFromDirectory() {
    var policy = NamingTriggerPolicy()
    #expect(policy.observe(agent: nil, command: nil, cwd: "/x/proj", now: t0) == .wait)
    let later = t0.addingTimeInterval(10)
    #expect(policy.observe(agent: nil, command: nil, cwd: "/x/proj", now: later)
        == .name(WorkspaceNameSignals(directory: "/x/proj")))
}

@Test func changedCwdReArmsStabilityClock() {
    var policy = NamingTriggerPolicy()
    _ = policy.observe(agent: nil, command: nil, cwd: "/a", now: t0)
    let t1 = t0.addingTimeInterval(5)
    _ = policy.observe(agent: nil, command: nil, cwd: "/b", now: t1) // cambio: riparte il clock
    #expect(policy.observe(agent: nil, command: nil, cwd: "/b", now: t1.addingTimeInterval(5))
        == .wait) // solo 5s sulla nuova cwd
    #expect(policy.observe(agent: nil, command: nil, cwd: "/b", now: t1.addingTimeInterval(10))
        == .name(WorkspaceNameSignals(directory: "/b")))
}

// MARK: - Priorità e soglie

@Test func commandStreakFiresBeforeCwdStabilizes() {
    var policy = NamingTriggerPolicy()
    _ = policy.observe(agent: nil, command: "make", cwd: "/p", now: t0)
    // 20s dopo la cwd sarebbe stabile, ma lo streak del comando (2) vince.
    let decision = policy.observe(
        agent: nil,
        command: "make",
        cwd: "/p",
        now: t0.addingTimeInterval(20)
    )
    #expect(decision == .name(WorkspaceNameSignals(directory: "/p", command: "make")))
}

@Test func customThresholdsAreHonored() {
    var byCommand = NamingTriggerPolicy(thresholds: .init(commandStreak: 1, cwdStableSeconds: 0))
    #expect(byCommand.observe(agent: nil, command: "ls -la", cwd: nil, now: t0)
        == .name(WorkspaceNameSignals(command: "ls -la")))

    var byCwd = NamingTriggerPolicy(thresholds: .init(commandStreak: 5, cwdStableSeconds: 0))
    _ = byCwd.observe(agent: nil, command: nil, cwd: "/q", now: t0)
    #expect(byCwd.observe(agent: nil, command: nil, cwd: "/q", now: t0)
        == .name(WorkspaceNameSignals(directory: "/q")))
}
