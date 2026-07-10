import Foundation

// Navigazione e lookup dello store: trovare/rivelare una tab fra i workspace, saltare a quelle che
// richiedono attenzione, ciclare fra tab e workspace adiacenti. Estratto da `WorkspaceStore` per
// tenere il file principale entro il budget di dimensione (vedi CONVENTIONS).

public extension WorkspaceStore {
    /// La tab con questo id fra tutti i workspace (`nil` se non c'è). Un solo idiom di lookup
    /// cross-workspace, condiviso dai consumer del marker di attenzione.
    internal func tab(id: UUID) -> Tab? {
        workspaces.lazy.flatMap(\.tabs).first { $0.id == id }
    }

    /// Porta in vista il workspace e la sua tab: de-archivia se serve (una notifica o una card
    /// della
    /// dashboard possono puntare a un workspace archiviato, con la riga nascosta in sidebar), poi
    /// seleziona entrambi. La finestra e l'attivazione dell'app restano al composition root (niente
    /// AppKit qui). No-op se il workspace non esiste più.
    func reveal(workspaceID: UUID, tabID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        if workspace.archived { setArchived(workspaceID, false) }
        selectWorkspace(workspaceID)
        selectTab(tabID, in: workspace)
    }

    /// Porta in vista la prossima (`focusNextAttention`) o precedente (`focusPrevAttention`) tab
    /// che
    /// richiede attenzione, in ordine visivo (`orderedWorkspaces` + ordine tab) e ciclico rispetto
    /// alla selezione corrente. Due livelli: prima l'attenzione fresca (aspetta input o completato
    /// non visto); esauriti quelli, i sospesi (`pending`). Salta sempre la corrente. No-op se
    /// nessuna tab la richiede. Ritorna `true` se la selezione è cambiata.
    @discardableResult
    func focusNextAttention() -> Bool {
        focusAttention(forward: true)
    }

    @discardableResult
    func focusPrevAttention() -> Bool {
        focusAttention(forward: false)
    }

    @discardableResult
    private func focusAttention(forward: Bool) -> Bool {
        let flat: [(ws: Workspace, tab: Tab)] = orderedWorkspaces.flatMap { ws in
            ws.orderedTabs.map { (ws, $0) }
        }
        let fresh = flat.indices.filter {
            flat[$0].tab.agentState == .needsInput || flat[$0].tab.attention == .unseen
        }
        let hits = fresh.isEmpty
            ? flat.indices.filter { flat[$0].tab.attention == .pending }
            : fresh
        guard !hits.isEmpty else { return false }
        let current = flat.firstIndex {
            $0.ws.id == selectedWorkspaceID && $0.tab.id == $0.ws.selectedTabID
        } ?? -1
        let targetIndex = forward
            ? (hits.first { $0 > current } ?? hits[0])
            : (hits.last { $0 < current } ?? hits[hits.count - 1])
        let target = flat[targetIndex]
        // `selectWorkspace`, non il setter della proiezione: il workspace può vivere in un'altra
        // finestra (multi-window), e assegnarlo alla key violerebbe la partizione (la stessa
        // surface finirebbe montata in due aree).
        selectWorkspace(target.ws.id)
        target.ws.reveal(target.tab.id)
        return true
    }

    /// Seleziona la tab adiacente **nella strip del pane focused** (ciclico). `forward` = la
    /// successiva. Col modello cmux la navigazione fra tab è per pane; fra pane si va con
    /// `Cmd+]`/`Cmd+[`.
    func selectAdjacentTab(forward: Bool) {
        guard let workspace = selectedWorkspace,
              let pane = workspace.focusedPane, !pane.tabIDs.isEmpty else { return }
        let tabs = pane.tabIDs
        let current = pane.selectedTabID.flatMap { tabs.firstIndex(of: $0) } ?? 0
        let next = (current + (forward ? 1 : -1) + tabs.count) % tabs.count
        workspace.reveal(tabs[next])
    }

    /// Seleziona il workspace adiacente in ordine visivo (`orderedWorkspaces`, ciclico).
    func selectAdjacentWorkspace(forward: Bool) {
        let ordered = orderedWorkspaces
        guard !ordered.isEmpty else { return }
        let current = ordered.firstIndex { $0.id == selectedWorkspaceID } ?? 0
        let next = (current + (forward ? 1 : -1) + ordered.count) % ordered.count
        selectedWorkspaceID = ordered[next].id
    }
}
