import Foundation

/// Segnali grezzi da cui derivare il nome di un workspace: la working directory corrente, il
/// comando in foreground, l'eventuale sessione agente e il titolo della sua chat. Tutti opzionali;
/// `WorkspaceNaming.prompt` decide se bastano a chiedere un nome.
public struct WorkspaceNameSignals: Equatable, Sendable {
    public var directory: String?
    public var command: String?
    public var agent: String?
    /// Titolo della chat dell'agente (il titolo OSC che Claude Code imposta, già ripulito da
    /// `WorkspaceNaming.chatTitle`). Dice di cosa si parla, non in che progetto: per questo nel
    /// prompt affianca la cartella invece di sostituirla.
    public var chatTitle: String?

    public init(
        directory: String? = nil,
        command: String? = nil,
        agent: String? = nil,
        chatTitle: String? = nil
    ) {
        self.directory = directory
        self.command = command
        self.agent = agent
        self.chatTitle = chatTitle
    }
}

/// Quel che si osserva di **una** tab ai fini della nomina: lo stato agente (dal model) più ciò che
/// si riesce a leggere dalla sua surface (comando in foreground, cwd viva). Tutto opzionale: una
/// tab mai realizzata - restore dal layout, sfratto della LRU - non ha surface da interrogare.
public struct TabNamingSignal: Equatable, Sendable {
    /// La tab è a schermo nel suo pane: a parità di forza del segnale è quella che stai guardando.
    public var isVisible: Bool
    public var agent: String?
    public var command: String?
    public var directory: String?
    public var chatTitle: String?

    public init(
        isVisible: Bool = false,
        agent: String? = nil,
        command: String? = nil,
        directory: String? = nil,
        chatTitle: String? = nil
    ) {
        self.isVisible = isVisible
        self.agent = agent
        self.command = command
        self.directory = directory
        self.chatTitle = chatTitle
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

    /// Titoli che un agente mostra prima di avere un argomento (`✳ Claude Code` all'avvio) e il
    /// placeholder di una tab senza OSC: non dicono di cosa parla la chat.
    private static let genericChatTitles: Set<String> = [
        "shell", "claude", "claude code", "codex", "codex cli",
    ]

    /// Tetto del titolo di chat spedito al modello: i titoli di Claude sono corti, ma il titolo OSC
    /// lo scrive chiunque.
    static let maxChatTitleLength = 80

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

    /// Il titolo della chat da un titolo di terminale (OSC 0/2) di una tab con una sessione agente.
    /// `nil` se non dice niente sull'argomento.
    ///
    /// Claude Code scrive `✳ <argomento>` da fermo e un glifo che gira (`◐`, `⠂`) mentre lavora: il
    /// glifo in testa va via. Prima che la chat abbia un argomento il titolo è `✳ Claude Code`
    /// (generico), e prima ancora può essere quello della shell: `user@host:path` al prompt o la
    /// riga di comando lanciata. Il glifo è anche la prova che il titolo l'ha scritto l'agente:
    /// quando c'è, il confronto col comando in foreground si salta, o un argomento che comincia
    /// per "Claude" verrebbe scambiato per il comando `claude`.
    public static func chatTitle(fromTerminalTitle raw: String, command: String? = nil) -> String? {
        let scalars = raw.unicodeScalars
        let body = scalars.drop { !CharacterSet.alphanumerics.contains($0) }
        let hadGlyph = body.count < scalars.count
            && !scalars.prefix(scalars.count - body.count).allSatisfy {
                CharacterSet.whitespaces.contains($0)
            }
        let title = String(String.UnicodeScalarView(body))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !title.isEmpty, !genericChatTitles.contains(title.lowercased()),
              !isShellPromptTitle(title) else { return nil }
        if !hadGlyph, let command, echoesCommand(title, command: command) { return nil }
        guard title.count > maxChatTitleLength else { return title }
        return truncateAtWordBoundary(title, limit: maxChatTitleLength)
    }

    /// `user@host:~/path`: il titolo che la shell mette al prompt, non un argomento.
    private static func isShellPromptTitle(_ title: String) -> Bool {
        guard let colon = title.firstIndex(of: ":") else { return false }
        let head = title[..<colon]
        return head.contains("@") && !head.contains(where: \.isWhitespace)
    }

    /// La shell che intitola la tab col comando lanciato (`claude --resume`): stesso eseguibile.
    private static func echoesCommand(_ title: String, command: String) -> Bool {
        let first = { (text: String) in
            text.split(separator: " ").first.map { ($0 as NSString).lastPathComponent.lowercased() }
        }
        return first(title) != nil && first(title) == first(command)
    }

    /// Fonde le osservazioni delle tab di un workspace in un solo set di segnali. Sceglie **una**
    /// tab - la più informativa - e ne prende i segnali interi: mescolare il comando di una tab con
    /// la cwd di un'altra descriverebbe un'attività che non esiste. Guardare tutte le tab e non
    /// solo la selezionata è il punto: la tab in vista è spesso una shell ferma mentre l'agente
    /// gira in quella accanto, ed è il workspace che stiamo nominando, non la tab.
    ///
    /// Forza del segnale: agente attivo > comando in foreground > cwd nota > niente; a parità vince
    /// la tab a schermo, poi l'ordine. La cwd ricade su `workspaceRoot` quando la tab scelta non ne
    /// ha (nessuna surface da interrogare): la cartella del workspace è il contesto minimo che
    /// conosciamo sempre.
    public static func signals(
        from tabs: [TabNamingSignal],
        workspaceRoot: String? = nil
    ) -> WorkspaceNameSignals {
        let best = tabs.enumerated().max { lhs, rhs in
            // L'indice negato tiene l'ordine deterministico: a parità vince la tab che viene prima.
            (strength(lhs.element), lhs.element.isVisible ? 1 : 0, -lhs.offset)
                < (strength(rhs.element), rhs.element.isVisible ? 1 : 0, -rhs.offset)
        }?.element
        return WorkspaceNameSignals(
            directory: best?.directory ?? workspaceRoot,
            command: best?.command,
            agent: best?.agent,
            chatTitle: best?.chatTitle
        )
    }

    /// Quanto una tab è informativa per la nomina. Ordine fisso, non pesi da tarare: una sessione
    /// agente dice di cosa ti stai occupando, un comando dice cosa stai facendo, la cwd solo dove
    /// sei.
    private static func strength(_ tab: TabNamingSignal) -> Int {
        if tab.agent != nil { return 3 }
        if tab.command != nil { return 2 }
        if tab.directory != nil { return 1 }
        return 0
    }

    /// Costruisce i messaggi (system + user) per la chat completion. `nil` se i segnali non bastano
    /// a nominare qualcosa: nessun comando, nessun titolo di chat **e** directory assente o
    /// coincidente con la home (un workspace fermo in home senza attività non ha un "argomento" da
    /// cui derivare un nome).
    ///
    /// La cartella dice il progetto, la chat dice il task: il prompt chiede di nominare il progetto
    /// e di usare la chat solo quando la cartella è generica o manca. Nominare dalla chat quando la
    /// cartella basta duplicherebbe il sottotitolo della sidebar (che mostra già il titolo della
    /// chat) e legherebbe il workspace all'argomento della prima conversazione.
    ///
    /// `avoiding` è il nome corrente da non ripetere, e lo passa solo il "Regenerate name" manuale:
    /// il prompt è deterministico (`temperature: 0`), quindi a contesto invariato il modello
    /// ridarebbe lo stesso identico nome e l'azione sembrerebbe non aver fatto nulla.
    public static func prompt(
        for signals: WorkspaceNameSignals,
        homePath: String,
        avoiding currentName: String? = nil
    ) -> (system: String, user: String)? {
        let directoryLabel = directoryHint(signals.directory, homePath: homePath)
        let command = signals.command?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCommand = !(command?.isEmpty ?? true)
        let chat = signals.chatTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasChat = !(chat?.isEmpty ?? true)
        guard directoryLabel != nil || hasCommand || hasChat else { return nil }

        let system = """
        You name developer terminal workspaces. You get some of: the working directory, the \
        running command, the title of the coding-agent chat in progress. Reply with a short, \
        human-friendly name of 1 to 3 words in Title Case. \
        A specific directory names the project: name the workspace after it. Use the chat title \
        only when the directory is generic (e.g. app, src, backend, tmp) or missing. \
        Ignore version suffixes (e.g. -v2, .1) and file extensions. \
        Reply with ONLY the name: no quotes, no punctuation, no explanation.
        """
        var lines: [String] = []
        if let directoryLabel { lines.append("Directory: \(directoryLabel)") }
        if hasCommand, let command { lines.append("Command: \(command)") }
        if hasChat, let chat { lines.append("Chat: \(chat)") }
        let agent = signals.agent?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let agent, !agent.isEmpty { lines.append("Agent: \(agent)") }
        let avoid = currentName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let avoid, !avoid.isEmpty {
            lines.append("Already named \"\(avoid)\": propose a different name for the same thing.")
        }
        return (system: system, user: lines.joined(separator: "\n"))
    }

    // MARK: - Nomi senza modello

    /// Nomi derivabili dai segnali **senza chiedere niente a nessuno**, in ordine di preferenza:
    /// prima la cartella (identifica il progetto e non cambia sotto i piedi), poi il titolo della
    /// chat, poi il comando (dice cosa stai facendo, ma passa). Lista vuota = gli stessi segnali
    /// per cui `prompt` torna `nil`, cioè non c'è niente da cui nominare.
    ///
    /// La chat viene prima del comando perché in una tab con un agente il comando è l'agente
    /// stesso (`claude` -> "Claude"), che non distingue un workspace dall'altro. Una regola non sa
    /// dire se una cartella è generica, quindi qui la chat non scavalca mai la cartella: conta
    /// quando la cartella non c'è, cioè sei in home.
    ///
    /// Esiste perché al modello arrivano tre righe scarne (`Directory: hub`, `Command: brew
    /// update`, `Agent: claude`): su un input così povero il grosso del lavoro è meccanico -
    /// separatori, Title Case, suffissi di versione, estensioni. Farlo qui rende la nomina
    /// automatica **il default per tutti**, senza API key, senza rete e senza attesa; il modello
    /// resta per quello che una regola non sa fare (espandere sigle, fondere cartella e comando in
    /// una frase) e per dare un nome *diverso* quando lo si rigenera.
    public static func localNames(for signals: WorkspaceNameSignals, homePath: String) -> [String] {
        var candidates: [String] = []
        if let directory = directoryHint(signals.directory, homePath: homePath) {
            candidates.append(titleCased(directory, maxWords: 3))
        }
        if let chat = signals.chatTitle {
            candidates.append(firstClause(chat))
        }
        if let command = signals.command {
            candidates.append(titleCased(commandWords(command), maxWords: 2))
        }
        // `sanitize` è la stessa porta d'uscita della risposta del modello: stesso cap, stessi
        // generici rifiutati, così i due percorsi non producono nomi di qualità diversa.
        var seen: Set<String> = []
        return candidates
            .compactMap(sanitize)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// La prima frase di un titolo di chat, senza Title Case: è già prosa scritta da qualcuno, e
    /// "Architettura modelli Anthropic, OpenAI e cinesi" -> "Architettura modelli Anthropic" (poi
    /// `sanitize` taglia al tetto sul confine di parola).
    private static func firstClause(_ title: String) -> String {
        let clause = title.split(whereSeparator: { ",;|".contains($0) }).first.map(String.init)
        return (clause ?? title).trimmingCharacters(in: .whitespaces)
    }

    /// Parole utili di una riga di comando: niente flag, niente sottocomandi-guscio (`npm **run**
    /// dev` -> "npm dev"), estensioni via (`vim README.md` -> "vim README").
    private static func commandWords(_ command: String) -> String {
        let noise: Set = ["run", "exec", "x", "--"]
        return command
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.hasPrefix("-") && !noise.contains($0.lowercased()) }
            .map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Title Case da uno slug: separa su `-`/`_`/`.`/spazio e sui confini camelCase, butta i
    /// suffissi di versione (`v2`, `1.0`), tiene le parole già maiuscole come sono (`API`,
    /// `README`)
    /// e si ferma a `maxWords`.
    private static func titleCased(_ raw: String, maxWords: Int) -> String {
        let separators = CharacterSet(charactersIn: "-_. ")
        let words = splitCamelCase(raw)
            .components(separatedBy: separators)
            .filter { !$0.isEmpty && !isVersionSuffix($0) }
            .prefix(maxWords)
            .map { word -> String in
                // Una parola che ha già maiuscole sue (API, README, iOS) sa come si scrive.
                word.contains(where: \.isUppercase) ? word : word.capitalized
            }
        return words.joined(separator: " ")
    }

    /// `yellowHub` -> `yellow Hub`: il camelCase è un separatore di parole quanto un trattino.
    private static func splitCamelCase(_ raw: String) -> String {
        var out = ""
        var previous: Character?
        for character in raw {
            if let previous, previous.isLowercase || previous.isNumber, character.isUppercase {
                out.append(" ")
            }
            out.append(character)
            previous = character
        }
        return out
    }

    /// `v2`, `2`, `1.0`: coda di versione, non una parola del nome.
    private static func isVersionSuffix(_ word: String) -> Bool {
        var digits = Substring(word)
        if digits.first == "v" || digits.first == "V" { digits = digits.dropFirst() }
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
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
