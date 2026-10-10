import AppKit
import Panels
import SwiftUI
import WorkspaceModel

/// Le pagine (Home, Projects) sopra i terminali del right pane. Estratto da `RightPaneController`
/// per il budget di dimensione: qui c'è solo il montaggio, la pagina stessa è SwiftUI (Panels).
extension RightPaneController {
    // MARK: - Pagine (Home, Projects)

    /// Bridge Observation -> AppKit: mostra la pagina quando la finestra ne chiede una (o non ha un
    /// progetto da mostrare), la toglie quando si torna ai terminali. I terminali restano montati
    /// sotto: tornarci è istantaneo e le sessioni non se ne accorgono.
    func observePage() {
        withObservationTracking {
            renderPage(WindowPageView.effectivePage(store, windowID: windowID))
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePage() }
        }
    }

    private func renderPage(_ page: WindowPage) {
        guard page != .workspace else {
            guard let host = pageHost, !host.isHidden else { return }
            host.isHidden = true
            area.focusTerminal()
            return
        }
        let host = pageHost ?? makePageHost()
        guard host.isHidden else { return }
        host.isHidden = false
        // Il focus va alla pagina (Esc, campo di ricerca): sul runloop dopo, come gli overlay.
        DispatchQueue.main.async { [weak self, weak host] in
            guard let host, let window = self?.view.window else { return }
            if let current = window.firstResponder as? NSView, current.isDescendant(of: host) {
                return
            }
            window.makeFirstResponder(host)
        }
    }

    private func makePageHost() -> NSView {
        let host = NSHostingView(rootView: WindowPageView(
            store: store, settings: settings, windowID: windowID, actions: pageActions
        ))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.safeAreaRegions = []
        host.isHidden = true
        // Sopra tutto il right pane, title bar compresa: la pagina ha la sua strip del titolo.
        view.addSubview(host, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        pageHost = host
        return host
    }

    /// Le righe a schermo di una tab (estratto di Home).
    func screenLines(for tabID: UUID) -> [String] {
        registry.screenLines(for: tabID)
    }
}
