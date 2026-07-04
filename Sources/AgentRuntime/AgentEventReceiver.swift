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

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    public init(
        path: String = RelayRuntimePaths.socketPath,
        onEvent: @escaping @Sendable (AgentStateEvent) -> Void
    ) {
        self.path = path
        self.onEvent = onEvent
    }

    /// Avvia l'ascolto. Rimuove un socket file stantio con lo stesso path.
    public func start() throws {
        try queue.sync { try openListeningSocket() }
    }

    /// Ferma l'ascolto e rimuove il socket file. Idempotente.
    public func stop() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if listenFD >= 0 {
                close(listenFD)
                listenFD = -1
            }
            unlink(path)
        }
    }

    // MARK: - Private (invocati su `queue`)

    private func openListeningSocket() throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.socketFailed(errno) }

        var addr = try UnixSocket.address(path: path)
        unlink(path) // rimuovi un socket stantio prima di bind
        let bindResult = UnixSocket.withSockAddr(&addr) { bind(fd, $0, $1) }
        guard bindResult == 0 else {
            close(fd)
            throw UnixSocketError.bindFailed(errno)
        }
        guard listen(fd, 16) == 0 else {
            close(fd)
            throw UnixSocketError.listenFailed(errno)
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        acceptSource = source
        source.resume()
        log.info("agent receiver listening")
    }

    private func acceptConnection() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }
        // Connessioni effimere (una linea e chiudi): leggo fino a EOF fuori dalla accept queue.
        readQueue.async { [weak self] in self?.drain(clientFD) }
    }

    private func drain(_ fd: Int32) {
        var buffer = Data()
        let chunkSize = 4096
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let n = read(fd, &chunk, chunkSize)
            if n > 0 {
                buffer.append(contentsOf: chunk[0 ..< n])
            } else {
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
