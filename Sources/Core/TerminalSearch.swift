import Foundation

/// Opzioni di ricerca nel terminale, condivise dalla UI (find bar), dal motore di navigazione
/// (SwiftTerm) e dall'evidenziazione dei match nella viewport. Pure, così viaggiano dovunque.
public struct TerminalSearchOptions: Equatable, Sendable {
    /// La ricerca distingue maiuscole/minuscole.
    public var caseSensitive: Bool
    /// Il match deve essere delimitato da confini di parola (non incastrato dentro un'altra
    /// parola).
    public var wholeWord: Bool
    /// Il termine è una regular expression invece di testo letterale.
    public var regex: Bool

    public init(caseSensitive: Bool = false, wholeWord: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.regex = regex
    }
}

/// Motore di matching **puro** su una singola stringa: date `text`, `term` e le opzioni, trova le
/// occorrenze e ne ritorna i range in **indici di Character** (non `String.Index` né byte). Gli
/// indici di Character sono l'unità giusta per il terminale, dove poi si mappano alle colonne-cella
/// (una emoji è un Character ma occupa due celle): il chiamante che disegna l'evidenziazione
/// traduce
/// indice-carattere -> colonna con le larghezze reali delle celle.
///
/// Confine di parola: un "carattere di parola" è alfanumerico o `_` (definizione POSIX-like),
/// coerente
/// con l'aspettativa comune di "whole word". La navigazione (SwiftTerm) usa un set proprio, quindi
/// in
/// modalità `wholeWord` i due potrebbero divergere su punteggiatura esotica: l'evidenziazione è un
/// aiuto visivo, il contatore resta autorevole.
public enum TerminalSearchMatcher {
    /// Occorrenze di `term` in `text`, come range di indici di Character `[start, end)`, in ordine
    /// e
    /// **non sovrapposte** (dopo un match si riparte dalla sua fine). `term` vuoto o regex non
    /// valida
    /// -> nessun match. Un match a larghezza zero (es. regex `a*` su testo vuoto tra caratteri)
    /// viene
    /// saltato avanzando di uno per non ciclare.
    public static func matches(
        in text: String,
        term: String,
        options: TerminalSearchOptions
    ) -> [Range<Int>] {
        guard !term.isEmpty, !text.isEmpty else { return [] }
        if options.regex {
            return regexMatches(in: text, pattern: term, options: options)
        }
        return literalMatches(in: text, term: term, options: options)
    }

    // MARK: - Letterale

    private static func literalMatches(
        in text: String,
        term: String,
        options: TerminalSearchOptions
    ) -> [Range<Int>] {
        let haystack = Array(text)
        let needle = Array(term)
        guard needle.count <= haystack.count else { return [] }

        let normalizedHaystack = options.caseSensitive ? haystack : haystack.map(lowercased)
        let normalizedNeedle = options.caseSensitive ? needle : needle.map(lowercased)

        var results: [Range<Int>] = []
        var index = 0
        let lastStart = haystack.count - needle.count
        while index <= lastStart {
            let isMatch = matchesAt(normalizedHaystack, needle: normalizedNeedle, at: index)
                && (!options.wholeWord || isWholeWord(haystack, start: index, length: needle.count))
            if isMatch {
                results.append(index ..< (index + needle.count))
                index += needle.count // non sovrapposte
            } else {
                index += 1
            }
        }
        return results
    }

    private static func matchesAt(
        _ haystack: [Character],
        needle: [Character],
        at start: Int
    ) -> Bool {
        for offset in needle.indices where haystack[start + offset] != needle[offset] {
            return false
        }
        return true
    }

    // MARK: - Regex

    private static func regexMatches(
        in text: String,
        pattern: String,
        options: TerminalSearchOptions
    ) -> [Range<Int>] {
        var regexOptions: NSRegularExpression.Options = []
        if !options.caseSensitive { regexOptions.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
            return []
        }
        // NSRegularExpression lavora su UTF-16: si converte l'offset UTF-16 in indice di Character.
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        let characters = Array(text)
        // Mappa offset UTF-16 -> indice di Character (una volta, poi lookup).
        var utf16ToCharacter = [Int](repeating: 0, count: nsText.length + 1)
        var charIndex = 0
        var utf16Index = 0
        for character in characters {
            let width = String(character).utf16.count
            for step in 0 ..< width {
                utf16ToCharacter[utf16Index + step] = charIndex
            }
            utf16Index += width
            charIndex += 1
        }
        utf16ToCharacter[nsText.length] = charIndex

        var results: [Range<Int>] = []
        regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match, match.range.length > 0 else { return }
            let startChar = utf16ToCharacter[match.range.location]
            let endChar = utf16ToCharacter[match.range.location + match.range.length]
            if endChar > startChar {
                results.append(startChar ..< endChar)
            }
        }
        return results
    }

    // MARK: - Helper

    private static func lowercased(_ character: Character) -> Character {
        let lower = character.lowercased()
        return lower.count == 1 ? lower[lower.startIndex] : character
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func isWholeWord(_ haystack: [Character], start: Int, length: Int) -> Bool {
        let before = start - 1
        let after = start + length
        let leftOk = before < 0 || !isWordCharacter(haystack[before])
        let rightOk = after >= haystack.count || !isWordCharacter(haystack[after])
        return leftOk && rightOk
    }
}
