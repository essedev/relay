import Foundation

/// Sceglie, fra le righe a schermo di un terminale, quella che riassume cosa vuole l'agente: la
/// domanda se ti aspetta, l'errore se si è fermato, altrimenti l'ultima riga di contenuto. La usa
/// Home per mostrare la sessione senza aprirla. Puro: le righe le legge l'engine.
public enum TerminalPeek {
    /// Cosa cercare: dipende da perché la sessione è in Home.
    public enum Intent: Sendable {
        case question
        case error
        case latest
    }

    /// Quante righe dal fondo guardare: oltre, è storia, non lo stato attuale.
    static let window = 20

    /// La riga scelta, ripulita dalla cornice dei box e dagli spazi; `nil` se lo schermo non ha
    /// niente di utile.
    public static func excerpt(from lines: [String], intent: Intent) -> String? {
        let content = lines.map(clean).filter { !$0.isEmpty && !isChrome($0) }.suffix(window)
        switch intent {
        case .question:
            return content.last { $0.hasSuffix("?") } ?? content.last
        case .error:
            return content.last { $0.localizedCaseInsensitiveContains("error") } ?? content.last
        case .latest:
            return content.last
        }
    }

    /// Toglie la cornice dei box (bordi e angoli) e gli spazi ai lati.
    static func clean(_ line: String) -> String {
        let frame = CharacterSet(charactersIn: "│┃╭╮╰╯─━┌┐└┘├┤┬┴┼")
        return line.trimmingCharacters(in: frame.union(.whitespaces))
    }

    /// Righe che sono interfaccia, non contenuto: il prompt vuoto e i suggerimenti a piè di
    /// schermo.
    static func isChrome(_ line: String) -> Bool {
        let prompts: Set = [">", "❯", "$", "%", "#"]
        if prompts.contains(line) { return true }
        let hints = ["? for shortcuts", "esc to interrupt", "shift+tab to cycle", "auto-accept"]
        return hints.contains { line.localizedCaseInsensitiveContains($0) }
    }
}
