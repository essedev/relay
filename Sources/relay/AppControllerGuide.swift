import AppKit
import Panels
import SwiftUI

/// Wiring del manuale in-app (Help > Relay Guide, `Cmd+?`): stesso overlay full-window di dashboard
/// e onboarding, quindi la mutua esclusione fra i tre è gratis (il presenter ha un solo slot).
/// Extension per tenere il corpo di `AppController` sul solo bootstrap.
extension AppController {
    var isGuideOpen: Bool {
        overlayPresenter?.isPresenting(.guide) ?? false
    }

    /// Voce di menu Help > Relay Guide. Toggle come la dashboard: la stessa combinazione la chiude.
    @objc func showGuide(_: Any?) {
        if isGuideOpen {
            closeGuide()
        } else {
            presentGuide()
        }
    }

    func presentGuide() {
        overlayPresenter?.present(.guide) {
            fullOverlayHost(GuideView(
                settings: self.settings,
                onClose: { [weak self] in self?.closeGuide() }
            ))
        }
    }

    func closeGuide() {
        overlayPresenter?.dismiss(.guide)
    }

    /// `--demo --show dashboard|guide`: apre un overlay subito dopo il seed, per gli screenshot
    /// automatici (`scripts/screenshots.sh` non può premere `Cmd+D` da solo). Differito al giro di
    /// runloop successivo: il presenter monta la hosting view sulla finestra, che durante il
    /// bootstrap non esiste ancora.
    func presentDemoOverlay(_ overlay: DemoOverlay) {
        DispatchQueue.main.async { [weak self] in
            switch overlay {
            case .dashboard: self?.openDashboard()
            case .guide: self?.presentGuide()
            }
        }
    }
}
