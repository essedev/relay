import Darwin
import Foundation

/// Chiusura della **sessione POSIX** di una pty, non della sola view.
///
/// Invariante di proprietà: *una tab possiede la sessione POSIX della sua pty*. Sono suoi la shell
/// che `forkpty` ha reso session leader e **ogni** processo nato in quella sessione: l'agente in
/// foreground, i suoi server MCP, e anche un job in background lanciato con `nohup` o `&`, che
/// cambia process group ma resta nella sessione. Chiudere la tab li chiude tutti. Esce dal
/// perimetro solo chi lascia la sessione davvero (`setsid`, tmux, un job launchd).
///
/// Serve perché `LocalProcess.terminate()` di SwiftTerm la sessione non la chiude. Fa `io.close()`
/// senza `.stop`, e la read pendente sul descrittore primario della pty non completa mai (nessun
/// EOF finché un figlio tiene aperto l'altro capo): il cleanup handler non gira, il descrittore
/// resta aperto e quindi la pty non fa **hangup**. Il `SIGTERM` che manda alla sola shell, una zsh
/// interattiva lo ignora. Senza questo tipo, chiudere una tab lascia vivi shell, agente e fd finché
/// Relay non muore. Misure e riproduzione in `docs/research/PERF.md`.
///
/// Membri e segnali sono quelli di `PtySessionReaper`, con le stesse prove di appartenenza: alla
/// cattura la shell è viva, quindi tutta la sessione è nostra; ai giri successivi la shell può
/// essere già uscita sul SIGHUP, e allora valgono i membri catturati e i loro figli vivi. Ogni
/// segnale verifica l'identità (pid **e** istante di avvio): lo spazio pid di macOS gira in fretta
/// (~3400 pid/minuto misurati, un giro in mezz'ora), e fra la cattura e l'escalation un pid può
/// essere di qualcun altro.
///
/// La scala è quella di un terminale che si chiude davvero: SIGHUP subito, poi SIGTERM (chi ignora
/// l'hangup apposta, come un job sotto `nohup`, ha ancora modo di chiudere pulito), poi SIGKILL ai
/// superstiti. Differita, così la tab sparisce subito e la sessione si spegne dietro.
public enum PtySessionTeardown {
    /// Una sessione fotografata alla chiusura: la shell (con l'eventuale fotografia del registro) e
    /// i membri provati nostri in quel momento.
    public struct Capture: Equatable, Sendable {
        public let record: PtySessionRecord
        public let members: [ProcessIdentity]
    }

    /// Cattura la sessione di una shell. `known` è la voce del registro, se c'è: porta la
    /// fotografia dei membri, che fa da prova se la shell è già uscita da sola (un `exit` che
    /// lascia un job in background). Senza voce serve la shell viva. `nil` se non c'è niente da
    /// chiudere.
    public static func capture(shellPid: pid_t, known: PtySessionRecord? = nil) -> Capture? {
        guard shellPid > 1 else { return nil }
        let record = known ?? ProcessIdentity.of(shellPid).map {
            PtySessionRecord(shellPid: shellPid, shellStartedAt: $0.startedAt, tabId: nil)
        }
        guard let record else { return nil }
        return Capture(record: record, members: PtySessionReaper.members(of: [record], trusted: []))
    }

    /// Hangup: il segnale che un terminale manda chiudendosi, a ogni membro catturato. Ritorna i
    /// processi raggiunti.
    @discardableResult
    public static func hangUp(_ capture: Capture) -> Int {
        PtySessionReaper.signal(capture.members, SIGHUP)
    }

    /// Un gradino dell'escalation: rilegge la sessione, segnala chi è ancora provato nostro (i
    /// membri catturati, chi è già stato segnalato, i loro figli vivi) e ritorna i processi
    /// raggiunti insieme alla prova aggiornata, da passare al gradino dopo.
    @discardableResult
    public static func escalate(
        _ capture: Capture,
        trusted: Set<ProcessIdentity> = [],
        signal: Int32
    ) -> (signalled: Int, proven: Set<ProcessIdentity>) {
        let proven = trusted.union(capture.members)
        let targets = PtySessionReaper.members(of: [capture.record], trusted: proven)
        return (PtySessionReaper.signal(targets, signal), proven.union(targets))
    }

    /// Raccoglie la shell morta. `terminate()` cancella il `DispatchSourceProcess` che avrebbe
    /// fatto `waitpid`, quindi senza questa chiamata ogni tab chiusa lascia uno zombie.
    /// Idempotente: a shell già raccolta `waitpid` ritorna `-1`/`ECHILD` e non fa danni.
    public static func reap(_ shellPid: pid_t) {
        guard shellPid > 1 else { return }
        var status: Int32 = 0
        _ = waitpid(shellPid, &status, WNOHANG)
    }

    /// Programma l'escalation dopo il SIGHUP: SIGTERM ai superstiti, poi SIGKILL, raccogliendo la
    /// shell a ogni giro. Non blocca la chiusura. Le attese sono generose di proposito: il SIGHUP è
    /// quasi sempre l'unico segnale che serve e l'escalation è la rete per chi lo ignora.
    ///
    /// `completion` corre a scala finita: è lì che la sessione esce dal registro
    /// (`PtySessionLedger.forget`). Prima sarebbe presto, perché se Relay esce durante l'attesa la
    /// sessione non ha ancora preso il SIGKILL e il prossimo lancio deve poterla ritrovare.
    @MainActor
    public static func escalateAfterGrace(
        _ capture: Capture?,
        reaping shellPid: pid_t,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        guard let capture else {
            reap(shellPid)
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + terminateGrace) {
            let terminated = escalate(capture, signal: SIGTERM)
            reap(shellPid)
            DispatchQueue.main.asyncAfter(deadline: .now() + killGrace) {
                escalate(capture, trusted: terminated.proven, signal: SIGKILL)
                reap(shellPid)
                completion()
            }
        }
    }

    /// Istante di avvio di un processo, in microsecondi. `nil` se il pid non esiste più o non è
    /// leggibile (altro uid). Insieme al pid è l'identità stabile di un processo: il pid da solo
    /// viene riciclato.
    static func startedAt(_ pid: pid_t) -> UInt64? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return UInt64(info.pbi_start_tvsec) &* 1_000_000 &+ UInt64(info.pbi_start_tvusec)
    }

    /// Attesa prima del SIGTERM: il tempo che una shell ci mette a propagare il SIGHUP ai job e a
    /// uscire.
    private static let terminateGrace: TimeInterval = 2
    /// Attesa fra SIGTERM e SIGKILL: quanto diamo a un processo per il suo cleanup.
    private static let killGrace: TimeInterval = 3
}
