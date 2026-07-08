import AppKit
import SwiftUI

/// Presenter unico degli overlay full-window (dashboard, onboarding): tiene **un solo** host e
/// quale `Kind` è presentato, così la mutua esclusione ("uno alla volta") è garantita per
/// costruzione invece che a mano (prima ogni `open` chiamava la `close` dell'altro). Centralizza il
/// ciclo che le due extension di `AppController` duplicavano: build host + `safeAreaRegions = []` +
/// `presentFullOverlay` + first responder deferito, e in chiusura `dismissFullOverlay` + ritorno
/// del
/// focus al terminale.
@MainActor
final class FullOverlayPresenter {
    enum Kind {
        case dashboard
        case onboarding
    }

    private let root: RootOverlayController
    private let splitVC: MainSplitViewController
    private(set) var presented: Kind?
    private var host: NSView?

    init(root: RootOverlayController, splitVC: MainSplitViewController) {
        self.root = root
        self.splitVC = splitVC
    }

    func isPresenting(_ kind: Kind) -> Bool {
        presented == kind
    }

    /// Presenta l'overlay per `kind`, costruendo la vista con `content` (invocata sincrona, quindi
    /// non-escaping). Idempotente: no-op se `kind` è già su. Un `kind` diverso sostituisce il
    /// precedente - `presentFullOverlay` dismette da solo il container attuale, un solo slot.
    func present(_ kind: Kind, content: () -> NSView) {
        guard presented != kind else { return }
        let host = content()
        root.presentFullOverlay(host)
        self.host = host
        presented = kind
        // First responder all'overlay sul runloop successivo: sincrono la hosting view non ha
        // ancora montato i suoi campi (TextField della dashboard, vista `.focusable`
        // dell'onboarding) e frecce/Esc cadrebbero nel vuoto.
        DispatchQueue.main.async { [weak self, weak host] in
            self?.splitVC.view.window?.makeFirstResponder(host)
        }
    }

    /// Chiude solo se `kind` è quello presentato (preserva il vecchio `guard isXOpen`: chiudere la
    /// dashboard mentre è su l'onboarding è un no-op).
    func dismiss(_ kind: Kind) {
        guard presented == kind else { return }
        dismiss()
    }

    func dismiss() {
        guard presented != nil else { return }
        root.dismissFullOverlay()
        host = nil
        presented = nil
        splitVC.focusTerminal() // il focus torna al terminale in vista
    }
}

/// Hosting view di un overlay full-window con la safe area disattivata: il layout verticale lo
/// gestisce la chrome, altrimenti SwiftUI spinge il contenuto sotto la title bar (`safeAreaRegions`
/// è di `NSHostingView`, non di `NSView`, quindi va settata dove il tipo concreto è noto).
@MainActor
func fullOverlayHost(_ view: some View) -> NSView {
    let host = NSHostingView(rootView: view)
    host.safeAreaRegions = []
    return host
}
