import Darwin
import Foundation
@testable import TerminalEngine
import Testing

// Il reaper è l'unico codice di Relay che segnala processi che **non** ha visto nascere in questa
// run: la parte pura decide cosa è nostro, quella su pty vere prova che un agente sordo a SIGHUP e
// SIGTERM muore davvero e che un processo estraneo con un pid "riciclato" resta in piedi.

// MARK: - Appartenenza (pura)

private let shell = ProcessIdentity(pid: 500, startedAt: 10000)

private func entry(
    _ pid: pid_t,
    startedAt: UInt64 = 20000,
    sid: pid_t = 500,
    parent: pid_t = 1,
    uid: uid_t = 501
) -> PtySessionReaper.ProcessEntry {
    PtySessionReaper.ProcessEntry(
        identity: ProcessIdentity(pid: pid, startedAt: startedAt),
        sessionID: sid,
        parentPid: parent,
        uid: uid
    )
}

private func members(
    _ processes: [PtySessionReaper.ProcessEntry],
    recorded: [ProcessIdentity] = [],
    trusted: Set<ProcessIdentity> = []
) -> [pid_t] {
    let record = PtySessionRecord(
        shellPid: 500, shellStartedAt: 10000, tabId: "tab", members: recorded
    )
    return PtySessionReaper.members(
        of: record, in: processes, trusted: trusted, ownUID: 501, selfPID: 999
    ).map(\.pid)
}

@Test func aLiveLeaderMakesTheWholeSessionOurs() {
    // La shell registrata è ancora lì: ogni membro è nostro, anche uno mai fotografato.
    let processes = [entry(500, startedAt: 10000), entry(600, parent: 500), entry(601)]
    #expect(members(processes) == [500, 600, 601])
}

@Test func aDeadLeaderNeedsARecordedIdentityAsProof() {
    // Una zsh esce sull'hangup e l'agente che lo ignora resta, figlio di launchd: senza leader
    // conta solo l'identità esatta fotografata mentre Relay era vivo. 601 ha lo stesso pid di un
    // membro fotografato ma un altro avvio: è un pid riciclato, non lo stesso processo.
    let processes = [entry(600), entry(601), entry(602)]
    let recorded = [
        ProcessIdentity(pid: 600, startedAt: 20000),
        ProcessIdentity(pid: 601, startedAt: 15000),
    ]
    #expect(members(processes, recorded: recorded) == [600])
    #expect(members(processes).isEmpty)
}

@Test func childrenOfAProvenMemberAreOursToo() {
    // L'agente lancia un hook dopo l'uscita di Relay, e quell'hook lancia un suo figlio: nessuno
    // dei due è nella fotografia, ma discendono da chi c'è.
    let agent = ProcessIdentity(pid: 600, startedAt: 20000)
    let processes = [
        entry(700, startedAt: 40000, parent: 650), // nipote: arriva dopo il figlio
        entry(600),
        entry(650, startedAt: 30000, parent: 600),
        entry(800, startedAt: 30000, parent: 1), // stessa sessione, nessuna prova
    ]
    #expect(members(processes, recorded: [agent]) == [700, 600, 650])
}

@Test func aLeaderWithTheSamePidButAnotherStartIsNotOurs() {
    // Il pid della shell è stato riciclato da un'altra sessione: nessuna prova, nessun segnale.
    let processes = [entry(500, startedAt: 30000), entry(600, startedAt: 30001, parent: 500)]
    #expect(members(processes).isEmpty)
}

@Test func provenMembersStayProvenWhenTheLeaderDies() {
    // Fra SIGHUP e SIGKILL la shell può morire: chi era già provato nostro resta tale.
    let agent = ProcessIdentity(pid: 600, startedAt: 20000)
    #expect(members([entry(600)], trusted: [agent]) == [600])
}

@Test func outsidersAreNeverMembers() {
    let processes = [
        entry(500, startedAt: 10000), // leader: la sessione è nostra
        entry(700, sid: 701), // un'altra sessione
        entry(702, uid: 0), // un altro utente
        entry(999), // Relay stesso
        entry(1), // launchd
        entry(703, startedAt: 9999), // più vecchio della shell che ha aperto la sessione
    ]
    #expect(members(processes) == [500])
}

@Test func anUnstartedShellHasNoSession() {
    let unstarted = PtySessionRecord(
        shellPid: 0, shellStartedAt: 0, tabId: nil,
        members: [ProcessIdentity(pid: 600, startedAt: 20000)]
    )
    let found = PtySessionReaper.members(
        of: unstarted, in: [entry(600, sid: 0)], trusted: [], ownUID: 501, selfPID: 999
    )
    #expect(found.isEmpty)
}

// MARK: - Su pty vere

private func temporaryLedgerDirectory() -> String {
    (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("relay-reaper-\(UInt64.random(in: 0 ..< 1_000_000_000))")
}

/// Un Relay morto: il pid di questo processo con un istante di avvio che non è il suo.
private let deadOwner = ProcessIdentity(pid: getpid(), startedAt: 1)

/// Scrive il file del registro di una run precedente, come l'avrebbe lasciato un Relay uscito.
private func writeLedger(
    in directory: String,
    runID: String,
    owner: ProcessIdentity,
    sessions: [PtySessionRecord]
) throws -> String {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let path = "\(directory)/\(runID).json"
    let file = PtySessionLedgerFile(runId: runID, owner: owner, sessions: sessions)
    try JSONEncoder().encode(file).write(to: URL(fileURLWithPath: path))
    return path
}

private func record(of session: PtySession) throws -> PtySessionRecord {
    let identity = try #require(ProcessIdentity.of(session.shellPid))
    return PtySessionRecord(
        shellPid: session.shellPid, shellStartedAt: identity.startedAt, tabId: "tab"
    )
}

/// I processi vivi rimasti nella sessione POSIX della shell.
private func survivors(ofSession shellPid: pid_t) -> [pid_t] {
    PtySessionReaper.processes(inSessions: [shellPid]).map(\.identity.pid)
}

@Test func reaperClosesASessionDeafToHangupAndTerm() throws {
    // Shell e agente sopravvivono al SIGHUP, l'agente anche al SIGTERM: è il caso in cui la shell
    // resta in piedi e fa da prova per tutta la sessione. Solo il SIGKILL li chiude.
    let session = try #require(PtySession.spawn(running: "trap '' HUP TERM; sleep 600"))
    defer { session.forceCleanup() }
    let agent = try #require(session.foregroundLeader())
    let directory = temporaryLedgerDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = try writeLedger(
        in: directory, runID: "dead-run", owner: deadOwner, sessions: [record(of: session)]
    )

    let outcome = PtySessionReaper.reapOrphans(
        in: directory, currentRunID: "this-run", grace: 0.3, killGrace: 1
    )

    #expect(outcome.sessions == 1)
    #expect(outcome.hungUp == 2) // shell e agente
    #expect(outcome.killed == 2) // entrambi hanno ignorato il SIGHUP
    #expect(outcome.survivors == 0)
    #expect(waitUntil { isGoneOrZombie(agent) && isGoneOrZombie(session.shellPid) })
    #expect(survivors(ofSession: session.shellPid).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: path)) // a sessioni chiuse il file sparisce
}

@MainActor
@Test func reaperFindsTheAgentFromTheSnapshotOnceTheShellIsGone() throws {
    // Il caso comune: la zsh muore sull'hangup e l'agente che lo ignora resta, figlio di launchd,
    // con l'id di sessione della shell morta. Lì la prova è la fotografia presa mentre Relay era
    // vivo, e il `sleep` del finto agente si prova come suo figlio.
    let session = try #require(PtySession.spawn(running: #"sh -c "trap '' HUP TERM; sleep 600""#))
    defer { session.forceCleanup() }
    let agent = try #require(session.foregroundLeader())
    let directory = temporaryLedgerDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let ledger = PtySessionLedger(
        directory: directory, runID: "dead-run", owner: deadOwner
    )
    ledger.record(shellPid: session.shellPid, tabID: "tab")
    #expect(waitUntil {
        ledger.refreshMembers()
        return ledger.records.first?.members.count == 2 // `sh` e `sleep`
    })
    // Solo l'agente nella fotografia: il suo `sleep` deve passare dalla prova del genitore.
    let snapshot = try #require(ledger.records.first)
    let onlyAgent = PtySessionRecord(
        shellPid: snapshot.shellPid, shellStartedAt: snapshot.shellStartedAt, tabId: "tab",
        members: snapshot.members.filter { $0.pid == agent }
    )
    #expect(onlyAgent.members.count == 1)

    _ = kill(session.shellPid, SIGKILL)
    #expect(waitUntil {
        PtySessionTeardown.reap(session.shellPid)
        return !isAlive(session.shellPid)
    })
    #expect(isAlive(agent)) // l'hangup del leader non l'ha toccato
    #expect(survivors(ofSession: session.shellPid).count == 2)
    _ = try writeLedger(in: directory, runID: "dead-run", owner: deadOwner, sessions: [onlyAgent])

    let outcome = PtySessionReaper.reapOrphans(
        in: directory, currentRunID: "this-run", grace: 0.3, killGrace: 1
    )

    #expect(outcome.killed == 2) // `sh` e il suo `sleep`
    #expect(outcome.survivors == 0)
    #expect(waitUntil { survivors(ofSession: session.shellPid).isEmpty })
    #expect(waitUntil { !isAlive(agent) })
}

@Test func anUnrelatedSessionBehindARecycledPidIsLeftAlone() throws {
    // Il pid registrato ora è di un'altra shell (avvio diverso), e la fotografia parla di processi
    // con gli stessi pid ma altri avvii: nessuna prova di appartenenza, quindi nessun segnale.
    let session = try #require(PtySession.spawn(running: "sleep 120"))
    defer { session.forceCleanup() }
    let job = try #require(session.foregroundLeader())
    let live = try record(of: session)
    let jobIdentity = try #require(ProcessIdentity.of(job))
    let recycled = PtySessionRecord(
        shellPid: live.shellPid,
        shellStartedAt: live.shellStartedAt - 1_000_000,
        tabId: "tab",
        members: [ProcessIdentity(pid: job, startedAt: jobIdentity.startedAt - 1)]
    )
    let directory = temporaryLedgerDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    _ = try writeLedger(in: directory, runID: "dead-run", owner: deadOwner, sessions: [recycled])

    let outcome = PtySessionReaper.reapOrphans(
        in: directory, currentRunID: "this-run", grace: 0.2, killGrace: 0.2
    )

    #expect(outcome.sessions == 1)
    #expect(outcome.hungUp == 0)
    #expect(outcome.killed == 0)
    #expect(!isGoneOrZombie(session.shellPid))
    #expect(!isGoneOrZombie(job))
}

@Test func sessionsOfARelayStillRunningAreNotOrphans() throws {
    // Un'altra istanza viva (socket e layout suoi) possiede ancora le sue sessioni: il suo file
    // resta, e i processi pure.
    let session = try #require(PtySession.spawn(running: "sleep 120"))
    defer { session.forceCleanup() }
    let owner = try #require(ProcessIdentity.current)
    let directory = temporaryLedgerDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = try writeLedger(
        in: directory, runID: "live-run", owner: owner, sessions: [record(of: session)]
    )

    let outcome = PtySessionReaper.reapOrphans(in: directory, currentRunID: "this-run")

    #expect(outcome == PtySessionReaper.Outcome())
    #expect(FileManager.default.fileExists(atPath: path))
    #expect(!isGoneOrZombie(session.shellPid))
}

@Test func hangUpAtQuitReachesEveryMemberWithoutWaiting() throws {
    // Il gradino dell'uscita: un SIGHUP a tutta la sessione, non solo ai due gruppi che
    // `PtySessionTeardown` vede da una pty viva. `; true` impedisce a `sh` di fare exec di `sleep`.
    let session = try #require(PtySession.spawn(running: #"sh -c "sleep 120; true""#))
    defer { session.forceCleanup() }
    let agent = try #require(session.foregroundLeader())
    // `sh` è già in foreground ma il suo `sleep` può non essere ancora nato.
    #expect(waitUntil { survivors(ofSession: session.shellPid).count == 3 })

    let reached = try PtySessionReaper.hangUp([record(of: session)])

    #expect(reached == 3) // zsh, sh, sleep
    #expect(waitUntil { survivors(ofSession: session.shellPid).isEmpty })
    #expect(waitUntil { isGoneOrZombie(agent) })
}

// MARK: - Registro e teardown di una surface vera

@MainActor
@Test func aSurfaceLeavesTheLedgerOnlyOnceItsSessionIsClosed() async throws {
    let directory = temporaryLedgerDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let ledger = PtySessionLedger(directory: directory, runID: "run")
    let surface = SwiftTermEngine(ledger: ledger)
        .makeSurface(cwd: NSHomeDirectory(), shell: "/bin/zsh", env: ["RELAY_TAB_ID": "tab-9"])

    surface.start()
    let entry = try #require(ledger.records.first)
    #expect(ledger.records.count == 1)
    #expect(entry.tabId == "tab-9")
    #expect(entry.shell.isAlive)
    #expect(FileManager.default.fileExists(atPath: ledger.path))

    surface.teardown()
    #expect(!ledger.records.isEmpty) // l'escalation è differita: la voce resta fino alla fine

    let deadline = ContinuousClock.now + .seconds(10)
    while !ledger.records.isEmpty, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(ledger.records.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: ledger.path))
    #expect(!entry.shell.isAlive)
}
