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
        overlayPresenter.isPresenting(.dashboard)
    }

    func toggleDashboard() {
        if isDashboardOpen { closeDashboard() } else { openDashboard() }
    }

    private func openDashboard() {
        applyPendingDecayIfEnabled() // le card nascono già decadute, se la preferenza è attiva
        overlayPresenter.present(.dashboard) {
            fullOverlayHost(DashboardView(
                store: self.store,
                settings: self.settings,
                onJump: { [weak self] workspace, tab in
                    guard let self else { return }
                    closeDashboard()
                    store.selectWorkspace(workspace.id)
                    store.selectTab(tab.id, in: workspace)
                },
                onClose: { [weak self] in self?.closeDashboard() }
            ))
        }
    }

    func closeDashboard() {
        overlayPresenter.dismiss(.dashboard)
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
