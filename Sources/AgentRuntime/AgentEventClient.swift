import AgentProtocol
import Foundation

/// Client del receiver: si connette al socket, scrive una JSON line, chiude. Fail-safe per design:
/// se il receiver non c'è (app non in esecuzione) `send` lancia, e il chiamante (CLI/hook) ignora
/// l'errore così non rompe Claude.
public enum AgentEventClient {
    /// Pause fra un tentativo di consegna e il successivo (millisecondi). Sotto raffica il
    /// backlog del receiver può essere pieno per una frazione di millisecondo: senza ritentare
    /// l'evento è perso per sempre, e nessuno se ne accorge perché il chiamante ingoia l'errore.
    /// Il processo hook è effimero, quindi 40 ms nel caso peggiore non li nota nessuno.
    /// Si ritenta **solo** sugli errori transitori: quando Relay non è in esecuzione la `connect`
    /// fallisce con `ENOENT` e si esce subito, senza far aspettare ogni hook della macchina.
    private static let retryDelaysMs: [UInt32] = [10, 30]

    /// `true` se un receiver vivo ascolta sul socket (una `connect` effimera riesce). Il guard
    /// single-instance lo usa per rilevare un'altra istanza Relay che possiede questa runtime dir,
    /// anche senza bundle id (lancio dev). Un socket stantio (owner morto) o assente -> `false`.
    public static func isReceiverReachable(at path: String = RelayRuntimePaths.socketPath) -> Bool {
        UnixSocket.isListening(path: path)
    }

    public static func send(
        _ event: AgentStateEvent,
        to path: String = RelayRuntimePaths.socketPath
    ) throws {
        var line = try AgentWireCoding.makeEncoder().encode(event)
        line.append(UInt8(ascii: "\n"))

        var lastError: any Error = UnixSocketError.connectFailed(ECONNREFUSED)
        for attempt in 0 ... retryDelaysMs.count {
            do {
                try deliver(line, to: path)
                return
            } catch {
                lastError = error
                guard let socketError = error as? UnixSocketError,
                      isTransient(socketError),
                      attempt < retryDelaysMs.count else { throw error }
                usleep(retryDelaysMs[attempt] * 1000)
            }
        }
        throw lastError
    }

    /// Un solo tentativo: connect, scrittura della linea, chiusura.
    private static func deliver(_ line: Data, to path: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.socketFailed(errno) }
        defer { close(fd) }

        // Senza questo, se il receiver sparisce tra la connect e la write (Relay chiude/crasha
        // mentre un hook Stop/SessionEnd sta scrivendo), la write su pipe rotta alza SIGPIPE, che
        // per default termina il processo hook: il contratto fail-safe (un problema di Relay non
        // rompe Claude) salterebbe. Con SO_NOSIGPIPE l'errore torna come EPIPE dalla write.
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = try UnixSocket.address(path: path)
        let connectResult = UnixSocket.withSockAddr(&addr) { connect(fd, $0, $1) }
        guard connectResult == 0 else { throw UnixSocketError.connectFailed(errno) }

        try line.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var sent = 0
            while sent < line.count {
                let n = write(fd, base + sent, line.count - sent)
                if n <= 0 { throw UnixSocketError.writeFailed(errno) }
                sent += n
            }
        }
    }

    /// L'errore è una coda piena o un'interruzione, non una destinazione che non esiste: un altro
    /// tentativo ha senso. Una write a metà e poi ripetuta può lasciare al receiver una linea
    /// monca, che il decode scarta; il duplicato che segue è innocuo, perché lo stesso evento
    /// applicato due volte è idempotente (stesso stato, stesso timestamp).
    static func isTransient(_ error: UnixSocketError) -> Bool {
        switch error {
        case let .connectFailed(code):
            code == ECONNREFUSED || code == EAGAIN || code == EINTR || code == ETIMEDOUT
        case let .writeFailed(code):
            code == EPIPE || code == EAGAIN || code == EINTR || code == ECONNRESET
        case let .socketFailed(code):
            code == EMFILE || code == ENFILE
        default:
            false
        }
    }
}
