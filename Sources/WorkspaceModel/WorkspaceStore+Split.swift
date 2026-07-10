import Foundation

// Comandi di split del workspace selezionato: dividere un pane, chiuderlo, ciclare il focus.
// Estratto da `WorkspaceStore` per tenere il file principale entro il budget di dimensione (vedi
// CONVENTIONS). Il layout vive sul `Workspace` (`layout`), le foglie sono `SplitPane` (modello
// cmux: ogni pane ospita le sue tab).

public extension WorkspaceStore {
    /// Divide un pane (default il focused) con una **nuova tab**, che prende il focus nel nuovo
    /// pane. `workspace` esplicito: le strip vivono in ogni finestra, non solo nella key. La nuova
    /// tab eredita la cwd passata dal chiamante, che la risolve dalla shell viva del pane diviso
    /// (`Core.CurrentDirectory`). Ritorna la tab creata.
    @discardableResult
    func splitPane(
        _ paneID: UUID? = nil,
        axis: SplitAxis,
        in workspace: Workspace,
        currentDirectory: String? = nil
    ) -> Tab? {
        let source = paneID ?? workspace.focusedPaneID
        let sourceTab = workspace.layout.pane(source)?.selectedTabID.flatMap { workspace.tab($0) }
        let inherited = currentDirectory ?? sourceTab?.currentDirectory
        let tab = Tab(currentDirectory: inherited)
        workspace.splitPane(paneID, axis: axis, adding: tab)
        return tab
    }

    /// Compat per le shortcut: divide il pane focused del workspace selezionato.
    @discardableResult
    func splitFocusedPane(axis: SplitAxis, currentDirectory: String? = nil) -> Tab? {
        guard let workspace = selectedWorkspace else { return nil }
        return splitPane(axis: axis, in: workspace, currentDirectory: currentDirectory)
    }

    /// Sposta una tab **esistente** in un nuovo pane accanto al suo ("Open in Split Right/Down"
    /// dal menu della tab): ci va con la sua sessione viva, perché il layout non tocca l'identità
    /// della Tab. No-op se la tab non è nel workspace o è l'unica del suo pane.
    @discardableResult
    func openInSplit(_ tabID: UUID, axis: SplitAxis, in workspace: Workspace) -> Bool {
        guard workspace.tab(tabID) != nil else { return false }
        let before = workspace.layout.paneIDs.count
        workspace.moveTabToSplit(tabID, axis: axis)
        return workspace.layout.paneIDs.count > before
    }

    /// Chiude un pane **e le sue tab** (le sessioni muoiono con lui, come chiudere quelle tab una
    /// per una): la conferma sui processi in foreground la fa il chiamante prima. No-op sull'ultimo
    /// pane. Ritorna gli id delle tab rimosse (per il teardown delle surface).
    @discardableResult
    func closePane(_ paneID: UUID, in workspace: Workspace) -> [UUID] {
        workspace.closePane(paneID)
    }

    /// Chiude il pane focused (`Opt+Cmd+W`). Ritorna gli id delle tab rimosse.
    @discardableResult
    func closeFocusedPane() -> [UUID] {
        guard let workspace = selectedWorkspace else { return [] }
        return workspace.closePane(workspace.focusedPaneID)
    }

    /// Dà il focus a un pane (click sulla sua strip o su una sua tab).
    func focusPane(_ paneID: UUID, in workspace: Workspace) {
        workspace.focusPane(paneID)
    }

    /// Sposta il focus al pane successivo (o precedente) nell'ordine visivo, ciclico. No-op se il
    /// workspace non è splittato. Ritorna `true` se il focus è cambiato.
    @discardableResult
    func focusAdjacentPane(forward: Bool) -> Bool {
        guard let workspace = selectedWorkspace,
              let next = workspace.layout.adjacentPaneID(
                  to: workspace.focusedPaneID, forward: forward
              ) else { return false }
        workspace.focusPane(next)
        return true
    }

    /// Nuova tab in un pane specifico (il `+` della sua strip): il pane prende il focus e la tab
    /// nasce in fondo alla sua strip, selezionata. Cwd ereditata dalla tab selezionata del pane.
    @discardableResult
    func addTab(
        toPane paneID: UUID, in workspace: Workspace, currentDirectory: String? = nil
    ) -> Tab? {
        guard workspace.layout.pane(paneID) != nil else { return nil }
        workspace.focusPane(paneID)
        return addTab(to: workspace, currentDirectory: currentDirectory)
    }

    /// Nuovo rapporto di divisione di un nodo (l'utente ha trascinato il divider). Il rendering
    /// conosce l'id del nodo; lo store si limita a riscrivere il layout, che l'autosave persiste.
    func setSplitRatio(_ ratio: Double, forBranch branchID: UUID, in workspace: Workspace) {
        workspace.setRatio(ratio, forBranch: branchID)
    }
}
