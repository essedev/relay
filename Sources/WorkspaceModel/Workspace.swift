import AgentProtocol
import Foundation

/// Un progetto: raggruppa tab (terminali), sta nella sidebar, si pinna e si riordina.
/// Model puro e osservabile: nessuna dipendenza da AppKit o dall'engine. Le surface vive sono
/// legate per `Tab.id` fuori dal model (vedi TerminalHostUI).
@Observable
public final class Workspace: Identifiable {
    public let id: UUID
    public var name: String
    public var rootPath: String?
    public var pinned: Bool
    public private(set) var tabs: [Tab]
    public var selectedTabID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        rootPath: String? = nil,
        pinned: Bool = false,
        tabs: [Tab] = [],
        selectedTabID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.pinned = pinned
        self.tabs = tabs
        self.selectedTabID = selectedTabID ?? tabs.first?.id
    }

    public var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabID }
    }

    /// Il workspace richiede attenzione *fresca*: una sua tab aspetta input (`needs_input`) o ha
    /// completato del lavoro non ancora visto (`unseen`). Guida il float in cima alla sidebar.
    /// I sospesi (`pending`) NON galleggiano: sono un segnale quieto (punto dimesso + dashboard).
    public var needsAttention: Bool {
        tabs.contains { $0.agentState == .needsInput || $0.attention == .unseen }
    }

    // MARK: - Mutazioni tab (usate dallo store; qui per tenere l'invariante di selezione)

    @discardableResult
    func appendTab(_ tab: Tab, select: Bool) -> Tab {
        tabs.append(tab)
        if select || selectedTabID == nil { selectedTabID = tab.id }
        return tab
    }

    /// Rimuove la tab e seleziona un vicino. Ritorna l'id rimosso (per il teardown della surface).
    @discardableResult
    func removeTab(_ tabID: UUID) -> UUID? {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        tabs.remove(at: index)
        if selectedTabID == tabID {
            let neighbor = tabs[safe: index] ?? tabs[safe: index - 1] ?? tabs.last
            selectedTabID = neighbor?.id
        }
        return tabID
    }

    /// Sposta `id` immediatamente prima di `targetID` (`nil` = in fondo). No-op se coincidono o
    /// `id` non esiste. Non tocca la selezione: spostare non cambia quale tab è attiva.
    func moveTab(_ id: UUID, before targetID: UUID?) {
        guard id != targetID,
              let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let moved = tabs.remove(at: from)
        if let targetID, let to = tabs.firstIndex(where: { $0.id == targetID }) {
            tabs.insert(moved, at: to)
        } else {
            tabs.append(moved)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
