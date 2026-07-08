import Foundation

/// Segnali grezzi da cui derivare il nome di un workspace: la working directory corrente, il
/// comando in foreground, l'eventuale agente attivo. Tutti opzionali; `WorkspaceNaming.prompt`
/// decide se bastano a chiedere un nome.
public struct WorkspaceNameSignals: Equatable, Sendable {
    public var directory: String?
    public var command: String?
    public var agent: String?

    public init(directory: String? = nil, command: String? = nil, agent: String? = nil) {
        self.directory = directory
        self.command = command
        self.agent = agent
    }
}

/// Logica pura per la nomina automatica dei workspace via LLM (endpoint OpenAI-compatible):
/// estrazione del comando dall'argv, costruzione del prompt e sanitizzazione della risposta.
/// Niente I/O: la rete vive nel composition root (`NamingController`), qui solo trasformazioni
/// testabili (come `ReleaseCheck` per il check aggiornamenti).
public enum WorkspaceNaming {
    /// Tetto di lunghezza del nome generato (caratteri). Nomi più lunghi si troncano al confine di
    /// parola in `sanitize`.
    public static let maxNameLength = 28

    /// Shell interattive: come foreground non sono un "comando" da cui nominare (sei al prompt di
    /// una shell annidata). Allineata alla safe-list dell'engine (`SwiftTermEngine`).
    private static let shellNames: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "login", "tcsh", "csh", "-zsh", "-bash", "-fish",
    ]

    /// Nomi da rifiutare come output del modello: generici o eco della domanda, non identificano
    /// niente. Confronto case-insensitive dopo la pulizia.
    private static let rejectedNames: Set<String> = [
        "workspace", "untitled", "terminal", "shell", "project", "home", "directory",
        "folder", "session", "unknown", "name", "prompt", "command",
    ]

    /// Deriva un comando leggibile dall'argv del processo in foreground. `nil` se non c'è argv, se
    /// è
    /// una shell interattiva nuda (sei al prompt), o se resta vuoto. Prende il basename
    /// dell'eseguibile e vi accoda gli argomenti, con un tetto di lunghezza per non spedire argv
    /// chilometriche al modello.
    public static func command(fromArgv argv: [String]?) -> String? {
        guard let argv, let executable = argv.first else { return nil }
        let exe = (executable as NSString).lastPathComponent
        guard !exe.isEmpty else { return nil }
        let args = Array(argv.dropFirst())
        // Shell interattiva nuda (nessun argomento): sei al prompt, non un comando da nominare.
        if shellNames.contains(exe), args.isEmpty { return nil }
        let joined = ([exe] + args).joined(separator: " ")
        let capped = joined.count > 80 ? String(joined.prefix(80)) : joined
        let trimmed = capped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Costruisce i messaggi (system + user) per la chat completion. `nil` se i segnali non bastano
    /// a nominare qualcosa: nessun comando **e** directory assente o coincidente con la home (un
    /// workspace fermo in home senza attività non ha un "argomento" da cui derivare un nome).
    public static func prompt(
        for signals: WorkspaceNameSignals,
        homePath: String
    ) -> (system: String, user: String)? {
        let directoryLabel = directoryHint(signals.directory, homePath: homePath)
        let command = signals.command?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCommand = !(command?.isEmpty ?? true)
        guard directoryLabel != nil || hasCommand else { return nil }

        let system = """
        You name developer terminal workspaces. Given a working directory and/or a running \
        command, reply with a short, human-friendly name of 1 to 3 words in Title Case. \
        Ignore version suffixes (e.g. -v2, .1) and file extensions. \
        Reply with ONLY the name: no quotes, no punctuation, no explanation.
        """
        var lines: [String] = []
        if let directoryLabel { lines.append("Directory: \(directoryLabel)") }
        if hasCommand, let command { lines.append("Command: \(command)") }
        let agent = signals.agent?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let agent, !agent.isEmpty { lines.append("Agent: \(agent)") }
        return (system: system, user: lines.joined(separator: "\n"))
    }

    /// Etichetta della directory per il prompt: basename della cwd, `nil` se assente o coincide con
    /// la home (una cwd = home non dice niente sul progetto).
    private static func directoryHint(_ directory: String?, homePath: String) -> String? {
        guard let directory else { return nil }
        let normalized = normalizePath(directory)
        guard !normalized.isEmpty, normalized != normalizePath(homePath) else { return nil }
        let base = (normalized as NSString).lastPathComponent
        return base.isEmpty || base == "/" ? nil : base
    }

    private static func normalizePath(_ path: String) -> String {
        var p = path
        while p.count > 1, p.hasSuffix("/") {
            p.removeLast()
        }
        return p
    }

    /// Ripulisce la risposta grezza del modello in un nome usabile, o `nil` se inservibile (vuoto,
    /// generico, eco della domanda). Prende la prima riga non vuota, toglie
    /// virgolette/backtick/markdown, collassa gli spazi, taglia la punteggiatura ai bordi e limita
    /// la lunghezza al confine di parola.
    public static func sanitize(_ raw: String) -> String? {
        // Prima riga non vuota: i modelli a volte aggiungono spiegazioni sotto.
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        // Toglie delimitatori/markdown attorno, poi collassa gli spazi interni.
        let strippable = CharacterSet(charactersIn: "\"'`*#_[]().:;,").union(.whitespaces)
        var name = firstLine.trimmingCharacters(in: strippable)
        name = name.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        guard !name.isEmpty else { return nil }
        if name.count > maxNameLength {
            name = truncateAtWordBoundary(name, limit: maxNameLength)
        }
        guard !name.isEmpty, !rejectedNames.contains(name.lowercased()) else { return nil }
        return name
    }

    /// Tronca a `limit` caratteri, preferendo l'ultimo confine di parola se cade oltre metà del
    /// tetto (altrimenti taglio netto: una singola parola lunghissima).
    private static func truncateAtWordBoundary(_ name: String, limit: Int) -> String {
        let hard = String(name.prefix(limit))
        let lastSpace = hard.lastIndex(of: " ")
        if let lastSpace, hard.distance(from: hard.startIndex, to: lastSpace) >= limit / 2 {
            return String(hard[..<lastSpace]).trimmingCharacters(in: .whitespaces)
        }
        return hard.trimmingCharacters(in: .whitespaces)
    }
}
