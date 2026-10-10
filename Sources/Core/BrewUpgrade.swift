import Foundation

/// Come si legge l'esito dell'aggiornamento via Homebrew lanciato dalla pill: logica pura, il
/// processo `brew` lo esegue `BrewUpgrader` in RelayApp. Due fonti di verità: l'exit status e
/// l'output di brew dicono se il comando è andato, la versione del bundle **sul disco** dice se
/// la copia di Relay in esecuzione è stata davvero sostituita.
public enum BrewUpgrade {
    /// Il cask nel tap `essedev/relay`.
    public static let cask = "relay-terminal"

    /// Il comando che la pill esegue, mostrato anche da copiare quando qualcosa non va.
    public static let command = "brew update && brew upgrade --cask \(cask)"

    /// Righe di output di brew riportate nel messaggio d'errore: le ultime dicono il perché.
    static let tailLines = 3

    /// Esito dopo che entrambi i comandi brew sono usciti con 0.
    public enum Verification: Equatable, Sendable {
        /// Il bundle sul disco ha la versione attesa (o una più nuova): basta riavviare.
        case installed
        /// brew è andato, ma il bundle da cui gira Relay è rimasto alla versione vecchia: Relay
        /// non è quello installato dal cask (dmg trascinato altrove, copia di sviluppo).
        case notReplaced(onDisk: String?)
    }

    /// Confronta la versione letta dall'Info.plist sul disco con quella attesa.
    public static func verify(onDisk: String?, expected: SemanticVersion) -> Verification {
        guard let onDisk, let version = SemanticVersion(onDisk), version >= expected else {
            return .notReplaced(onDisk: onDisk)
        }
        return .installed
    }

    /// Il messaggio per l'utente quando un comando brew esce con un errore.
    public static func failureMessage(output: String) -> String {
        if output.contains("not installed") {
            return "Relay wasn't installed with Homebrew. Install it with "
                + "\u{201C}brew install --cask essedev/relay/\(cask)\u{201D}, or download the "
                + "new version from the release notes."
        }
        let tail = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(tailLines)
        return tail.isEmpty ? "Homebrew stopped with an error." : tail.joined(separator: "\n")
    }

    /// Il messaggio per `Verification.notReplaced`.
    public static func notReplacedMessage(onDisk: String?, bundlePath: String) -> String {
        let found = onDisk.map { " (found \($0))" } ?? ""
        return "Homebrew finished, but the copy of Relay at \(bundlePath) wasn't updated\(found). "
            + "Quit it and open the one in /Applications."
    }
}
