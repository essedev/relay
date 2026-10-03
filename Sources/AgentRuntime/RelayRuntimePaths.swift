import Foundation

/// Percorsi runtime condivisi tra l'app (receiver) e il CLI (client hook). Un solo posto per il
/// path del socket, così server e client non possono divergere.
public enum RelayRuntimePaths {
    /// Directory runtime di Relay (`~/.relay`).
    public static var runtimeDirectory: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".relay")
    }

    /// Path del Unix domain socket degli eventi agente. Override via `RELAY_SOCKET` (test e
    /// istanze multiple).
    public static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["RELAY_SOCKET"], !override.isEmpty {
            return override
        }
        return (runtimeDirectory as NSString).appendingPathComponent("relay.sock")
    }

    /// Path dello snapshot del layout (persistence). Override via `RELAY_LAYOUT` (test e istanze
    /// multiple).
    public static var layoutPath: String {
        if let override = ProcessInfo.processInfo.environment["RELAY_LAYOUT"], !override.isEmpty {
            return override
        }
        return (runtimeDirectory as NSString).appendingPathComponent("layout.json")
    }

    /// Directory del registro delle sessioni pty (`PtySessionLedger`): un file per run con le shell
    /// che quella run ha aperto, letto al lancio successivo per chiudere gli orfani. Override via
    /// `RELAY_SESSIONS` (test e istanze isolate, come gli screenshot).
    public static var sessionLedgerDirectory: String {
        if let override = ProcessInfo.processInfo.environment["RELAY_SESSIONS"], !override.isEmpty {
            return override
        }
        return (runtimeDirectory as NSString).appendingPathComponent("sessions")
    }

    /// Crea la directory runtime se manca. Idempotente.
    public static func ensureRuntimeDirectory() throws {
        try FileManager.default.createDirectory(
            atPath: runtimeDirectory,
            withIntermediateDirectories: true
        )
    }
}
