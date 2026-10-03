import Core
import Darwin
import Foundation

/// Chiude le sessioni pty che Relay ha aperto e che sono sopravvissute alla sua uscita o al suo
/// crash: il complemento di `PtySessionTeardown`, che copre solo la chiusura di una tab.
///
/// Quando Relay esce il kernel chiude la pty e fa hangup, ma un agente bloccato il SIGHUP lo ignora
/// (Claude Code gestisce i segnali nel suo event loop JS: se è fermo non risponde nemmeno al
/// SIGTERM) e resta vivo, figlio di `launchd`, con il suo albero di server MCP. Misurati 52 orfani
/// per giorni sulla macchina di lavoro, e quattro sessioni girate due volte sullo stesso transcript
/// dopo il resume. Numeri in `docs/research/PERF.md`.
///
/// Il perimetro è la **sessione POSIX** della shell (`getsid(pid) == shellPid`), come
/// nell'invariante di `ARCHITECTURE.md`: il foreground group cambia quando parte l'agente, la
/// sessione no. Un processo di quella sessione è nostro se lo si può **provare**:
///
/// - il leader è ancora la shell registrata (pid **e** istante di avvio): allora la sessione è
///   nostra e lo è ogni suo membro;
/// - oppure, a leader morto (una zsh esce sull'hangup, l'agente che lo ignora resta: è il caso
///   comune, misurato anche con la configurazione vera dell'utente), il processo è fra i membri che
///   il registro ha fotografato mentre Relay era vivo (identità esatta), o è figlio vivo di uno di
///   loro (un hook lanciato dall'agente dopo l'uscita). Un id di sessione riusato da altri non ha
///   nessuna delle due prove: non si tocca.
///
/// L'ambiente non è una prova utilizzabile: il `RELAY_RUN_ID` che ogni processo eredita sarebbe
/// stato perfetto, ma macOS non espone più l'ambiente degli altri processi in `KERN_PROCARGS2`
/// nemmeno allo stesso utente (verificato su Darwin 25: arrivano solo gli argomenti).
///
/// La scala è SIGHUP, attesa breve, SIGKILL ai superstiti. Niente SIGTERM: contro un agente
/// bloccato è inutile (misurato), e chi gestisce i segnali ha già avuto il SIGHUP.
public enum PtySessionReaper {
    /// Un processo della tabella, quanto basta a decidere. Gli zombie non ci entrano: sono già
    /// morti, li raccoglie il loro genitore (o `launchd`).
    struct ProcessEntry: Equatable {
        let identity: ProcessIdentity
        let sessionID: pid_t
        let parentPid: pid_t
        let uid: uid_t
    }

    /// Cosa è successo, per il log e per i test.
    public struct Outcome: Equatable, Sendable {
        /// Sessioni considerate (registrate da run il cui Relay non c'è più).
        public var sessions = 0
        /// Processi raggiunti dal SIGHUP.
        public var hungUp = 0
        /// Processi che hanno ignorato il SIGHUP e hanno preso il SIGKILL.
        public var killed = 0
        /// Processi ancora vivi a scala finita (non dovrebbe succedere: SIGKILL non si ignora).
        public var survivors = 0

        public init() {}
    }

    private static let log = RelayLog.logger("sessions")

    // MARK: - Lancio

    /// Chiude le sessioni delle run precedenti il cui Relay non è più vivo, e ne toglie i file dal
    /// registro. Va chiamata al lancio **prima** di ripristinare qualsiasi sessione: un resume
    /// accanto al suo orfano scriverebbe due volte sullo stesso transcript.
    ///
    /// Sincrona: blocca al massimo `grace + killGrace`, e solo se ci sono superstiti (chi muore sul
    /// SIGHUP accorcia l'attesa). I file di un Relay ancora vivo (un'altra istanza con socket e
    /// layout suoi) restano dove sono: quelle sessioni non sono orfane.
    @discardableResult
    public static func reapOrphans(
        in directory: String,
        currentRunID: String,
        grace: TimeInterval = 1,
        killGrace: TimeInterval = 0.5
    ) -> Outcome {
        let stored = PtySessionLedger.otherRuns(in: directory, excluding: currentRunID)
        let orphaned = stored.filter { !$0.file.owner.isAlive }
        let sessions = orphaned.flatMap(\.file.sessions)
        let outcome = reap(sessions, grace: grace, killGrace: killGrace)
        if outcome.sessions > 0 {
            let (count, runs) = (outcome.sessions, orphaned.count)
            let (hungUp, killed, left) = (outcome.hungUp, outcome.killed, outcome.survivors)
            log.notice("""
            orphaned sessions: \(count, privacy: .public) from \(runs, privacy: .public) runs, \
            hung up \(hungUp, privacy: .public), killed \(killed, privacy: .public), \
            survivors \(left, privacy: .public)
            """)
        }
        // Con dei superstiti il file resta: il prossimo lancio riprova, con gli stessi controlli.
        guard outcome.survivors == 0 else { return outcome }
        for file in orphaned {
            PtySessionLedger.remove(file.path)
        }
        return outcome
    }

    /// La scala completa su sessioni date: SIGHUP a ogni membro, attesa fino a `grace` (finisce
    /// prima se muoiono tutti), poi SIGKILL a chi resta, compresi i membri nati nel frattempo (un
    /// agente che riceve SIGHUP lancia i suoi hook `SessionEnd`).
    public static func reap(
        _ sessions: [PtySessionRecord],
        grace: TimeInterval = 1,
        killGrace: TimeInterval = 0.5
    ) -> Outcome {
        var outcome = Outcome()
        outcome.sessions = sessions.count
        guard !sessions.isEmpty else { return outcome }

        let first = members(of: sessions, trusted: [])
        outcome.hungUp = signal(first, SIGHUP)
        _ = waitUntilGone(first, timeout: grace)

        let second = members(of: sessions, trusted: Set(first))
        outcome.killed = signal(second, SIGKILL)
        _ = waitUntilGone(second, timeout: killGrace)

        outcome.survivors = members(of: sessions, trusted: Set(first + second)).count
        return outcome
    }

    // MARK: - Decisione (pura)

    /// I membri di una sessione registrata che abbiamo il diritto di segnalare. Puro: la tabella
    /// dei processi arriva da fuori.
    ///
    /// - `trusted`: processi già provati nostri a un giro precedente della scala. Servono quando il
    ///   leader muore fra il SIGHUP e il SIGKILL: il resto della sessione non perde la sua prova.
    static func members(
        of record: PtySessionRecord,
        in processes: [ProcessEntry],
        trusted: Set<ProcessIdentity>,
        ownUID: uid_t,
        selfPID: pid_t
    ) -> [ProcessIdentity] {
        guard record.shellPid > 1 else { return [] }
        let candidates = processes.filter { entry in
            entry.sessionID == record.shellPid
                && entry.identity.pid > 1
                && entry.identity.pid != selfPID
                && entry.uid == ownUID
                // Un membro nasce dopo la shell che ha aperto la sessione: uno più vecchio non
                // può essere nostro, qualunque cosa dica il suo id di sessione.
                && entry.identity.startedAt >= record.shellStartedAt
        }
        if candidates.contains(where: { $0.identity == record.shell }) {
            return candidates.map(\.identity)
        }
        // Leader morto: si parte da chi è provato per identità esatta, poi si scende ai figli. Il
        // ppid di un processo vivo è il pid del suo genitore vivo, che non può essere stato
        // riciclato finché è vivo: un figlio di un membro provato è nostro anche lui.
        let known = trusted.union(record.members)
        var proven = Set(candidates.map(\.identity).filter(known.contains))
        var grew = true
        while grew {
            let parents = Set(proven.map(\.pid))
            let children = candidates.filter {
                !proven.contains($0.identity) && parents.contains($0.parentPid)
            }
            proven.formUnion(children.map(\.identity))
            grew = !children.isEmpty
        }
        return candidates.map(\.identity).filter(proven.contains)
    }

    // MARK: - Sistema

    /// I membri di tutte le sessioni date, letti adesso dalla tabella dei processi.
    static func members(
        of sessions: [PtySessionRecord],
        trusted: Set<ProcessIdentity>
    ) -> [ProcessIdentity] {
        let ids = Set(sessions.map(\.shellPid).filter { $0 > 1 })
        let processes = processes(inSessions: ids)
        let ownUID = getuid()
        let selfPID = getpid()
        var result: [ProcessIdentity] = []
        for session in sessions {
            let found = members(
                of: session,
                in: processes,
                trusted: trusted,
                ownUID: ownUID,
                selfPID: selfPID
            )
            for identity in found where !result.contains(identity) {
                result.append(identity)
            }
        }
        return result
    }

    /// I processi vivi (non zombie) che stanno in una delle sessioni date. `getsid` funziona su
    /// qualsiasi pid su macOS, anche di altre sessioni e utenti (verificato): la lettura del
    /// `proc_bsdinfo` si paga solo per i candidati.
    static func processes(inSessions ids: Set<pid_t>) -> [ProcessEntry] {
        guard !ids.isEmpty else { return [] }
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        // Margine: fra le due chiamate possono nascere processi.
        var pids = [pid_t](repeating: 0, count: Int(estimate) * 2)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        var entries: [ProcessEntry] = []
        for pid in pids.prefix(Int(count)) where pid > 1 {
            let sessionID = getsid(pid)
            guard ids.contains(sessionID), let info = bsdInfo(pid), !info.isZombie else { continue }
            entries.append(ProcessEntry(
                identity: ProcessIdentity(pid: pid, startedAt: info.startedAt),
                sessionID: sessionID,
                parentPid: info.parentPid,
                uid: info.uid
            ))
        }
        return entries
    }

    /// Segnala i processi **ancora identici** a quando sono stati letti, e ritorna quanti ne ha
    /// raggiunti. Mai pid <= 1, mai Relay stesso.
    static func signal(_ targets: [ProcessIdentity], _ signal: Int32) -> Int {
        var signalled = 0
        for target in targets where target.pid > 1 && target.pid != getpid() {
            guard isRunning(target), kill(target.pid, signal) == 0 else { continue }
            signalled += 1
        }
        return signalled
    }

    /// Attende che tutti i target siano morti (o zombie), al massimo `timeout`. `true` se ci sono
    /// riusciti.
    static func waitUntilGone(_ targets: [ProcessIdentity], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if !targets.contains(where: isRunning) { return true }
            if Date() >= deadline { return false }
            usleep(25000)
        }
    }

    /// Vivo, non zombie, ed è lo stesso processo.
    static func isRunning(_ identity: ProcessIdentity) -> Bool {
        guard let info = bsdInfo(identity.pid) else { return false }
        return !info.isZombie && info.startedAt == identity.startedAt
    }

    private struct BSDInfo {
        let startedAt: UInt64
        let parentPid: pid_t
        let uid: uid_t
        let isZombie: Bool
    }

    private static func bsdInfo(_ pid: pid_t) -> BSDInfo? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return BSDInfo(
            startedAt: UInt64(info.pbi_start_tvsec) &* 1_000_000 &+ UInt64(info.pbi_start_tvusec),
            parentPid: pid_t(info.pbi_ppid),
            uid: info.pbi_uid,
            isZombie: info.pbi_status == UInt32(SZOMB)
        )
    }
}
