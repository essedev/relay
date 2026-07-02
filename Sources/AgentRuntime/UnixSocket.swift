import Foundation

/// Errori del trasporto Unix domain socket. `Equatable` per i test.
public enum UnixSocketError: Error, Equatable {
    case pathTooLong(String)
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case writeFailed(Int32)
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
}
