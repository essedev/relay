import os

/// Logging centralizzato. Subsystem unico dell'app, category = modulo chiamante.
/// Regola (CONVENTIONS): mai `print`, mai segreti o payload utente nei log.
public enum RelayLog {
    public static let subsystem = "dev.relay.app"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
