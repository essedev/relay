import Foundation

// Navigazione e lookup dello store: helper per trovare/rivelare tab fra i workspace. Estratto da
// `WorkspaceStore` per tenere il file principale entro il budget di dimensione (vedi CONVENTIONS).

extension WorkspaceStore {
    /// La tab con questo id fra tutti i workspace (`nil` se non c'è). Un solo idiom di lookup
    /// cross-workspace, condiviso dai consumer del marker di attenzione.
    func tab(id: UUID) -> Tab? {
        workspaces.lazy.flatMap(\.tabs).first { $0.id == id }
    }
}
