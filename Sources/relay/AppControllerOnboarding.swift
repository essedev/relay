import AppKit
import Panels
import SwiftUI

/// Wiring dell'onboarding (Welcome to Relay): parte da solo al primo avvio e si riapre da
/// Help > Welcome to Relay. Stessa meccanica della dashboard (overlay full-window in
/// `RootOverlayController`); extension per tenere il corpo di `AppController` sul solo bootstrap.
extension AppController {
    var isOnboardingOpen: Bool {
        overlayPresenter?.isPresenting(.onboarding) ?? false
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
        overlayPresenter?.present(.onboarding) {
            fullOverlayHost(OnboardingView(
                settings: self.settings,
                hooks: self.makeHookControls(),
                onClose: { [weak self] in self?.closeOnboarding() }
            ))
        }
    }

    func closeOnboarding() {
        overlayPresenter?.dismiss(.onboarding)
    }
}
