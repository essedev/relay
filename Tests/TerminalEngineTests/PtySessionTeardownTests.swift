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

// MARK: - Supporto

/// Flag thread-safe: il cleanup handler della DispatchIO gira su una queue di background.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func raise() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isRaised: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Una zsh interattiva dentro una pty vera, come quella che Relay apre in una tab.
private struct PtySession {
    let shellPid: pid_t
    let primary: Int32
    private let primaryOwned: Ref<Bool>
    private let drainStopped: Flag

    /// `running` `nil` = shell ferma al prompt.
    ///
    /// Le stringhe C si allocano **prima** della fork: swift-testing gira i test in parallelo,
    /// quindi il processo è multithread e fra `fork` ed `exec` il figlio può chiamare solo funzioni
    /// async-signal-safe. Un `strdup` (o qualsiasi allocazione Swift) lì dentro prende il lock di
    /// malloc che un altro thread può aver lasciato preso alla fork, e il figlio resta appeso senza
    /// mai eseguire la shell.
    ///
    /// `-f` salta gli rc file (i test non dipendono dalla config dell'utente), `-i` accende il job
    /// control, che è ciò che mette il comando in un process group suo.
    static func spawn(running command: String?) -> PtySession? {
        var argv: [UnsafeMutablePointer<CChar>?] = ["/bin/zsh", "-f", "-i"]
            .map { $0.withCString { strdup($0) } }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = [
            "TERM=dumb",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME=" + NSTemporaryDirectory(),
        ].map { $0.withCString { strdup($0) } }
        envp.append(nil)
        defer {
            for pointer in argv + envp {
                free(pointer)
            }
        }

        // La maschera dei segnali si eredita attraverso fork **ed exec**, e i thread di
        // swift-testing/libdispatch ne hanno una piena. Una zsh che parte con SIGCHLD e SIGTTOU
        // bloccati esegue il prompt ma non fa job control: resta lì senza lanciare il comando.
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)

        var primary: Int32 = 0
        var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&primary, nil, nil, &size)
        if pid == 0 {
            sigprocmask(SIG_SETMASK, &emptyMask, nil)
            for signalNumber in [SIGCHLD, SIGPIPE, SIGTTOU, SIGTTIN, SIGHUP, SIGTERM, SIGINT] {
                signal(signalNumber, SIG_DFL)
            }
            _ = execve("/bin/zsh", &argv, &envp)
            _exit(127)
        }
        guard pid > 0 else { return nil }
        let session = PtySession(
            shellPid: pid, primary: primary, primaryOwned: Ref(true), drainStopped: Flag()
        )
        session.startDraining()
        guard session.waitForShell() else {
            session.forceCleanup()
            return nil
        }
        if let command {
            let line = command + "\n"
            _ = line.withCString { write(primary, $0, strlen($0)) }
            guard session.waitForForegroundJob() else {
                session.forceCleanup()
                return nil
            }
        }
        return session
    }

    /// Qualcuno deve leggere dal descrittore primario, o zsh si blocca in `write` e da lì non
    /// processa più né
    /// l'input né il proprio handler di SIGHUP: sembrerebbe un teardown che non funziona, e invece
    /// è il test che non si comporta come un terminale. Descrittore in non-blocking così fermare il
    /// drain è un flag e non serve svegliare una `read` bloccante.
    private func startDraining() {
        _ = fcntl(primary, F_SETFL, fcntl(primary, F_GETFL, 0) | O_NONBLOCK)
        let fd = primary
        let stopped = drainStopped
        let thread = Thread {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while !stopped.isRaised {
                let count = read(fd, &buffer, buffer.count)
                if count > 0 { continue }
                if count < 0, errno == EBADF { break }
                usleep(2000) // EAGAIN, EINTR o EIO a sessione finita: si riprova finché serve
            }
        }
        thread.stackSize = 64 * 1024
        thread.start()
    }

    /// Ferma il drain prima di cedere il descrittore primario a un altro lettore.
    func stopDraining() {
        drainStopped.raise()
        usleep(10000)
    }

    /// La shell è viva quando ha davvero fatto `exec`: `tcgetpgrp` non basta, perché il figlio
    /// della fork possiede già il terminale prima di diventare una zsh.
    private func waitForShell() -> Bool {
        waitUntil {
            var name = [CChar](repeating: 0, count: 64)
            guard proc_name(shellPid, &name, UInt32(name.count)) > 0 else { return false }
            return String(cString: name) == "zsh"
        }
    }

    /// Il comando è partito quando il foreground group non è più quello della shell.
    private func waitForForegroundJob() -> Bool {
        waitUntil {
            let foreground = tcgetpgrp(primary)
            return foreground > 0 && foreground != shellPid
        }
    }

    /// Il pid leader del gruppo in foreground (per `sleep` è il suo stesso pid).
    func foregroundLeader() -> pid_t? {
        let foreground = tcgetpgrp(primary)
        return foreground > 0 ? foreground : nil
    }

    /// Cede il descrittore primario a chi lo chiuderà (la DispatchIO), così `forceCleanup` non lo
    /// chiude due
    /// volte.
    func releasePrimary() {
        stopDraining()
        primaryOwned.value = false
    }

    /// Rete di sicurezza: un test rosso non deve lasciare processi vivi sulla macchina.
    func forceCleanup() {
        drainStopped.raise()
        _ = killpg(shellPid, SIGKILL)
        _ = kill(shellPid, SIGKILL)
        var status: Int32 = 0
        _ = waitpid(shellPid, &status, WNOHANG)
        if primaryOwned.value { close(primary) }
    }
}

private final class Ref<Value> {
    var value: Value
    init(_ value: Value) {
        self.value = value
    }
}

private func isAlive(_ pid: pid_t) -> Bool {
    kill(pid, 0) == 0
}

/// `kill(pid, 0)` riesce anche su uno zombie: per "il processo non lavora più" serve lo stato.
private func isGoneOrZombie(_ pid: pid_t) -> Bool {
    guard isAlive(pid) else { return true }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return true }
    return info.pbi_status == UInt32(SZOMB)
}

/// Polling breve: i segnali sono asincroni e una sleep fissa sarebbe lenta o flaky.
private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        usleep(20000)
    }
    return condition()
}
