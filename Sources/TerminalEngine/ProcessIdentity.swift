import Darwin
import Foundation

/// Identità stabile di un processo: il pid **più** il suo istante di avvio. Il pid da solo viene
/// riciclato (su macOS lo spazio gira in mezz'ora su una macchina al lavoro, vedi
/// `PtySessionTeardown`), la coppia no: è ciò che permette di segnalare un processo visto in un
/// altro momento, o da un'altra run, senza colpire chi ne ha ereditato il numero.
public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: pid_t
    /// Istante di avvio in microsecondi, come lo dà `proc_pidinfo`. Resta lo stesso attraverso
    /// `exec`: la shell fotografata subito dopo il fork e lo stesso processo diventato zsh
    /// coincidono.
    public let startedAt: UInt64

    public init(pid: pid_t, startedAt: UInt64) {
        self.pid = pid
        self.startedAt = startedAt
    }

    /// L'identità attuale di un pid, `nil` se non esiste o non è leggibile.
    public static func of(_ pid: pid_t) -> ProcessIdentity? {
        PtySessionTeardown.startedAt(pid).map { ProcessIdentity(pid: pid, startedAt: $0) }
    }

    /// Questo processo.
    public static var current: ProcessIdentity? {
        of(getpid())
    }

    /// `true` se il pid è ancora vivo **ed è lo stesso processo**.
    public var isAlive: Bool {
        Self.of(pid) == self
    }
}
