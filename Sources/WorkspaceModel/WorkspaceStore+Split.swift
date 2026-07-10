import Foundation

// Comandi di split del workspace selezionato: dividere un pane, smontarlo, ciclare il focus fra i
// pane. Estratto da `WorkspaceStore` per tenere il file principale entro il budget di dimensione
// (vedi CONVENTIONS). Il layout vive sul `Workspace` (`splitLayout`), le foglie sono `Tab.id`.

public extension WorkspaceStore {
    /// Divide il pane focused e ci monta accanto (o sotto) una **nuova tab**, che prende il focus.
    /// La nuova tab eredita la cwd passata dal chiamante, che la risolve dalla shell viva del pane
    /// diviso (`Core.CurrentDirectory`). Ritorna la tab creata, o `nil` senza workspace
    /// selezionato.
    @discardableResult
    func splitFocusedPane(axis: SplitAxis, currentDirectory: String? = nil) -> Tab? {
        guard let workspace = selectedWorkspace, workspace.selectedTabID != nil else { return nil }
        let inherited = currentDirectory ?? workspace.selectedTab?.currentDirectory
        let tab = Tab(currentDirectory: inherited)
        workspace.appendTab(tab, select: false) // lo monta `split`, non la selezione
        workspace.split(axis: axis, with: tab.id)
        return tab
    }

    /// Chiude il **pane** focused: la tab resta viva nella tab bar (sessione agente compresa),
    /// sparisce solo dallo schermo, e il fratello prende il suo spazio. Distinto da `closeTab`, che
    /// uccide la sessione. No-op senza split (l'unico pane non si smonta). Ritorna `true` se ha
    /// smontato qualcosa.
    @discardableResult
    func closeFocusedPane() -> Bool {
        guard let workspace = selectedWorkspace, workspace.splitLayout != nil,
              let focused = workspace.selectedTabID else { return false }
        workspace.unmount(focused)
        return true
    }

    /// Sposta il focus al pane successivo (o precedente) nell'ordine visivo, ciclico. No-op se il
    /// workspace non è splittato. Ritorna `true` se il focus è cambiato.
    @discardableResult
    func focusAdjacentPane(forward: Bool) -> Bool {
        guard let workspace = selectedWorkspace,
              let layout = workspace.splitLayout,
              let focused = workspace.selectedTabID,
              let next = layout.adjacentLeaf(to: focused, forward: forward) else { return false }
        workspace.selectedTabID = next
        return true
    }

    /// Nuovo rapporto di divisione di un nodo (l'utente ha trascinato il divider). Il rendering
    /// conosce l'id del nodo; lo store si limita a riscrivere il layout, che l'autosave persiste.
    func setSplitRatio(_ ratio: Double, forBranch branchID: UUID, in workspace: Workspace) {
        guard let layout = workspace.splitLayout else { return }
        workspace.splitLayout = layout.settingRatio(ratio, forBranch: branchID)
    }
}
