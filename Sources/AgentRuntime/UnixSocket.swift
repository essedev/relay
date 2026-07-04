import Foundation

/// Errori del trasporto Unix domain socket. `Equatable` per i test.
public enum UnixSocketError: Error, Equatable {
    case pathTooLong(String)
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case writeFailed(Int32)
    /// Un receiver vivo possiede già il socket a questo path: non lo calpestiamo (no-stomp).
    case addressInUse
}

/// Helper condivisi tra receiver (server) e client per costruire l'indirizzo del socket. Tiene la
/// gestione a basso livello di `sockaddr_un` in un solo posto.
enum UnixSocket {
    /// Riempie un `sockaddr_un` col path dato. Lancia se il path eccede `sun_path` (~104 byte).
    static func address(path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { throw UnixSocketError.pathTooLong(path) }
        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                path.withCString { src in _ = strncpy(dst, src, capacity - 1) }
            }
        }
        return addr
    }

    /// Lunghezza dell'indirizzo passata a `bind`/`connect`.
    static var addressLength: socklen_t {
        socklen_t(MemoryLayout<sockaddr_un>.size)
    }

    /// Esegue `body` con l'indirizzo ricast a `sockaddr` (come vogliono `bind`/`connect`).
    static func withSockAddr<R>(
        _ addr: inout sockaddr_un,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> R
    ) -> R {
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, addressLength) }
        }
    }

    /// `true` se un listener vivo accetta connessioni su `path`. Discrimina tre casi con una
    /// `connect` effimera: successo -> owner vivo; `ECONNREFUSED` -> socket file stantio (owner
    /// morto); `ENOENT` -> assente. Usato per non calpestare il socket di un'istanza viva
    /// (no-stomp nel receiver) e per il guard single-instance basato sul path (App.main).
    static func isListening(path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard var addr = try? address(path: path) else { return false }
        return withSockAddr(&addr) { connect(fd, $0, $1) } == 0
    }
}
