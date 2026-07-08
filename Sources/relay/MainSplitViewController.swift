import AppKit
import Observation
import Panels
import SwiftUI
import TerminalEngine
import WorkspaceModel

/// Split principale: sidebar (SwiftUI in NSHostingController) + area di lavoro a destra.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    private let settings: AppSettings
    private let right: RightPaneController
    private var sidebarItem: NSSplitViewItem!
    /// Notifica la larghezza corrente della sidebar (0 se collassata) a ogni resize, anche
    /// frame-by-frame durante l'animazione: guida la posizione dell'overlay toggle.
    var onSidebarWidthChange: ((CGFloat) -> Void)?

    init(
        store: WorkspaceStore,
        settings: AppSettings,
        engine: TerminalEngine,
        updateConfig: SidebarUpdateConfig?,
        onNewWorkspace: @escaping () -> Void,
        onCloseWorkspace: @escaping (Workspace) -> Void,
        onCloseTab: @escaping (WorkspaceModel.Tab, Workspace) -> Void
    ) {
        self.settings = settings
        right = RightPaneController(
            store: store,
            settings: settings,
            engine: engine,
            onCloseTab: onCloseTab
        )
        super.init(nibName: nil, bundle: nil)

        let sidebar = NSHostingController(
            rootView: SidebarView(
                store: store,
                settings: settings,
                onNewWorkspace: onNewWorkspace,
                onCloseWorkspace: onCloseWorkspace,
                updateConfig: updateConfig
            )
        )
        // L'header della sidebar vive sulla riga dei semafori (full-size content view): niente
        // safe area, il layout la gestisce con l'inset esplicito.
        sidebar.safeAreaRegions = []
        // Item normale, non `sidebarWithViewController:`: su macOS 26 quello stila la sidebar come
        // pannello glass flottante (box, materiale, margini), in conflitto col design flat themed.
        let item = NSSplitViewItem(viewController: sidebar)
        item.minimumThickness = CGFloat(AppSettings.minSidebarWidth)
        item.maximumThickness = CGFloat(AppSettings.maxSidebarWidth)
        // Il resize della finestra va al body: la sidebar tiene la sua larghezza.
        item.holdingPriority = NSLayoutConstraint.Priority(260)
        item.canCollapse = true
        sidebarItem = item
        addSplitViewItem(item)

        addSplitViewItem(NSSplitViewItem(viewController: right))

        observeSidebarState()
    }

    /// Inoltra la query "processo in foreground" della tab al right pane (registry delle surface).
    /// Usata dalla conferma di chiusura nell'AppController.
    func foregroundProcess(for tabID: UUID) -> String? {
        right.foregroundProcess(for: tabID)
    }

    /// Surface vive nel right pane (strumentazione di performance, misure M3).
    var liveSurfaceCount: Int {
        right.liveSurfaceCount
    }

    /// Mostra/chiude la find bar sul terminale attivo (Cmd+F).
    func toggleFind() {
        right.toggleFind()
    }

    /// Risultato successivo/precedente: apre la find bar se chiusa, altrimenti scorre.
    func findStep(forward: Bool) {
        right.findStep(forward: forward)
    }

    /// Pulisce il terminale della tab attiva (Cmd+K).
    func clearActiveTerminal() {
        right.clearActiveTerminal()
    }

    /// Flash del ring di attenzione (ritorno in foreground).
    func flashAttentionRing() {
        right.flashAttentionRing()
    }

    /// Riporta il focus al terminale attivo (dopo la chiusura di un overlay, es. dashboard).
    func focusTerminal() {
        right.focusTerminal()
    }

    /// Inietta un comando nella surface di una tab (play dell'update). Inoltra al right pane.
    func sendText(to tabID: UUID, _ text: String) {
        right.sendText(to: tabID, text)
    }

    /// L'evento appartiene al terminale in vista (mark-read filtrato). Inoltra al right pane.
    func terminalOwns(_ event: NSEvent) -> Bool {
        right.terminalOwns(event)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("MainSplitViewController is programmatic-only")
    }

    /// Applica la larghezza persistita alla prima passata di layout (quando la sidebar e espansa):
    /// dopo, il resize manuale la aggiorna e la persiste da solo.
    private var didApplyInitialWidth = false

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !didApplyInitialWidth, view.bounds.width > 0 else { return }
        didApplyInitialWidth = true
        if !settings.sidebarCollapsed {
            splitView.setPosition(CGFloat(settings.sidebarWidth), ofDividerAt: 0)
        }
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard let sidebarView = splitView.arrangedSubviews.first else { return }
        let visibleWidth = sidebarView.isHidden ? 0 : sidebarView.frame.width
        onSidebarWidthChange?(visibleWidth)
        // Salva solo dopo l'applicazione iniziale: altrimenti i resize transitori del boot
        // sovrascrivono il valore persistito prima che `viewDidLayout` lo applichi. E solo se
        // espansa (durante il collapse la larghezza va a 0). `setSidebarWidth` clampa e dedup.
        guard didApplyInitialWidth, !sidebarView.isHidden,
              visibleWidth >= CGFloat(AppSettings.minSidebarWidth) else { return }
        settings.setSidebarWidth(Double(visibleWidth))
    }

    /// Lo stato del collapse vive in `AppSettings` (persistito); qui lo si applica all'item,
    /// animato. Si ri-arma sui cambi (Observation).
    private func observeSidebarState() {
        withObservationTracking {
            let collapsed = settings.sidebarCollapsed
            if sidebarItem.isCollapsed != collapsed {
                sidebarItem.animator().isCollapsed = collapsed
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSidebarState() }
        }
    }
}
