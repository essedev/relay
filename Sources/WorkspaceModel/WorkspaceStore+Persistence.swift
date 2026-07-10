import Foundation

// Persistence del layout: fotografia serializzabile dello store e ricostruzione al riavvio.
// Estratto da `WorkspaceStore` per tenere il file principale entro il budget di dimensione (vedi
// CONVENTIONS). Non persiste stato agente (effimero) né surface (ricreate lazy al primo focus).

public extension WorkspaceStore {
    /// Fotografa il layout corrente (per il salvataggio su disco). Solo dati persistenti: niente
    /// stato agente né surface.
    func snapshot() -> LayoutSnapshot {
        LayoutSnapshot(
            selectedWorkspaceID: selectedWorkspaceID,
            workspaces: workspaces.map { workspace in
                WorkspaceSnapshot(
                    id: workspace.id,
                    windowID: workspace.windowID,
                    name: workspace.name,
                    nameOrigin: workspace.nameOrigin,
                    rootPath: workspace.rootPath,
                    pinned: workspace.pinned,
                    archived: workspace.archived,
                    selectedTabID: workspace.selectedTabID,
                    splitLayout: workspace.layout,
                    focusedPaneID: workspace.focusedPaneID,
                    tabs: workspace.tabs.map { tab in
                        TabSnapshot(
                            id: tab.id,
                            title: tab.title,
                            hasCustomTitle: tab.hasCustomTitle,
                            currentDirectory: tab.currentDirectory,
                            resume: tab.resume,
                            // Un completamento mai ripreso sopravvive al riavvio come "in
                            // sospeso": anche `unseen` degrada a pending (al restore il segnale
                            // forte sarebbe stantio; il posto giusto è la dashboard). Persisto il
                            // clock del marker (`attentionSince`), non `lastEventAt`.
                            pendingSince: tab.attention == .none
                                ? nil
                                : (tab.attentionSince ?? tab.lastEventAt)
                        )
                    }
                )
            },
            windows: windows.map { window in
                WindowSnapshot(
                    id: window.id,
                    selectedWorkspaceID: window.selectedWorkspaceID,
                    frame: window.frame,
                    isKey: window.id == keyWindowID
                )
            }
        )
    }

    /// Ricostruisce workspace e tab da uno snapshot (al restore). Le tab nascono senza stato agente
    /// e `unrealized`: la surface parte al primo focus (vedi lifecycle in ARCHITECTURE). La
    /// selezione viene validata contro i workspace effettivamente ricostruiti.
    /// `now` = istante del restore: un marker sopravvissuto degrada a `pending` e il suo clock di
    /// decadenza (`attentionSince`) riparte da qui, così un completamento mai visto non viene
    /// spazzato subito al primo boot (il decay misurerebbe dall'età dell'evento, non da ora).
    func restore(from snapshot: LayoutSnapshot, now: Date = Date()) {
        workspaces = snapshot.workspaces.map { workspace in
            let tabs = workspace.tabs.map { tab in
                Tab(
                    id: tab.id,
                    title: tab.title,
                    hasCustomTitle: tab.hasCustomTitle,
                    currentDirectory: tab.currentDirectory,
                    attention: tab.pendingSince == nil ? .none : .pending,
                    lastEventAt: tab.pendingSince, // età reale dell'evento (ordinamento dashboard)
                    attentionSince: tab.pendingSince == nil ? nil : now, // clock decay dal boot
                    resume: tab.resume
                )
            }
            // La selezione salvata potrebbe puntare a una tab inesistente (file editato a mano,
            // corruzione parziale che decodifica ancora): validala, altrimenti `Workspace.init`
            // ricade sulla prima tab invece di lasciare il right pane senza tab.
            let selectedTabID = tabs.contains { $0.id == workspace.selectedTabID }
                ? workspace.selectedTabID
                : nil
            // Il layout viene sanitizzato da `Workspace.init` contro le tab davvero ricostruite
            // (pane orfani collassati, duplicati scartati, tab fuori dall'albero adottate).
            return Workspace(
                id: workspace.id,
                windowID: workspace.windowID,
                name: workspace.name,
                nameOrigin: workspace.nameOrigin,
                rootPath: workspace.rootPath,
                pinned: workspace.pinned,
                archived: workspace.archived,
                tabs: tabs,
                selectedTabID: selectedTabID,
                layout: workspace.splitLayout,
                focusedPaneID: workspace.focusedPaneID
            )
        }
        restoreWindows(from: snapshot)
        // La selezione deve puntare a un workspace VISIBILE (non archiviato): setArchived la sposta
        // via dagli archiviati, ma un file editato a mano potrebbe averla lasciata su uno. Ricade
        // sul primo visibile, e solo se tutti sono archiviati (degenere) sul primo assoluto.
        for window in windows {
            let saved = window.selectedWorkspaceID
            let visible = orderedWorkspaces(in: window.id)
            window.selectedWorkspaceID = visible.contains { $0.id == saved }
                ? saved
                : visible.first?.id ?? workspaces(in: window.id).first?.id
        }
    }

    /// Ricostruisce le finestre. Un layout salvato prima del multi-window non ha `windows`: tutti i
    /// suoi workspace hanno `windowID == RelayWindow.mainID` (default del decode), quindi basta una
    /// finestra sola con la selezione salvata. Le finestre **senza workspace** vengono scartate:
    /// una
    /// finestra vuota non ha niente da mostrare, e i suoi workspace erano già stati riassegnati.
    private func restoreWindows(from snapshot: LayoutSnapshot) {
        let owners = Set(workspaces.map(\.windowID))
        let restored = snapshot.windows
            .filter { owners.contains($0.id) }
            .map { RelayWindow(
                id: $0.id,
                selectedWorkspaceID: $0.selectedWorkspaceID,
                frame: $0.frame
            ) }

        if restored.isEmpty {
            let main = RelayWindow(
                id: RelayWindow.mainID, selectedWorkspaceID: snapshot.selectedWorkspaceID
            )
            windows = [main]
        } else {
            windows = restored
        }
        // Un workspace la cui finestra è sparita (file editato a mano) finisce nella prima: meglio
        // in una sidebar sbagliata che invisibile per sempre.
        let live = Set(windows.map(\.id))
        for workspace in workspaces where !live.contains(workspace.windowID) {
            workspace.windowID = windows[0].id
        }
        let key = snapshot.windows.first(where: \.isKey)?.id
        keyWindowID = key.flatMap { live.contains($0) ? $0 : nil } ?? windows[0].id
        // Cronologia: la key davanti, il resto nell'ordine salvato.
        activationOrder = [keyWindowID] + windows.map(\.id).filter { $0 != keyWindowID }
    }
}
