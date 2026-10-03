import Core
import Darwin
import Foundation

/// Una sessione pty aperta da Relay: la shell che `forkpty` ha reso session leader. Il suo pid è
/// anche l'id della sessione POSIX (`getsid`), che resta lo stesso anche quando il foreground passa
/// all'agente e ai suoi figli: è il perimetro che il reaper ritrova in una run successiva.
public struct PtySessionRecord: Codable, Equatable, Sendable {
    public let shellPid: pid_t
    public let shellStartedAt: UInt64
    /// La tab che possedeva la sessione, solo diagnostica: l'identità sta nella coppia pid/avvio.
    public let tabId: String?
    /// Gli altri processi della sessione all'ultima fotografia (`PtySessionLedger.refreshMembers`),
    /// per identità esatta. Sono la prova di appartenenza quando la shell non c'è più: una zsh esce
    /// sull'hangup e lascia l'agente orfano, e da quel momento solo questa lista dice che è nostro.
    public let members: [ProcessIdentity]

    public init(
        shellPid: pid_t,
        shellStartedAt: UInt64,
        tabId: String?,
        members: [ProcessIdentity] = []
    ) {
        self.shellPid = shellPid
        self.shellStartedAt = shellStartedAt
        self.tabId = tabId
        self.members = members
    }

    private enum CodingKeys: String, CodingKey {
        case shellPid, shellStartedAt, tabId, members
    }

    /// `members` è additivo: una voce che non ce l'ha (o che non la decodifica) resta una voce
    /// valida, con la sola prova del leader.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shellPid = try container.decode(pid_t.self, forKey: .shellPid)
        shellStartedAt = try container.decode(UInt64.self, forKey: .shellStartedAt)
        tabId = try container.decodeIfPresent(String.self, forKey: .tabId)
        members = (try? container.decodeIfPresent([ProcessIdentity].self, forKey: .members)) ?? []
    }

    public var shell: ProcessIdentity {
        ProcessIdentity(pid: shellPid, startedAt: shellStartedAt)
    }

    func with(members: [ProcessIdentity]) -> PtySessionRecord {
        PtySessionRecord(
            shellPid: shellPid, shellStartedAt: shellStartedAt, tabId: tabId, members: members
        )
    }
}

/// Il contenuto di un file del registro: le sessioni aperte da **una** run di Relay, con
/// l'identità del processo che le possedeva. Un file per run, così due istanze (l'app e una run di
/// sviluppo con socket e layout suoi) non scrivono mai lo stesso file.
public struct PtySessionLedgerFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let runId: String
    /// Il Relay che possedeva queste sessioni. Finché è vivo le sessioni sono sue, non orfane.
    public let owner: ProcessIdentity
    public let sessions: [PtySessionRecord]

    public init(runId: String, owner: ProcessIdentity, sessions: [PtySessionRecord]) {
        version = Self.currentVersion
        self.runId = runId
        self.owner = owner
        self.sessions = sessions
    }

    private enum CodingKeys: String, CodingKey {
        case version, runId, owner, sessions
    }

    /// Decode tollerante: `runId` e `owner` sono necessari (senza, non si può dire se le sessioni
    /// sono orfane), il resto no. Una voce di sessione illeggibile si scarta da sola invece di far
    /// perdere tutte le altre: un file scritto da una versione diversa deve ancora poter dire quali
    /// processi erano nostri.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        runId = try container.decode(String.self, forKey: .runId)
        owner = try container.decode(ProcessIdentity.self, forKey: .owner)
        let entries = try container.decodeIfPresent([Lossy].self, forKey: .sessions) ?? []
        sessions = entries.compactMap(\.record)
    }

    /// Una voce che non decodifica diventa `nil` invece di un errore.
    private struct Lossy: Decodable {
        let record: PtySessionRecord?

        init(from decoder: Decoder) throws {
            record = try? PtySessionRecord(from: decoder)
        }
    }
}

/// Registro su disco delle sessioni pty aperte da questa run: la memoria che sopravvive a Relay.
///
/// Chiudere una tab termina la sua sessione (`PtySessionTeardown`), ma uscire dall'app o crashare
/// no: il kernel fa hangup sulla pty e un agente bloccato il SIGHUP lo ignora (misurato, vedi
/// `docs/research/PERF.md`). Quei processi restano orfani per giorni, e al riavvio nessuno sa più
/// che erano nostri. Questo registro lo ricorda: una voce per shell avviata, tolta quando la tab
/// chiude davvero la sessione; al lancio successivo `PtySessionReaper` usa le voci rimaste.
///
/// Il path è iniettato (il composition root passa `~/.relay/sessions`, i test una dir temporanea):
/// come `LayoutStore`, questo tipo non conosce `~/.relay` né gli override d'ambiente.
@MainActor
public final class PtySessionLedger {
    /// La variabile d'ambiente che lega una shell alla sua tab: la stessa che usano gli hook.
    public nonisolated static let tabEnvironmentKey = "RELAY_TAB_ID"

    private nonisolated static let log = RelayLog.logger("sessions")

    public let directory: String
    public let runID: String
    private let owner: ProcessIdentity?
    public private(set) var records: [PtySessionRecord] = []
    private var refreshTimer: Timer?

    public init(
        directory: String,
        runID: String = RelayRunID.current,
        owner: ProcessIdentity? = .current
    ) {
        self.directory = directory
        self.runID = runID
        self.owner = owner
    }

    /// Il file di questa run.
    public var path: String {
        Self.path(for: runID, in: directory)
    }

    nonisolated static func path(for runID: String, in directory: String) -> String {
        (directory as NSString).appendingPathComponent("\(runID).json")
    }

    /// Registra una shell appena avviata. Va chiamata subito dopo il fork: l'istante di avvio si
    /// legge qui, e una shell già morta (exec fallito) non lascia una voce.
    public func record(shellPid: pid_t, tabID: String?) {
        guard shellPid > 1, let shell = ProcessIdentity.of(shellPid) else { return }
        records.removeAll { $0.shellPid == shellPid }
        records.append(PtySessionRecord(
            shellPid: shellPid, shellStartedAt: shell.startedAt, tabId: tabID
        ))
        persist()
    }

    /// Toglie la voce di una sessione chiusa davvero (fine dell'escalation del teardown). No-op se
    /// la voce non c'è.
    public func forget(shellPid: pid_t) {
        let before = records.count
        records.removeAll { $0.shellPid == shellPid }
        guard records.count != before else { return }
        persist()
    }

    /// Fotografa i membri vivi di ogni sessione la cui shell è ancora al suo posto, e riscrive il
    /// file solo se qualcosa è cambiato. È la prova che servirà al prossimo lancio se la shell
    /// muore prima dell'agente; una sessione con la shell già morta tiene l'ultima fotografia.
    public func refreshMembers() {
        guard !records.isEmpty else { return }
        let processes = PtySessionReaper.processes(inSessions: Set(records.map(\.shellPid)))
        let ownUID = getuid()
        var changed = false
        records = records.map { record in
            guard processes.contains(where: { $0.identity == record.shell }) else { return record }
            let members = processes
                .filter {
                    $0.sessionID == record.shellPid && $0.identity != record.shell
                        && $0.uid == ownUID
                }
                .map(\.identity)
                .sorted { ($0.pid, $0.startedAt) < ($1.pid, $1.startedAt) }
            guard members != record.members else { return record }
            changed = true
            return record.with(members: members)
        }
        if changed { persist() }
    }

    /// Rinfresca la fotografia a intervalli, finché l'app vive. Un crash non passa da
    /// `applicationWillTerminate`, quindi la prova va presa prima: a ogni giro una lettura della
    /// tabella dei processi (~0,2 ms su 900 pid, vedi `docs/research/PERF.md`) e una scrittura solo
    /// se i membri sono cambiati. Senza sessioni registrate il giro è un `guard`.
    public func startRefreshing(every interval: TimeInterval = 30) {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMembers() }
        }
        timer.tolerance = interval / 2 // nessuna precisione richiesta: si lascia coalescere
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    public func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Scrive il file della run in modo atomico; senza sessioni lo toglie, perché un file vuoto non
    /// ha niente da dire al prossimo lancio. Best-effort ma non silenzioso: un registro che non si
    /// scrive vuol dire orfani non recuperabili, e va detto nel log.
    private func persist() {
        guard let owner else {
            Self.log.error("session ledger disabled: cannot read Relay's own start time")
            return
        }
        let url = URL(fileURLWithPath: path)
        do {
            if records.isEmpty {
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.removeItem(at: url)
                }
                return
            }
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true
            )
            let file = PtySessionLedgerFile(runId: runID, owner: owner, sessions: records)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: url, options: .atomic)
        } catch {
            Self.log.error(
                "session ledger write failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Run precedenti

    /// Un file del registro letto da disco.
    public struct StoredFile: Sendable {
        public let path: String
        public let file: PtySessionLedgerFile
    }

    /// I file del registro di **altre** run. Un file che non decodifica viene tolto e loggato: è
    /// scritto in modo atomico, quindi non è una scrittura a metà, e senza `owner` nessuno potrà
    /// mai dire se le sue sessioni sono orfane.
    public nonisolated static func otherRuns(
        in directory: String,
        excluding runID: String
    ) -> [StoredFile] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory)
        } catch CocoaError.fileReadNoSuchFile {
            return [] // nessuna sessione mai registrata: il caso normale al primo avvio
        } catch {
            log.error(
                "session ledger unreadable: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
        var stored: [StoredFile] = []
        for name in names.sorted() where name.hasSuffix(".json") && name != "\(runID).json" {
            let path = (directory as NSString).appendingPathComponent(name)
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let file = try JSONDecoder().decode(PtySessionLedgerFile.self, from: data)
                stored.append(StoredFile(path: path, file: file))
            } catch {
                log.error("session ledger \(name, privacy: .public) unreadable, removed")
                remove(path)
            }
        }
        return stored
    }

    /// Toglie un file del registro di una run precedente, a sessioni chiuse.
    public nonisolated static func remove(_ path: String) {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch CocoaError.fileNoSuchFile {
            return // tolto da un'altra istanza nel frattempo: è lo stato voluto
        } catch {
            log.error(
                "session ledger removal failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
