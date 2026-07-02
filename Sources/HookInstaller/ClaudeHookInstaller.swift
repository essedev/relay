import Foundation

public enum HookInstallerError: Error {
    case notImplemented
}

/// Installa/rimuove gli hook Claude in ~/.claude/settings.json in modo idempotente, con backup
/// e validazione JSON, senza rompere Otty o hook utente. Implementazione in Fase 4.
public struct ClaudeHookInstaller {
    public init() {}

    public func status() -> Bool {
        false
    }

    public func setup() throws {
        throw HookInstallerError.notImplemented
    }

    public func uninstall() throws {
        throw HookInstallerError.notImplemented
    }
}
