import AppKit
import Core
import WorkspaceModel

// Gestione delle finestre: crearne una per ogni `RelayWindow`, agganciarne gli eventi allo store,
// aprirne di nuove e chiuderle rimpatriando i workspace. Estratto da `AppController` per tenerlo
// sul
// solo wiring (vedi CONVENTIONS). Le finestre condividono store, settings e `SurfaceRegistry`: una
// tab ha una surface sola, ovunque sia montata.

extension AppController {
    /// Costruisce la finestra di un `RelayWindow` e ne aggancia gli eventi allo store. Ogni
    /// finestra
    /// ha il suo split e i suoi overlay, ma **condivide** store, settings e `SurfaceRegistry`.
    func makeWindowController(for relayWindow: RelayWindow) -> RelayWindowController {
        let controller = RelayWindowController(
            windowID: relayWindow.id,
            splitVC: makeSplitViewController(windowID: relayWindow.id),
            toggleOverlay: makeSidebarToggleOverlay(),
            frame: relayWindow.frame
        )
        controller.applyChrome(settings.theme)
        controller.onBecomeKey = { [weak self] id in
            self?.store.activateWindow(id)
        }
        // Una finestra occlusa non la stai guardando: le sue tab tornano a notificare e bumpare.
        controller.onOcclusionChange = { [weak self] (id: UUID, occluded: Bool) in
            guard let self else { return }
            if occluded {
                store.occludedWindowIDs.insert(id)
            } else {
                store.occludedWindowIDs.remove(id)
            }
        }
        controller.onFrameChange = { [weak self] id, frame in
            self?.store.setWindowFrame(frame, for: id)
        }
        controller.onClose = { [weak self] id in
            self?.windowDidClose(id)
        }
        return controller
    }

    /// Una finestra si è chiusa: i suoi workspace rimpatriano in quella attivata più di recente
    /// (`closeWindow`), il lavoro non si butta col contenitore. Sull'ultima è un no-op: lì termina
    /// l'app e il layout va salvato com'è.
    ///
    /// **Non** durante la terminazione: alla chiusura dell'app macOS chiude le finestre una per
    /// una,
    /// e rimpatriare a ogni passaggio collasserebbe il layout multi-window in una finestra sola,
    /// che è poi quello che l'utente si ritroverebbe al riavvio.
    func windowDidClose(_ windowID: UUID) {
        guard !isTerminating else { return }
        let repatriated = store.closeWindow(windowID)
        windowControllers.removeValue(forKey: windowID)
        if !repatriated.isEmpty {
            RelayLog.logger("app")
                .info("window closed: \(repatriated.count) workspaces repatriated")
        }
    }

    /// Sposta un workspace in una finestra nuova ("Move to New Window"): ci va con le sue tab, e le
    /// surface restano vive (la `SurfaceRegistry` è condivisa), quindi nessuna sessione agente si
    /// interrompe. No-op se è l'unico della sua finestra: la lascerebbe vuota.
    func moveWorkspaceToNewWindow(_ workspace: Workspace) {
        guard let relayWindow = store.moveWorkspaceToNewWindow(workspace.id) else { return }
        let controller = makeWindowController(for: relayWindow)
        windowControllers[relayWindow.id] = controller
        controller.show()
        controller.activate()
    }
}
