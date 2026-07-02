import AgentProtocol
import Foundation

/// Stato dell'app: la lista di workspace e la selezione corrente. Osservabile, guida la sidebar
/// e l'area di lavoro. Puro: non conosce le surface del terminale (legate per `Tab.id` altrove).
///
/// Le operazioni di chiusura ritornano gli id delle tab rimosse, così il chiamante può fare il
/// teardown delle surface vive corrispondenti.
@Observable
public final class WorkspaceStore {
    public private(set) var workspaces: [Workspace]
    public var selectedWorkspaceID: UUID?

    public init(workspaces: [Workspace] = []) {
        self.workspaces = workspaces
        selectedWorkspaceID = workspaces.first?.id
    }

    // MARK: - Query

    public var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    public var pinnedWorkspaces: [Workspace] {
        workspaces.filter(\.pinned)
    }

    public var otherWorkspaces: [Workspace] {
        workspaces.filter { !$0.pinned }
    }

    // MARK: - Workspace

    @discardableResult
    public func createWorkspace(name: String, rootPath: String? = nil) -> Workspace {
        let workspace = Workspace(name: name, rootPath: rootPath)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        addTab(to: workspace) // ogni workspace nasce con una tab
        return workspace
    }

    public func selectWorkspace(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        selectedWorkspaceID = id
    }

    public func togglePin(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        workspace.pinned.toggle()
    }

    /// Rimuove un workspace. Ritorna gli id delle tab rimosse (per il teardown delle surface).
    @discardableResult
    public func closeWorkspace(_ id: UUID) -> [UUID] {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return [] }
        let removedTabIDs = workspaces[index].tabs.map(\.id)
        workspaces.remove(at: index)
        if selectedWorkspaceID == id {
            let neighbor = workspaces[safe: index] ?? workspaces[safe: index - 1] ?? workspaces.last
            selectedWorkspaceID = neighbor?.id
        }
        return removedTabIDs
    }

    public func moveWorkspaces(fromOffsets: IndexSet, toOffset: Int) {
        workspaces.moveElements(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    // MARK: - Tab

    @discardableResult
    public func addTab(to workspace: Workspace, title: String = "shell") -> Tab {
        workspace.appendTab(Tab(title: title), select: true)
    }

    public func selectTab(_ tabID: UUID, in workspace: Workspace) {
        guard workspace.tabs.contains(where: { $0.id == tabID }) else { return }
        workspace.selectedTabID = tabID
    }

    /// Chiude una tab. Ritorna l'id rimosso (per il teardown della surface).
    @discardableResult
    public func closeTab(_ tabID: UUID, in workspace: Workspace) -> UUID? {
        workspace.removeTab(tabID)
    }

    public func renameTab(_ tabID: UUID, in workspace: Workspace, to title: String) {
        guard let tab = workspace.tabs.first(where: { $0.id == tabID }) else { return }
        tab.title = title
        tab.hasCustomTitle = true
    }

    // MARK: - Stato agente

    /// Applica un evento agente alla tab identificata da `paneId` (= `RELAY_TAB_ID` = `Tab.id`).
    /// Lo store calcola `isVisible` (workspace + tab selezionati) e delega la transizione al
    /// reducer.
    /// Ritorna `false` se `paneId` non è un UUID valido o non corrisponde a nessuna tab (no-op).
    @discardableResult
    public func applyAgentState(paneId: String, state: AgentState, at timestamp: Date) -> Bool {
        guard let tabID = UUID(uuidString: paneId) else { return false }
        for workspace in workspaces {
            guard let tab = workspace.tabs.first(where: { $0.id == tabID }) else { continue }
            let isVisible = selectedWorkspaceID == workspace.id && workspace.selectedTabID == tab.id
            let result = AgentStateReducer.reduce(
                current: tab.agentState,
                incoming: state,
                isVisible: isVisible,
                currentAttention: tab.attention
            )
            tab.agentState = result.state
            tab.attention = result.attention
            tab.lastEventAt = timestamp
            return true
        }
        return false
    }
}
