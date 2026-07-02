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

    /// Il workspace richiede attenzione: una sua tab aspetta input (`needs_input`) o ha completato
    /// del lavoro non ancora visto (`attention`). Guida il float in cima alla sidebar.
    public var needsAttention: Bool {
        tabs.contains { $0.agentState == .needsInput || $0.attention }
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
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }

    /// Sposta elementi replicando la semantica di `move(fromOffsets:toOffset:)` di SwiftUI,
    /// senza dipendere da SwiftUI (WorkspaceModel resta puro).
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[$0] }
        for index in source.sorted(by: >) {
            remove(at: index)
        }
        let adjusted = destination - source.count(where: { $0 < destination })
        insert(contentsOf: moving, at: Swift.min(Swift.max(adjusted, 0), count))
    }
}
