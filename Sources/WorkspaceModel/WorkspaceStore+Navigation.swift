import Foundation

// Navigazione e lookup dello store: helper per trovare/rivelare tab fra i workspace. Estratto da
// `WorkspaceStore` per tenere il file principale entro il budget di dimensione (vedi CONVENTIONS).

extension WorkspaceStore {
    /// La tab con questo id fra tutti i workspace (`nil` se non c'è). Un solo idiom di lookup
    /// cross-workspace, condiviso dai consumer del marker di attenzione.
    func tab(id: UUID) -> Tab? {
        workspaces.lazy.flatMap(\.tabs).first { $0.id == id }
    }

    /// Porta in vista il workspace e la sua tab: de-archivia se serve (una notifica o una card
    /// della
    /// dashboard possono puntare a un workspace archiviato, con la riga nascosta in sidebar), poi
    /// seleziona entrambi. La finestra e l'attivazione dell'app restano al composition root (niente
    /// AppKit qui). No-op se il workspace non esiste più.
    public func reveal(workspaceID: UUID, tabID: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return }
        if workspace.archived { setArchived(workspaceID, false) }
        selectWorkspace(workspaceID)
        selectTab(tabID, in: workspace)
    }
}
