import AppKit
import Core
import Panels
import SwiftUI
import WorkspaceModel

/// Wiring della dashboard overlay (griglia delle sessioni agente) e della decadenza dei sospesi.
/// Extension per tenere il corpo di `AppController` sul solo bootstrap: qui vive il ciclo
/// apri/chiudi dell'overlay, il jump verso una sessione e l'applicazione della decadenza.
extension AppController {
    var isDashboardOpen: Bool {
        dashboardHost != nil
    }

    func toggleDashboard() {
        if isDashboardOpen { closeDashboard() } else { openDashboard() }
    }

    private func openDashboard() {
        closeOnboarding() // un overlay full-window alla volta, con lo stato che resta coerente
        applyPendingDecayIfEnabled() // le card nascono già decadute, se la preferenza è attiva
        let dashboard = DashboardView(
            store: store,
            settings: settings,
            onJump: { [weak self] workspace, tab in
                guard let self else { return }
                closeDashboard()
                store.selectWorkspace(workspace.id)
                store.selectTab(tab.id, in: workspace)
            },
            onClose: { [weak self] in self?.closeDashboard() }
        )
        let host = NSHostingView(rootView: dashboard)
        host.safeAreaRegions = []
        rootController.presentFullOverlay(host)
        dashboardHost = host
        // First responder all'overlay sul runloop successivo: la dashboard è una vista pesante
        // (grid + card), sincrono l'hosting view non ha ancora montato il campo filtro e il focus
        // resterebbe "vuoto" (né frecce né Esc). Deferito, SwiftUI ha montato il TextField e il
        // `@FocusState` aggancia. La find bar può farlo sincrono perché è minima e monta in tempo.
        DispatchQueue.main.async { [weak self] in
            self?.splitVC.view.window?.makeFirstResponder(host)
        }
    }

    func closeDashboard() {
        guard isDashboardOpen else { return }
        rootController.dismissFullOverlay()
        dashboardHost = nil
        splitVC.focusTerminal() // il focus torna al terminale in vista
    }

    /// Decadenza opzionale dei sospesi (`pendingDecayHours` > 0): spegne i pending più vecchi
    /// della soglia. Chiamata nei momenti naturali (boot post-restore, ritorno in foreground,
    /// apertura dashboard): niente timer, la granularità è a ore.
    func applyPendingDecayIfEnabled() {
        let hours = settings.pendingDecayHours
        guard hours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let decayed = store.decayPending(olderThan: cutoff)
        if decayed > 0 {
            RelayLog.logger("app").info("pending decay: \(decayed) marker oltre le \(hours)h")
        }
    }
}
