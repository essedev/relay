import Foundation

/// Il manuale di Relay come **dato**, non come testo: una lista di sezioni fatte di blocchi
/// tipizzati. È la fonte unica di due rese - la guida in-app (`Panels/GuideView`, che disegna i
/// blocchi coi componenti del design system e legge le combo dai binding vivi) e `docs/GUIDE.md`
/// (`GuideMarkdown`, generato da `make guide-md`). Scritto una volta, letto in due posti: due
/// prose parallele divergerebbero al primo cambio di feature, come è successo a `README.it.md`.
///
/// Sta in `WorkspaceModel` perché il contenuto cita `ShortcutAction`: la lista delle scorciatoie
/// non si scrive a mano, si genera dal modello, quindi una nuova azione compare da sola in
/// entrambe le rese. Nessuna dipendenza da AppKit/SwiftUI: il generatore markdown gira da CLI.
///
/// Regola per chi scrive il contenuto: la prosa deve funzionare **in entrambe le rese**. Niente
/// "clicca qui sotto" né riferimenti a cosa c'è a schermo nel pannello, e nessuna combinazione di
/// tasti scritta a mano per un'azione rimappabile (`.action`, non `.fixed`).
public enum Guide {
    /// Le sezioni nell'ordine di lettura: prima il modello (cosa sono workspace, pane e finestre),
    /// poi come si tiene in ordine la sidebar, poi la parte agente che è il motivo per cui Relay
    /// esiste, infine tastiera, aspetto e manutenzione.
    public static var sections: [GuideSection] {
        [
            workspacesSection,
            panesAndWindowsSection,
            sidebarSection,
            agentStateSection,
            dashboardSection,
            namingSection,
            keyboardSection,
            appearanceSection,
            housekeepingSection,
        ]
    }

    public static func section(id: String) -> GuideSection? {
        sections.first { $0.id == id }
    }
}

/// Una sezione della guida: una voce nella lista a sinistra del pannello, un `##` nel markdown.
public struct GuideSection: Identifiable, Sendable {
    /// Slug stabile: selezione nel pannello e ancora nel markdown. Non cambiarlo a cuor leggero,
    /// è quello che finisce nei link.
    public let id: String
    public let title: String
    /// SF Symbol per la riga nella lista (ignorato dal markdown).
    public let symbol: String
    /// Una riga sotto il titolo: cosa copre la sezione.
    public let summary: String
    public let blocks: [GuideBlock]

    public init(
        id: String,
        title: String,
        symbol: String,
        summary: String,
        blocks: [GuideBlock]
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.summary = summary
        self.blocks = blocks
    }

    /// Tutto il testo della sezione, minuscolo: è la ricerca del pannello, senza una lista di
    /// keyword da tenere allineata a mano (quella di `SettingsView` la si aggiorna, questa no).
    public var searchText: String {
        var parts = [title, summary]
        for block in blocks {
            parts.append(contentsOf: block.searchableStrings)
        }
        return parts.joined(separator: " ").lowercased()
    }

    public func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        // Tutte le parole devono comparire: "drag tab" non deve pescare ogni sezione che dice drag.
        return trimmed.split(separator: " ").allSatisfy { searchText.contains($0) }
    }
}

/// I blocchi che compongono una sezione. Deliberatamente pochi: ogni caso in più è un caso in più
/// da rendere in due posti.
public enum GuideBlock: Sendable {
    /// Prosa. Il primo paragrafo di una sezione dice cosa fa la feature, non come è fatta.
    case paragraph(String)
    /// Elenco di voci con titolo: la forma giusta per "queste sono le cose che puoi fare".
    case topics([GuideTopic])
    /// Passi in ordine, quando la sequenza conta (setup).
    case steps([String])
    /// Tabella di scorciatoie: le rimappabili escono dai binding, le fisse sono scritte.
    case shortcuts([GuideShortcut])
    /// **Tutte** le azioni rimappabili, raggruppate per `ShortcutGroup`. Generato, non scritto:
    /// aggiungere un `ShortcutAction` lo fa comparire nella guida e in `docs/GUIDE.md` senza che
    /// nessuno se ne ricordi. Le glosse opzionali stanno in `Guide.shortcutNotes`.
    case allShortcuts
    /// Comando da terminale, con una riga di spiegazione.
    case command(String, note: String)
    /// Chiusa in tono minore: un limite noto, un default, una precisazione.
    case note(String)

    var searchableStrings: [String] {
        switch self {
        case let .paragraph(text), let .note(text):
            [text]
        case let .topics(topics):
            topics.flatMap { [$0.title, $0.detail] }
        case let .steps(steps):
            steps
        case let .shortcuts(shortcuts):
            shortcuts.flatMap(\.searchableStrings)
        case .allShortcuts:
            ShortcutAction.allCases.flatMap { [$0.label, Guide.shortcutNotes[$0] ?? ""] }
        case let .command(command, note):
            [command, note]
        }
    }
}

/// Le azioni rimappabili raggruppate per `ShortcutGroup`, nell'ordine dichiarato dal modello:
/// la forma in cui `.allShortcuts` va reso, uguale per il pannello e per il markdown.
public extension Guide {
    static var shortcutGroups: [(group: ShortcutGroup, actions: [ShortcutAction])] {
        ShortcutGroup.allCases.compactMap { group in
            let actions = ShortcutAction.allCases.filter { $0.group == group }
            return actions.isEmpty ? nil : (group, actions)
        }
    }
}

/// Voce di un elenco: simbolo, titolo, spiegazione.
public struct GuideTopic: Identifiable, Sendable {
    public var id: String {
        title
    }

    public let symbol: String
    public let title: String
    public let detail: String

    public init(_ symbol: String, _ title: String, _ detail: String) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

/// Una riga della tabella scorciatoie. `.action` è il caso normale: la combinazione la conosce
/// `AppSettings`, quindi se l'utente la rimappa la guida mostra la sua. `.fixed` è per i tasti che
/// non sono azioni rimappabili (select-by-number, comandi di sistema).
public enum GuideShortcut: Sendable {
    case action(ShortcutAction, String)
    case fixed(keys: String, title: String, detail: String)

    public var detail: String {
        switch self {
        case let .action(_, detail), let .fixed(_, _, detail): detail
        }
    }

    /// Il titolo della riga: per le azioni è la label del modello, così non si duplica.
    public var title: String {
        switch self {
        case let .action(action, _): action.label
        case let .fixed(_, title, _): title
        }
    }

    var searchableStrings: [String] {
        switch self {
        case let .action(action, detail): [action.rawValue, detail]
        case let .fixed(keys, title, detail): [keys, title, detail]
        }
    }
}
