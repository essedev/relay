import Foundation

/// Combinazione di tasti: un tasto base + modificatori. Pura e `Codable` (persistita nei
/// keybinding). I modificatori sono un bitmask indipendente da AppKit; la conversione da/verso
/// `NSEvent` vive nel composition root.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    /// Bitmask dei modificatori, indipendente da AppKit (`NSEvent.ModifierFlags` sta in relay).
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    /// Tasto base normalizzato: un carattere minuscolo (`"t"`, `"]"`) o un nome speciale
    /// (`"tab"`, `"up"`, `"down"`, `"left"`, `"right"`, `"space"`, `"return"`, `"escape"`).
    public let key: String
    public let modifiers: Modifiers

    public init(key: String, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Ha almeno un modificatore "forte" (⌘/⌃/⌥). Lo shift da solo non basta: `⇧A` è digitare una
    /// maiuscola, non una scorciatoia. Il recorder ignora (aspetta) una combo senza modificatore
    /// forte invece di legarla.
    public var hasStrongModifier: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    /// Motivo per cui il recorder rifiuta di legare questa combo (`nil` = registrabile). Distinto
    /// dai conflitti tra azioni (`AppSettings.conflict`): qui sono combo che non funzionerebbero o
    /// romperebbero un'altra funzione a prescindere dai binding correnti.
    public var recordingRejection: ShortcutRejection? {
        // Control-char vitali del terminale: il monitor le ruberebbe al pty (SIGINT/EOF/suspend).
        if modifiers == [.control], ["c", "d", "z"].contains(key) { return .terminal }
        // Comandi di sistema con keyEquivalent veri del menu (quit/settings/copy/paste/select-all).
        if Self.systemReserved.contains(self) { return .system }
        // Select-by-number fissi (⌘/⌥ 1..9): li intercetta il monitor di navigazione a monte,
        // quindi un'azione legata qui non scatterebbe mai.
        if isFixedSelect { return .fixedSelect }
        return nil
    }

    /// `⌘1..9` o `⌥1..9`: i due assi di select fissi, gestiti fuori dai binding rimappabili.
    private var isFixedSelect: Bool {
        guard modifiers == [.command] || modifiers == [.option] else { return false }
        return Int(key).map { (1 ... 9).contains($0) } ?? false
    }

    private static let systemReserved: Set<KeyCombo> = [
        KeyCombo(key: "q", modifiers: [.command]),
        KeyCombo(key: ",", modifiers: [.command]),
        KeyCombo(key: "c", modifiers: [.command]),
        KeyCombo(key: "v", modifiers: [.command]),
        KeyCombo(key: "a", modifiers: [.command]),
        // Voci standard di sistema con keyEquivalent veri (Hide/Hide Others/Minimize/Full Screen):
        // legarle a un'azione farebbe doppio trigger.
        KeyCombo(key: "h", modifiers: [.command]),
        KeyCombo(key: "h", modifiers: [.command, .option]),
        KeyCombo(key: "m", modifiers: [.command]),
        KeyCombo(key: "f", modifiers: [.command, .control]),
    ]

    /// Rappresentazione simbolica per la UI (es. `⌘⇧T`, `⌃⇥`). Ordine dei modificatori come Apple.
    public var display: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        out += Self.symbol(for: key)
        return out
    }

    private static func symbol(for key: String) -> String {
        symbols[key] ?? key.uppercased()
    }

    /// `=` mostrato come `+` per convenzione (zoom in).
    private static let symbols: [String: String] = [
        "tab": "⇥", "up": "↑", "down": "↓", "left": "←", "right": "→",
        "space": "␣", "return": "↩", "escape": "⎋", "delete": "⌫", "=": "+",
    ]
}

/// Perché il recorder rifiuta una combo (per un messaggio d'errore mirato nella UI).
public enum ShortcutRejection: Equatable, Sendable {
    /// Comando di sistema (quit/settings/copy/paste/select-all): romperebbe una funzione base.
    case system
    /// Control-char del terminale (⌃C/⌃D/⌃Z): il monitor la sottrarrebbe al pty.
    case terminal
    /// Select-by-number fisso (⌘/⌥ 1..9): intercettato a monte, non scatterebbe mai.
    case fixedSelect
}

/// Gruppo di azioni, per raggruppare la lista shortcut nel pannello impostazioni.
public enum ShortcutGroup: String, CaseIterable, Identifiable, Sendable {
    case workspace, window, tab, pane, agent, terminal, view

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .workspace: "Workspace"
        case .window: "Window"
        case .tab: "Tab"
        case .pane: "Pane"
        case .agent: "Agent"
        case .terminal: "Terminal"
        case .view: "View"
        }
    }
}

/// Azione rimappabile dell'app. I select-by-number (`Cmd/Option+1..9`) e i comandi di sistema
/// (copy/paste/quit/settings) NON sono qui: restano fissi. Ogni case ha label, gruppo e default.
public enum ShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case newWorkspace, openFolder, closeWorkspace
    case cycleWorkspaceForward, cycleWorkspaceBackward
    case newWindow, closeWindow
    case newTab, closeTab, cycleTabForward, cycleTabBackward
    case splitRight, splitDown, closePane, focusNextPane, focusPrevPane
    case nextAttention, prevAttention, toggleDashboard
    case find, findNext, findPrevious, clear
    case toggleSidebar, zoomIn, zoomOut, actualSize

    public var id: String {
        rawValue
    }

    /// Titolo per menu e lista shortcut: Title Case, come vuole la HIG per le voci di menu.
    public var label: String {
        switch self {
        case .newWorkspace: "New Workspace"
        case .openFolder: "Open Folder as Workspace…"
        case .closeWorkspace: "Close Workspace"
        case .cycleWorkspaceForward: "Next Workspace"
        case .cycleWorkspaceBackward: "Previous Workspace"
        case .newWindow: "New Window"
        case .closeWindow: "Close Window"
        case .newTab: "New Tab"
        case .closeTab: "Close Tab"
        case .cycleTabForward: "Next Tab"
        case .cycleTabBackward: "Previous Tab"
        case .splitRight: "Split Right"
        case .splitDown: "Split Down"
        case .closePane: "Close Pane"
        case .focusNextPane: "Next Pane"
        case .focusPrevPane: "Previous Pane"
        case .nextAttention: "Next Attention"
        case .prevAttention: "Previous Attention"
        case .toggleDashboard: "Agent Dashboard"
        case .find: "Find…"
        case .findNext: "Find Next"
        case .findPrevious: "Find Previous"
        case .clear: "Clear Terminal"
        case .toggleSidebar: "Toggle Sidebar"
        case .zoomIn: "Make Text Bigger"
        case .zoomOut: "Make Text Smaller"
        case .actualSize: "Actual Size"
        }
    }

    public var group: ShortcutGroup {
        switch self {
        case .newWorkspace, .openFolder, .closeWorkspace,
             .cycleWorkspaceForward, .cycleWorkspaceBackward:
            .workspace
        case .newWindow, .closeWindow:
            .window
        case .newTab, .closeTab, .cycleTabForward, .cycleTabBackward:
            .tab
        case .splitRight, .splitDown, .closePane, .focusNextPane, .focusPrevPane:
            .pane
        case .nextAttention, .prevAttention, .toggleDashboard:
            .agent
        case .find, .findNext, .findPrevious, .clear:
            .terminal
        case .toggleSidebar, .zoomIn, .zoomOut, .actualSize:
            .view
        }
    }

    public var defaultCombo: KeyCombo {
        switch self {
        case .newWorkspace: KeyCombo(key: "n", modifiers: [.command])
        case .openFolder: KeyCombo(key: "o", modifiers: [.command])
        // `⇧⌘W` è "Close Window" su tutto macOS (Terminal, iTerm, i browser): tenerlo su "chiudi
        // workspace" - che uccide sessioni - era una trappola per la muscle memory. Il workspace
        // scala di un modificatore, nella famiglia delle chiusure.
        case .closeWorkspace: KeyCombo(key: "w", modifiers: [.command, .option, .shift])
        case .cycleWorkspaceForward: KeyCombo(key: "down", modifiers: [.command, .option])
        case .cycleWorkspaceBackward: KeyCombo(key: "up", modifiers: [.command, .option])
        case .newWindow: KeyCombo(key: "n", modifiers: [.command, .shift])
        case .closeWindow: KeyCombo(key: "w", modifiers: [.command, .shift])
        case .newTab: KeyCombo(key: "t", modifiers: [.command])
        case .closeTab: KeyCombo(key: "w", modifiers: [.command])
        case .cycleTabForward: KeyCombo(key: "tab", modifiers: [.control])
        case .cycleTabBackward: KeyCombo(key: "tab", modifiers: [.control, .shift])
        // Le combo di iTerm/tmux: dividere condivide il tasto, l'asse lo sceglie lo Shift.
        case .splitRight: KeyCombo(key: "\\", modifiers: [.command])
        case .splitDown: KeyCombo(key: "\\", modifiers: [.command, .shift])
        // `Cmd+W` chiude la tab selezionata; il pane chiude tutte le sue tab insieme.
        case .closePane: KeyCombo(key: "w", modifiers: [.command, .option])
        case .focusNextPane: KeyCombo(key: "]", modifiers: [.command])
        case .focusPrevPane: KeyCombo(key: "[", modifiers: [.command])
        case .nextAttention: KeyCombo(key: "j", modifiers: [.command])
        case .prevAttention: KeyCombo(key: "j", modifiers: [.command, .shift])
        case .toggleDashboard: KeyCombo(key: "d", modifiers: [.command])
        case .find: KeyCombo(key: "f", modifiers: [.command])
        case .findNext: KeyCombo(key: "g", modifiers: [.command])
        case .findPrevious: KeyCombo(key: "g", modifiers: [.command, .shift])
        case .clear: KeyCombo(key: "k", modifiers: [.command])
        case .toggleSidebar: KeyCombo(key: "b", modifiers: [.command])
        case .zoomIn: KeyCombo(key: "=", modifiers: [.command])
        case .zoomOut: KeyCombo(key: "-", modifiers: [.command])
        case .actualSize: KeyCombo(key: "0", modifiers: [.command])
        }
    }
}
