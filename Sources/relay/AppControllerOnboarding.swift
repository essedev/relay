import AppKit
import Panels
import SwiftUI

/// Wiring dell'onboarding (Welcome to Relay): parte da solo al primo avvio e si riapre da
/// Help > Welcome to Relay. Stessa meccanica della dashboard (overlay full-window in
/// `RootOverlayController`); extension per tenere il corpo di `AppController` sul solo bootstrap.
extension AppController {
    var isOnboardingOpen: Bool {
        onboardingHost != nil
    }

    /// Voce di menu Help > Welcome to Relay.
    @objc func showWelcome(_: Any?) {
        presentOnboarding()
    }

    /// Al primo avvio l'onboarding si presenta da solo, una volta sola (flag persistito, timbrato
    /// alla presentazione: se l'utente lo chiude subito non glielo ripropone a raffica, c'è la
    /// voce Help). Il chiamante esclude la demo mode.
    func showOnboardingIfFirstLaunch() {
        guard !settings.onboardingSeen else { return }
        settings.markOnboardingSeen()
        presentOnboarding()
    }

    func presentOnboarding() {
        closeDashboard() // un overlay full-window alla volta, con lo stato che resta coerente
        guard !isOnboardingOpen else { return }
        let onboarding = OnboardingView(
            settings: settings,
            hooks: makeHookControls(),
            onClose: { [weak self] in self?.closeOnboarding() }
        )
        let host = NSHostingView(rootView: onboarding)
        host.safeAreaRegions = []
        rootController.presentFullOverlay(host)
        onboardingHost = host
        // First responder deferito, come la dashboard: sincrono la hosting view non ha ancora
        // montato la vista `.focusable` e frecce/Esc cadrebbero nel vuoto.
        DispatchQueue.main.async { [weak self] in
            self?.splitVC.view.window?.makeFirstResponder(host)
        }
    }

    func closeOnboarding() {
        guard isOnboardingOpen else { return }
        rootController.dismissFullOverlay()
        onboardingHost = nil
        splitVC.focusTerminal() // il focus torna al terminale in vista
    }
}
