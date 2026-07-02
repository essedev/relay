import AgentProtocol
import Foundation

/// Client del receiver: si connette al socket, scrive una JSON line, chiude. Fail-safe per design:
/// se il receiver non c'è (app non in esecuzione) `send` lancia, e il chiamante (CLI/hook) ignora
/// l'errore così non rompe Claude.
public enum AgentEventClient {
    public static func send(
        _ event: AgentStateEvent,
        to path: String = RelayRuntimePaths.socketPath
    ) throws {
        var line = try AgentWireCoding.makeEncoder().encode(event)
        line.append(UInt8(ascii: "\n"))

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.socketFailed(errno) }
        defer { close(fd) }

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
}
