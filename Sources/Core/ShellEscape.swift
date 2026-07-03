import Foundation

/// Escaping di un percorso per l'input del terminale (drop di file): backslash davanti a ogni
/// carattere non "sicuro" (spazi, parentesi, apici, ...), come fanno Terminal.app/iTerm. Così il
/// path trascinato viene inserito pronto all'uso, sia per la shell sia per Claude Code.
public enum ShellEscape {
    /// Caratteri che non vanno escaped: lettere, cifre e la punteggiatura innocua dei path.
    private static let safe = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._-+,:@%"
    )

    /// Un singolo path, con backslash davanti ai caratteri non sicuri.
    public static func path(_ path: String) -> String {
        var result = ""
        for character in path {
            if !safe.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    /// Più path insieme (drop multiplo): ognuno escaped, separati da spazio, con uno spazio finale
    /// per continuare a digitare. Vuoto -> stringa vuota.
    public static func joined(_ paths: [String]) -> String {
        guard !paths.isEmpty else { return "" }
        return paths.map(path).joined(separator: " ") + " "
    }
}
