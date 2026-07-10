import Foundation

// Le finestre come partizione dei workspace: aprirne una, attivarla, chiuderla rimpatriando i suoi
// workspace. Estratto da `WorkspaceStore` per tenere il file principale entro il budget di
// dimensione (vedi CONVENTIONS). La `NSWindow` vera vive nel composition root, legata per `id`.

public extension WorkspaceStore {
    /// La finestra che possiede il workspace.
    func window(of workspace: Workspace) -> RelayWindow? {
        windows.first { $0.id == workspace.windowID }
    }

    /// La finestra è a schermo: non occlusa da altre finestre né minimizzata. È la nozione di
    /// visibilità che conta per notifiche e bump, **non** l'avere il focus: con due monitor la
    /// finestra che stai fissando spesso non è la key.
    func isWindowVisible(_ windowID: UUID) -> Bool {
        !occludedWindowIDs.contains(windowID)
    }

    /// Segna la finestra come key e la porta in testa alla cronologia di attivazione (guida il
    /// rimpatrio dei workspace quando una finestra chiude). No-op se non esiste.
    func activateWindow(_ windowID: UUID) {
        guard windows.contains(where: { $0.id == windowID }) else { return }
        keyWindowID = windowID
        activationOrder.removeAll { $0 == windowID }
        activationOrder.insert(windowID, at: 0)
    }

    /// Sposta un workspace in una finestra **esistente**. La finestra di partenza ripiega su un
    /// altro dei suoi. No-op se è l'unico che le resta (la lascerebbe vuota), se la destinazione
    /// non esiste o se ci è già. I `Tab` non si toccano: surface e sessioni restano vive.
    @discardableResult
    func moveWorkspace(_ id: UUID, toWindow target: UUID) -> Bool {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.windowID != target,
              windows.contains(where: { $0.id == target }),
              workspaces(in: workspace.windowID).count > 1 else { return false }
        let origin = workspace.windowID
        workspace.windowID = target
        reselectAfterLeaving(origin, movedAway: id)
        return true
    }

    /// La finestra `origin` mostrava il workspace che se n'è appena andato: passa a un altro suo.
    private func reselectAfterLeaving(_ origin: UUID, movedAway id: UUID) {
        guard let window = windows.first(where: { $0.id == origin }),
              window.selectedWorkspaceID == id else { return }
        window.selectedWorkspaceID = (orderedWorkspaces(in: origin).first
            ?? workspaces(in: origin).first)?.id
    }

    /// Sposta un workspace in una finestra **nuova**, che diventa la key ("Move to New Window").
    /// No-op se è l'unico della sua finestra: la lascerebbe vuota, e una finestra senza workspace
    /// non ha niente da mostrare (nasce da un workspace, non prima di lui).
    /// I `Tab` non si toccano, quindi le surface vive e le sessioni agente restano intatte.
    @discardableResult
    func moveWorkspaceToNewWindow(_ id: UUID, frame: WindowFrame? = nil) -> RelayWindow? {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspaces(in: workspace.windowID).count > 1 else { return nil }
        let origin = workspace.windowID
        let window = RelayWindow(selectedWorkspaceID: id, frame: frame)
        windows.append(window)
        workspace.windowID = window.id
        workspace.archived = false // una finestra che mostra un archiviato sarebbe vuota
        reselectAfterLeaving(origin, movedAway: id)
        activateWindow(window.id)
        return window
    }

    /// Chiude una finestra **rimpatriando** i suoi workspace in quella attivata più di recente:
    /// chiudere una finestra è un gesto sul contenitore, non sul lavoro che contiene. Nessuna
    /// finestra è privilegiata. No-op sull'ultima rimasta: lì è l'app a chiudersi, e il layout va
    /// salvato com'è (i workspace restano suoi).
    /// Ritorna gli id dei workspace rimpatriati.
    @discardableResult
    func closeWindow(_ windowID: UUID) -> [UUID] {
        guard windows.count > 1, let index = windows.firstIndex(where: { $0.id == windowID })
        else { return [] }
        let liveIDs = Set(windows.map(\.id))
        let heir = activationOrder.first { $0 != windowID && liveIDs.contains($0) }
            ?? windows.first { $0.id != windowID }?.id
        guard let heirID = heir, let heirWindow = windows.first(where: { $0.id == heirID })
        else { return [] }

        let orphans = workspaces(in: windowID)
        for workspace in orphans {
            workspace.windowID = heirID
        }
        windows.remove(at: index)
        activationOrder.removeAll { $0 == windowID }
        occludedWindowIDs.remove(windowID)
        // L'erede continua a mostrare il suo workspace; se non ne aveva uno valido, prende il primo
        // dei rimpatriati, così non resta con la sidebar piena e il right pane vuoto.
        let shown = heirWindow.selectedWorkspaceID
        let stillShowsOneOfItsOwn = workspaces.contains {
            $0.id == shown && $0.windowID == heirID
        }
        if !stillShowsOneOfItsOwn {
            heirWindow.selectedWorkspaceID = (orderedWorkspaces(in: heirID).first
                ?? workspaces(in: heirID).first)?.id
        }
        if keyWindowID == windowID { activateWindow(heirID) }
        return orphans.map(\.id)
    }

    /// Registra il frame corrente di una finestra (resize/spostamento), che l'autosave persiste.
    func setWindowFrame(_ frame: WindowFrame, for windowID: UUID) {
        windows.first { $0.id == windowID }?.frame = frame
    }
}
