import Darwin
import Dispatch
import Foundation
@testable import TerminalEngine
import Testing

// Il teardown di una surface è l'unico punto in cui Relay promette all'utente ("will be
// terminated") di spegnere una sessione. `FakeEngine` non lo attraversa, quindi finché questi test
// non esistevano il percorso non era coperto da niente: chiudere una tab lasciava vivi shell,
// agente e descrittore della pty senza che un test diventasse rosso. Questi girano su pty **vere**,
// con una
// zsh interattiva e un figlio in foreground, perché è la forma in cui il bug si manifesta.

// MARK: - Scelta dei process group (puro)

@Test func foregroundGroupComesBeforeTheShellGroup() {
    #expect(PtySessionTeardown.pgids(shellPid: 100, foregroundPgid: 200) == [200, 100])
}

@Test func shellAtThePromptYieldsASingleGroup() {
    // Senza comandi in foreground `tcgetpgrp` ritorna il pgid della shell: un solo target.
    #expect(PtySessionTeardown.pgids(shellPid: 100, foregroundPgid: 100) == [100])
}

@Test func failedForegroundLookupIsDropped() {
    // `tcgetpgrp` ritorna -1 in errore: `killpg(-1)` colpirebbe ogni processo dell'utente.
    #expect(PtySessionTeardown.pgids(shellPid: 100, foregroundPgid: -1) == [100])
}

@Test func launchdAndUnstartedShellsAreDropped() {
    #expect(PtySessionTeardown.pgids(shellPid: 1, foregroundPgid: 1).isEmpty)
    #expect(PtySessionTeardown.pgids(shellPid: 0, foregroundPgid: -1).isEmpty)
}

// MARK: - Hangup su pty vere

@Test func hangUpClosesTheWholeSession() throws {
    let session = try #require(PtySession.spawn(running: "sleep 120"))
    defer { session.forceCleanup() }

    let child = try #require(session.foregroundLeader())
    #expect(child != session.shellPid) // il job control ha messo `sleep` in un gruppo suo

    PtySessionTeardown.hangUp(PtySessionTeardown.targets(
        shellPid: session.shellPid, childfd: session.primary
    ))

    #expect(waitUntil { !isAlive(child) })
    #expect(waitUntil { isGoneOrZombie(session.shellPid) })
}

@Test func hangUpAlsoClosesAShellSittingAtThePrompt() throws {
    // Il caso che spiega i numeri: anche una tab senza niente dentro leakava la sua shell.
    let session = try #require(PtySession.spawn(running: nil))
    defer { session.forceCleanup() }

    PtySessionTeardown.hangUp(PtySessionTeardown.targets(
        shellPid: session.shellPid, childfd: session.primary
    ))

    #expect(waitUntil { isGoneOrZombie(session.shellPid) })
}

@Test func reapClearsTheZombieLeftByTheDeadShell() throws {
    let session = try #require(PtySession.spawn(running: nil))
    defer { session.forceCleanup() }

    PtySessionTeardown.hangUp(PtySessionTeardown.targets(
        shellPid: session.shellPid, childfd: session.primary
    ))
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
    let targets = PtySessionTeardown.targets(
        shellPid: session.shellPid, childfd: session.primary
    )

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

    PtySessionTeardown.hangUp(targets)
    #expect(waitUntil(timeout: 5) { released.isRaised })
}

// MARK: - Identità del target

@Test func escalationSkipsAGroupWhoseLeaderIsGone() throws {
    // Lo spazio pid gira in fretta: un pgid catturato e segnalato più tardi può essere di un altro
    // gruppo. Senza il leader vivo non possiamo dimostrare che sia ancora il nostro, quindi si
    // lascia stare.
    let session = try #require(PtySession.spawn(running: nil))
    defer { session.forceCleanup() }
    let targets = PtySessionTeardown.targets(
        shellPid: session.shellPid, childfd: session.primary
    )
    #expect(targets.count == 1)

    _ = kill(session.shellPid, SIGKILL)
    #expect(waitUntil {
        PtySessionTeardown.reap(session.shellPid)
        return !isAlive(session.shellPid)
    })

    #expect(PtySessionTeardown.escalate(targets, signal: SIGKILL) == 0)
}

@Test func startTimeIsStableForALiveProcessAndAbsentForADeadOne() {
    let mine = getpid()
    let first = PtySessionTeardown.startedAt(mine)
    #expect(first != nil)
    #expect(PtySessionTeardown.startedAt(mine) == first)
    #expect(PtySessionTeardown.startedAt(0) == nil)
}
