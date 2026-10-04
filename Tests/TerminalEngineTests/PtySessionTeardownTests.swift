import Darwin
import Dispatch
import Foundation
@testable import TerminalEngine
import Testing

// Il teardown di una surface è l'unico punto in cui Relay promette all'utente ("will be
// terminated") di spegnere una sessione. `FakeEngine` non lo attraversa, quindi finché questi test
// non esistevano il percorso non era coperto da niente: chiudere una tab lasciava vivi shell,
// agente e descrittore della pty senza che un test diventasse rosso. Questi girano su pty **vere**,
// con una zsh interattiva e i suoi job, perché è la forma in cui il bug si manifesta.

// MARK: - Cattura

@Test func nothingToCaptureForAnUnstartedOrLaunchdShell() {
    #expect(PtySessionTeardown.capture(shellPid: 0) == nil)
    #expect(PtySessionTeardown.capture(shellPid: 1) == nil)
}

// MARK: - Hangup su pty vere

@Test func hangUpClosesTheWholeSession() throws {
    let session = try #require(PtySession.spawn(running: "sleep 120"))
    defer { session.forceCleanup() }

    let child = try #require(session.foregroundLeader())
    #expect(child != session.shellPid) // il job control ha messo `sleep` in un gruppo suo

    try PtySessionTeardown.hangUp(#require(PtySessionTeardown.capture(shellPid: session.shellPid)))

    #expect(waitUntil { !isAlive(child) })
    #expect(waitUntil { isGoneOrZombie(session.shellPid) })
}

@Test func hangUpAlsoClosesAShellSittingAtThePrompt() throws {
    // Il caso che spiega i numeri: anche una tab senza niente dentro leakava la sua shell.
    let session = try #require(PtySession.spawn(running: nil))
    defer { session.forceCleanup() }

    try PtySessionTeardown.hangUp(#require(PtySessionTeardown.capture(shellPid: session.shellPid)))

    #expect(waitUntil { isGoneOrZombie(session.shellPid) })
}

@Test func reapClearsTheZombieLeftByTheDeadShell() throws {
    let session = try #require(PtySession.spawn(running: nil))
    defer { session.forceCleanup() }

    try PtySessionTeardown.hangUp(#require(PtySessionTeardown.capture(shellPid: session.shellPid)))
    #expect(waitUntil { isGoneOrZombie(session.shellPid) })

    // La raccolta si ritenta nel loop: fra "non lavora più" e "è raccoglibile" c'è una transizione
    // di stato, e un solo `waitpid` può arrivare troppo presto.
    #expect(waitUntil {
        PtySessionTeardown.reap(session.shellPid)
        return !isAlive(session.shellPid)
    })
    PtySessionTeardown.reap(session.shellPid) // idempotente
}

@Test func thePrimaryDescriptorIsReleasedOnceTheSessionIsGone() throws {
    // Il leak di fd non si chiude segnalando il descriptor ma svuotando la sessione: morti i figli
    // la read sul descrittore primario della pty va in EOF, la DispatchIO completa e il suo cleanup
    // handler chiude l'fd.
    // Qui la DispatchIO è montata come la monta `LocalProcess`, chiusura ordinata compresa.
    let session = try #require(PtySession.spawn(running: "sleep 120"))
    defer { session.forceCleanup() }
    let capture = try #require(PtySessionTeardown.capture(shellPid: session.shellPid))

    let released = Flag()
    let primary = session.primary
    session.releasePrimary() // il drain lascia il posto alla DispatchIO, che legge lei
    let io = DispatchIO(
        type: .stream,
        fileDescriptor: primary,
        queue: .global()
    ) { _ in
        close(primary)
        released.raise()
    }
    io.setLimit(lowWater: 1)
    io.read(offset: 0, length: 4096, queue: .global()) { _, _, _ in }
    io.close()

    PtySessionTeardown.hangUp(capture)
    #expect(waitUntil(timeout: 5) { released.isRaised })
}

// MARK: - Job in background

@Test func aNohupJobInTheBackgroundDiesWithTheTab() throws {
    // La tab possiede tutta la sessione, non solo i due gruppi che il terminale vede: un job
    // lanciato con `nohup ... &` sta in un process group suo, ignora l'hangup, e prima moriva solo
    // con Relay. Il SIGHUP non lo tocca, il SIGTERM dell'escalation sì.
    let session = try #require(PtySession.spawn(running: nil))
    defer { session.forceCleanup() }
    let job = try #require(startBackgroundJob(in: session, "nohup sleep 600 > /dev/null 2>&1 &"))
    let capture = try #require(PtySessionTeardown.capture(shellPid: session.shellPid))
    #expect(capture.members.contains(job))

    PtySessionTeardown.hangUp(capture)
    #expect(waitUntil { isGoneOrZombie(session.shellPid) }) // la shell esce sull'hangup
    #expect(isRunning(job)) // il job no: è proprio quello che `nohup` promette

    // A shell morta la prova è la cattura: il job resta nostro anche senza leader.
    #expect(PtySessionTeardown.escalate(capture, signal: SIGTERM).signalled == 1)
    #expect(waitUntil { !isRunning(job) })
}

@Test func aJobDeafToHangupAndTermNeedsTheKill() throws {
    // Il caso peggiore: un job in background che ignora sia SIGHUP sia SIGTERM. Solo l'ultimo
    // gradino lo chiude, e la prova passa da un gradino all'altro.
    let session = try #require(PtySession.spawn(running: nil))
    defer { session.forceCleanup() }
    // `; true` impedisce a `sh` di fare exec di `sleep`: due processi nel job.
    let job = try #require(startBackgroundJob(
        in: session, #"sh -c "trap '' HUP TERM; sleep 600; true" &"#, processes: 2
    ))
    let capture = try #require(PtySessionTeardown.capture(shellPid: session.shellPid))

    PtySessionTeardown.hangUp(capture)
    #expect(waitUntil { isGoneOrZombie(session.shellPid) })
    let terminated = PtySessionTeardown.escalate(capture, signal: SIGTERM)
    usleep(200_000)
    #expect(isRunning(job))

    let killed = PtySessionTeardown.escalate(capture, trusted: terminated.proven, signal: SIGKILL)
    #expect(killed.signalled == 2) // `sh` e il suo `sleep`
    #expect(waitUntil { PtySessionReaper.processes(inSessions: [session.shellPid]).isEmpty })
}

@MainActor
@Test func closingASurfaceKillsItsNohupJob() async throws {
    // Il percorso vero: `SwiftTermSurface.teardown()`, con la sua scala differita. `/bin/sh` invece
    // della shell dell'utente, così il test non dipende da nessun file di configurazione.
    let directory = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("relay-teardown-\(UInt64.random(in: 0 ..< 1_000_000_000))")
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let ledger = PtySessionLedger(directory: directory, runID: "run")
    let surface = SwiftTermEngine(ledger: ledger)
        .makeSurface(cwd: NSHomeDirectory(), shell: "/bin/sh", env: [:])
    surface.start()
    let shell = try #require(ledger.records.first?.shellPid)
    surface.sendText("nohup sleep 600 > /dev/null 2>&1 &\n")

    var job: ProcessIdentity?
    let deadline = ContinuousClock.now + .seconds(5)
    while job == nil, ContinuousClock.now < deadline {
        job = PtySessionReaper.processes(inSessions: [shell])
            .map(\.identity).first { $0.pid != shell }
        if job == nil { try await Task.sleep(for: .milliseconds(50)) }
    }
    let nohupJob = try #require(job)

    surface.teardown()

    let closed = ContinuousClock.now + .seconds(10)
    while isRunning(nohupJob) || !ledger.records.isEmpty, ContinuousClock.now < closed {
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(!isRunning(nohupJob))
    #expect(PtySessionReaper.processes(inSessions: [shell]).isEmpty)
    #expect(ledger.records.isEmpty)
}

@Test func escalationLeavesAPidThatIsNoLongerOurs() throws {
    // Lo spazio pid gira in fretta: un processo catturato e segnalato più tardi può essere morto e
    // il suo pid riusato. Senza l'identità esatta non lo si tocca.
    let session = try #require(PtySession.spawn(running: nil))
    defer { session.forceCleanup() }
    let capture = try #require(PtySessionTeardown.capture(shellPid: session.shellPid))
    #expect(capture.members.map(\.pid) == [session.shellPid])

    _ = kill(session.shellPid, SIGKILL)
    #expect(waitUntil {
        PtySessionTeardown.reap(session.shellPid)
        return !isAlive(session.shellPid)
    })

    #expect(PtySessionTeardown.escalate(capture, signal: SIGKILL).signalled == 0)
}

@Test func startTimeIsStableForALiveProcessAndAbsentForADeadOne() {
    let mine = getpid()
    let first = PtySessionTeardown.startedAt(mine)
    #expect(first != nil)
    #expect(PtySessionTeardown.startedAt(mine) == first)
    #expect(PtySessionTeardown.startedAt(0) == nil)
}

// MARK: - Supporto

/// Lancia un job in background nella shell e ne ritorna il primo processo, quando nella sessione
/// sono comparsi `processes` processi oltre alla shell.
private func startBackgroundJob(
    in session: PtySession,
    _ command: String,
    processes: Int = 1
) -> ProcessIdentity? {
    let line = command + "\n"
    _ = line.withCString { write(session.primary, $0, strlen($0)) }
    var job: [ProcessIdentity] = []
    _ = waitUntil {
        job = PtySessionReaper.processes(inSessions: [session.shellPid])
            .map(\.identity)
            .filter { $0.pid != session.shellPid }
            .sorted { $0.startedAt < $1.startedAt }
        return job.count >= processes
    }
    return job.count >= processes ? job.first : nil
}

private func isRunning(_ identity: ProcessIdentity) -> Bool {
    PtySessionReaper.isRunning(identity)
}
