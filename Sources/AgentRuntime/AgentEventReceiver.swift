import AgentProtocol
import Core
import Foundation

/// Receiver locale degli eventi agente: un Unix domain socket che riceve JSON lines (un
/// `AgentStateEvent` per riga) dagli hook (via CLI) e le inoltra al callback. Puro trasporto: non
/// conosce il model UI. Il binding `paneId -> tab` avviene nel coordinatore (composition root),
/// così `AgentRuntime` resta indipendente da `WorkspaceModel`.
///
/// Concorrenza: tutto lo stato del socket vive sulla serial `queue` dedicata; per questo la classe
/// è `@unchecked Sendable`. Il callback `onEvent` è `@Sendable` e può fare hop verso il MainActor.
public final class AgentEventReceiver: @unchecked Sendable {
    private let path: String
    private let onEvent: @Sendable (AgentStateEvent) -> Void
    private let queue = DispatchQueue(label: "dev.relay.agent-receiver")
    /// Drain delle connessioni in parallelo, deliberatamente: un client che si connette e non
    /// chiude (wedged) non deve fermare gli altri. Il prezzo è che l'ordine di consegna tra
    /// connessioni NON è garantito; lo ristabiliscono a valle il pump FIFO del coordinatore e la
    /// guardia di monotonicità sui timestamp negli store.
    private let readQueue = DispatchQueue(
        label: "dev.relay.agent-receiver.read",
        attributes: .concurrent
    )
    private let log = RelayLog.logger("agent-receiver")
    /// Coda di connessioni in attesa di `accept`. 128 = `kern.ipc.somaxconn` su macOS, cioè il
    /// massimo che il kernel onora: chiederne di più non serve a niente.
    private static let backlog: Int32 = 128

    private var listenFD: Int32 = -1
    /// Vogliamo essere in ascolto (tra `start` e `stop`): guida il self-heal a ritentare anche dopo
    /// un rebind fallito, quando `listenFD` è tornato -1. Slegato da `listenFD` di proposito.
    private var shouldListen = false
    private var acceptSource: DispatchSourceRead?
    /// Watch della runtime dir per il self-heal: se il socket file sparisce sotto di noi (una
    /// seconda istanza che fa `unlink`, una pulizia esterna), ri-binda. Event-driven, nessun
    /// timer: reagisce solo al cambio della dir, costo zero sul path caldo degli eventi.
    private var dirSource: DispatchSourceFileSystemObject?

    public init(
        path: String = RelayRuntimePaths.socketPath,
        onEvent: @escaping @Sendable (AgentStateEvent) -> Void
    ) {
        self.path = path
        self.onEvent = onEvent
    }

    /// Avvia l'ascolto. Rimuove un socket file stantio con lo stesso path e arma il self-heal.
    public func start() throws {
        try queue.sync {
            shouldListen = true
            try openListeningSocket()
            startDirectoryWatch()
        }
    }

    /// Ferma l'ascolto e rimuove il socket file. Idempotente.
    public func stop() {
        queue.sync {
            shouldListen = false
            // Prima il watch, così il nostro stesso `unlink` non scatena un re-bind.
            dirSource?.cancel() // il cancel handler chiude l'fd della dir
            dirSource = nil
            teardownListen()
            unlink(path)
        }
    }

    // MARK: - Private (invocati su `queue`)

    private func openListeningSocket() throws {
        // No-stomp: se un'altra istanza viva ascolta già qui, `unlink`+`bind` le ruberebbe il
        // socket. Il guard single-instance (App.main) dovrebbe evitarci di arrivare qui; questa è
        // la rete di sicurezza a livello di trasporto (lancio dev sullo stesso ~/.relay, test).
        guard !UnixSocket.isListening(path: path) else { throw UnixSocketError.addressInUse }

        // Ricrea la runtime dir se sparita (es. `rm -rf ~/.relay`): senza, il `bind` fallirebbe con
        // ENOENT e il receiver resterebbe orfano.
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.socketFailed(errno) }

        var addr = try UnixSocket.address(path: path)
        unlink(path) // ora sicuro: il socket è stantio (owner morto) o assente
        let bindResult = UnixSocket.withSockAddr(&addr) { bind(fd, $0, $1) }
        guard bindResult == 0 else {
            close(fd)
            throw UnixSocketError.bindFailed(errno)
        }
        // Backlog al massimo che il kernel accetta (`kern.ipc.somaxconn`, 128 su macOS). Con
        // decine di sessioni agente gli hook si connettono a raffica: quando la coda è piena la
        // `connect` del client fallisce e l'evento è perso in silenzio, perché la CLI ingoia
        // l'errore per contratto (un problema di Relay non deve rompere l'agente).
        guard listen(fd, Self.backlog) == 0 else {
            close(fd)
            throw UnixSocketError.listenFailed(errno)
        }
        // Listener non bloccante: serve ad `acceptConnection` per drenare tutta la coda in un
        // giro solo (una `accept` bloccante al secondo giro fermerebbe la serial queue).
        setNonBlocking(fd)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        acceptSource = source
        source.resume()
        log.info("agent receiver listening")
    }

    /// Chiude la socket di ascolto corrente (senza toccare il watch della dir). Riusato da `stop`
    /// e dal re-bind del self-heal.
    private func teardownListen() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
    }

    /// Osserva la runtime dir del socket: al cambio (creazione/rimozione di un file) verifica se il
    /// nostro socket è sparito e in tal caso ri-binda. Best-effort: se la dir non è osservabile il
    /// binding resta valido, solo senza recupero automatico.
    private func startDirectoryWatch() {
        let dir = (path as NSString).deletingLastPathComponent
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else {
            log.error("agent receiver cannot watch runtime dir; self-heal disabled")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.rebindIfMissing() }
        source.setCancelHandler { close(fd) }
        dirSource = source
        source.resume()
    }

    /// Se stiamo ascoltando ma il socket file non c'è più, ri-binda. Solo quando il file è
    /// davvero assente: se esiste (un'altra istanza ne ha uno vivo) non lo tocchiamo, per non
    /// innescare un ping-pong; lo stomp lo previene già il guard + no-stomp.
    private func rebindIfMissing() {
        // Guardato da `shouldListen`, non da `listenFD >= 0`: un rebind fallito lascia `listenFD`
        // a -1, ma vogliamo comunque ritentare al prossimo cambio della dir finché non ci
        // riusciamo.
        guard shouldListen, access(path, F_OK) != 0 else { return }
        log.error("agent socket file vanished; rebinding")
        teardownListen()
        do {
            try openListeningSocket()
            log.info("agent receiver rebound")
        } catch {
            // listenFD resta -1; il watch è ancora armato e ritenta al prossimo cambio della dir.
            let reason = error.localizedDescription
            log.error("agent receiver rebind failed: \(reason, privacy: .public)")
        }
    }

    /// Svuota **tutta** la coda di accept a ogni risveglio della source. Accettarne una sola per
    /// evento lascia il backlog pieno sotto raffica, e un backlog pieno respinge la `connect` del
    /// client: l'evento sparisce senza che nessuno se ne accorga.
    private func acceptConnection() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else {
                if errno == EINTR { continue }
                // Coda svuotata: è la condizione di uscita normale del loop, non un errore.
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                // fd esauriti o listen fd invalido: senza un segnale il badge si fermerebbe in
                // silenzio. `privacy: .public`: un errno non è un dato dell'utente, e redatto il
                // log non dice più di quanto direbbe il silenzio.
                let reason = String(cString: strerror(errno))
                log.error("agent receiver accept failed: \(reason, privacy: .public)")
                return
            }
            // Su BSD/macOS l'fd accettato **eredita** O_NONBLOCK dal listener, che abbiamo reso
            // non bloccante per il loop qui sopra. `drain` legge in modo bloccante: senza questo
            // ripristino la read tornerebbe EAGAIN ogni volta che i byte del client non sono
            // ancora arrivati, e l'evento andrebbe perso invece che atteso.
            setBlocking(clientFD)
            // Connessioni effimere (una linea e chiudi): leggo fino a EOF fuori dalla accept
            // queue.
            readQueue.async { [weak self] in self?.drain(clientFD) }
        }
    }

    private func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    private func setBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
    }

    private func drain(_ fd: Int32) {
        var buffer = Data()
        let chunkSize = 4096
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let n = read(fd, &chunk, chunkSize)
            if n > 0 {
                buffer.append(contentsOf: chunk[0 ..< n])
            } else if n == 0 {
                break // EOF pulito: il client ha inviato la sua linea e chiuso.
            } else if errno == EINTR {
                continue // interrotto da un segnale: riprova, non è una fine.
            } else {
                // Errore di trasporto reale: senza log sarebbe indistinguibile da un EOF
                // pulito. L'errno va letto **prima** di qualunque altra chiamata (la
                // interpolazione stessa può sovrascriverlo) e stampato in chiaro: è l'unico
                // indizio su un evento perso.
                let reason = String(cString: strerror(errno))
                log.error("agent receiver read failed: \(reason, privacy: .public)")
                break
            }
        }
        close(fd)
        deliver(buffer)
    }

    private func deliver(_ data: Data) {
        let decoder = AgentWireCoding.makeDecoder()
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            guard let event = try? decoder.decode(AgentStateEvent.self, from: Data(line)) else {
                log.error("dropped malformed agent event line")
                continue
            }
            onEvent(event)
        }
    }
}
