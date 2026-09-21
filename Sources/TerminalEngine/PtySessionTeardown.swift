import Darwin
import Foundation

/// Chiusura della **sessione POSIX** di una pty, non della sola view.
///
/// Invariante di proprietà: *una tab possiede la sessione POSIX della sua pty*. Sono suoi la shell
/// che `forkpty` ha reso session leader e i process group nati sotto quel controlling terminal:
/// chiudere la tab li chiude. Un processo che si è staccato apposta (`setsid`, o un `nohup` che ha
/// abbandonato la sessione) esce da quel perimetro e non lo inseguiamo: è una scelta dell'utente,
/// non un residuo.
///
/// Serve perché `LocalProcess.terminate()` di SwiftTerm la sessione non la chiude. Fa `io.close()`
/// senza `.stop`, e la read pendente sul descrittore primario della pty non completa mai (nessun
/// EOF finché un figlio tiene aperto l'altro capo): il cleanup handler non gira, il descrittore
/// resta aperto e quindi la pty non fa **hangup**. Il `SIGTERM` che manda alla sola shell, una zsh
/// interattiva lo ignora.
/// Senza questo tipo, chiudere una tab lascia vivi shell, agente e fd finché Relay non muore.
/// Misure e riproduzione in `docs/research/PERF.md`.
///
/// La scala dei segnali è quella di un terminale che si chiude davvero: SIGHUP subito, poi SIGTERM,
/// poi SIGKILL ai superstiti. L'escalation è differita, e un pgid da solo non basta a indirizzarla:
/// lo spazio pid di macOS gira in fretta (misurati ~3400 pid/minuto su una macchina di lavoro, cioè
/// un giro completo in mezz'ora), quindi fra la cattura e il segnale quel pgid può appartenere a un
/// altro process group. Per questo `Target` porta anche l'istante di avvio del leader, e
/// l'escalation salta i target che non corrispondono più: meglio lasciare vivo un residuo che
/// mandare un SIGKILL a un gruppo di qualcun altro.
public enum PtySessionTeardown {
    /// Un process group da segnalare, con l'identità che ne permette il riconoscimento più tardi.
    public struct Target: Equatable, Sendable {
        public let pgid: pid_t
        /// Istante di avvio del leader del gruppo (il processo con pid == pgid), in microsecondi.
        /// `nil` se non leggibile: quel target riceve il SIGHUP immediato ma **non** l'escalation,
        /// perché senza identità non possiamo distinguerlo da un pgid riciclato.
        public let leaderStartedAt: UInt64?

        public init(pgid: pid_t, leaderStartedAt: UInt64?) {
            self.pgid = pgid
            self.leaderStartedAt = leaderStartedAt
        }
    }

    /// I process group da segnalare, in ordine: prima quello in **foreground** (è chi sta usando il
    /// terminale, tipicamente l'agente, e con il job control sta in un gruppo diverso dalla shell),
    /// poi quello della shell. Deduplicati: a shell ferma al prompt i due coincidono.
    ///
    /// Scarta tutto ciò che è `<= 1`: `tcgetpgrp` ritorna `-1` in errore e una shell mai avviata ha
    /// pid `0`, e `killpg` su quei valori colpirebbe il gruppo sbagliato (o quello di `launchd`).
    /// Puro: è la sola parte che ha senso testare senza pty vere.
    public static func pgids(shellPid: pid_t, foregroundPgid: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        for candidate in [foregroundPgid, shellPid] where candidate > 1 {
            if !result.contains(candidate) { result.append(candidate) }
        }
        return result
    }

    /// Cattura i target di una pty viva. Va chiamata **prima** di `terminate()`, che azzera
    /// `childfd` e rende `tcgetpgrp` inutilizzabile.
    public static func targets(shellPid: pid_t, childfd: Int32) -> [Target] {
        let foreground = childfd >= 0 ? tcgetpgrp(childfd) : -1
        return pgids(shellPid: shellPid, foregroundPgid: foreground).map { pgid in
            Target(pgid: pgid, leaderStartedAt: startedAt(pgid))
        }
    }

    /// Hangup: è il segnale che un terminale manda chiudendosi, e le shell lo propagano ai loro
    /// job. Va a tutti i target, anche a quelli senza identità: qui la cattura è appena avvenuta,
    /// non c'è finestra di riciclo.
    public static func hangUp(_ targets: [Target]) {
        for target in targets {
            _ = killpg(target.pgid, SIGHUP)
        }
    }

    /// Segnala i target **ancora identici** a quando sono stati catturati, e ritorna quanti ne ha
    /// raggiunti. Un target il cui leader è sparito viene saltato: il gruppo può avere ancora
    /// membri, ma senza il leader non possiamo provare che il pgid sia ancora il nostro.
    @discardableResult
    public static func escalate(_ targets: [Target], signal: Int32) -> Int {
        var signalled = 0
        for target in targets {
            guard let captured = target.leaderStartedAt,
                  startedAt(target.pgid) == captured,
                  killpg(target.pgid, signal) == 0 else { continue }
            signalled += 1
        }
        return signalled
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
    /// shell a ogni giro. Non blocca la chiusura: la tab sparisce subito, la sessione si spegne
    /// dietro. Le attese sono generose di proposito, il SIGHUP è quasi sempre l'unico segnale che
    /// serve e l'escalation è la rete per chi lo ignora.
    @MainActor
    public static func escalateAfterGrace(_ targets: [Target], reaping shellPid: pid_t) {
        guard !targets.isEmpty || shellPid > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + terminateGrace) {
            escalate(targets, signal: SIGTERM)
            reap(shellPid)
            DispatchQueue.main.asyncAfter(deadline: .now() + killGrace) {
                escalate(targets, signal: SIGKILL)
                reap(shellPid)
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
