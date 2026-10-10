import AppKit
import Observation
import Panels
import SwiftUI
import TerminalEngine
import TerminalHostUI
import WorkspaceModel

/// Split principale: sidebar (SwiftUI in NSHostingController) + area di lavoro a destra.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    private let settings: AppSettings
    private let right: RightPaneController
    private var sidebarItem: NSSplitViewItem!
    /// Le due card (sidebar e contenuto) sopra la cornice della finestra.
    private var sidebarCard: CardContainerController!
    private var contentCard: CardContainerController!
    /// Il drag di una tab dalla strip di un pane a una riga della sidebar: una sessione per
    /// finestra, perché è qui che le due hosting view coesistono (vedi `TabDragSession`).
    let tabDrag = TabDragSession()
    /// Notifica la larghezza corrente della sidebar (0 se collassata) a ogni resize, anche
    /// frame-by-frame durante l'animazione: guida la posizione dell'overlay toggle.
    var onSidebarWidthChange: ((CGFloat) -> Void)?

    init(
        store: WorkspaceStore,
        settings: AppSettings,
        engine: TerminalEngine,
        windowID: UUID,
        registry: SurfaceRegistry,
        updateConfig: SidebarUpdateConfig?,
        onNewWorkspace: @escaping () -> Void,
        onMoveWorkspaceToNewWindow: @escaping (Workspace) -> Void,
        onCloseWorkspace: @escaping (Workspace) -> Void,
        onCloseProject: @escaping (Workspace) -> Void,
        onDeactivateSessions: @escaping (Workspace) -> Void,
        onRegenerateWorkspaceName: @escaping (Workspace) -> Void,
        onShowPalette: @escaping () -> Void,
        onShowPage: @escaping (WindowPage) -> Void,
        paneActions: PaneTabBarActions,
        pageActions: PageActions
    ) {
        self.settings = settings
        let tabDrag = tabDrag
        right = RightPaneController(
            store: store,
            settings: settings,
            engine: engine,
            windowID: windowID,
            registry: registry,
            paneActions: paneActions,
            pageActions: pageActions,
            tabDrag: tabDrag
        )
        super.init(nibName: nil, bundle: nil)
        // La cornice al posto del divider: va impostata prima di aggiungere gli item.
        splitView = FrameSplitView()
        splitView.isVertical = true

        let sidebar = NSHostingController(
            rootView: SidebarView(
                store: store,
                settings: settings,
                windowID: windowID,
                onNewWorkspace: onNewWorkspace,
                onCloseWorkspace: onCloseWorkspace,
                onCloseProject: onCloseProject,
                onDeactivateSessions: onDeactivateSessions,
                onMoveWorkspaceToNewWindow: onMoveWorkspaceToNewWindow,
                onRegenerateName: onRegenerateWorkspaceName,
                onShowPalette: onShowPalette,
                onShowPage: onShowPage,
                updateConfig: updateConfig,
                tabDrag: tabDrag
            )
        )
        // L'header della sidebar vive sulla riga dei semafori (full-size content view): niente
        // safe area, il layout la gestisce con l'inset esplicito.
        sidebar.safeAreaRegions = []
        // Item normale, non `sidebarWithViewController:`: su macOS 26 quello stila la sidebar come
        // pannello glass flottante con il **suo** materiale, non il tema del terminale. La card
        // qui è nostra: stessa forma, colori dal tema (`CardContainerController`).
        let gap = FrameSplitView.gap
        sidebarCard = CardContainerController(
            content: sidebar, insets: .init(top: gap, leading: gap, bottom: gap, trailing: 0)
        )
        let item = NSSplitViewItem(viewController: sidebarCard)
        item.minimumThickness = CGFloat(AppSettings.minSidebarWidth)
        item.maximumThickness = CGFloat(AppSettings.maxSidebarWidth)
        // Il resize della finestra va al body: la sidebar tiene la sua larghezza.
        item.holdingPriority = NSLayoutConstraint.Priority(260)
        item.canCollapse = true
        sidebarItem = item
        addSplitViewItem(item)

        contentCard = CardContainerController(
            content: right, insets: .init(top: gap, leading: 0, bottom: gap, trailing: gap)
        )
        addSplitViewItem(NSSplitViewItem(viewController: contentCard))
        observeTheme()

        observeSidebarState()
    }

    /// Il fantasma della tab in volo, da montare sopra tutta la finestra mentre il drag è fuori
    /// dalla strip: lo costruisce qui chi ha già tema e sessione.
    func makeDragGhostView() -> NSView {
        let host = NSHostingView(rootView: TabDragGhost(session: tabDrag, settings: settings))
        host.safeAreaRegions = []
        return host
    }

    /// Inoltra la query "processo in foreground" della tab al right pane (registry delle surface).
    /// Usata dalla conferma di chiusura nell'AppController.
    func foregroundProcess(for tabID: UUID) -> String? {
        right.foregroundProcess(for: tabID)
    }

    /// Inoltra la query "argv in foreground" della tab al right pane. Usata dalla nomina automatica
    /// del workspace nell'AppController (poll di "cosa stai facendo").
    func foregroundCommandLine(for tabID: UUID) -> [String]? {
        right.foregroundCommandLine(for: tabID)
    }

    /// Cwd migliore nota della tab, includendo il fallback al processo shell quando OSC 7 manca.
    func currentDirectory(for tabID: UUID) -> String? {
        right.currentDirectory(for: tabID)
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

    /// Riporta il focus al terminale attivo (dopo la chiusura di un overlay o di una pagina).
    func focusTerminal() {
        right.focusTerminal()
    }

    /// Inietta un comando nella surface di una tab (play dell'update). Inoltra al right pane.
    func sendText(to tabID: UUID, _ text: String) {
        right.sendText(to: tabID, text)
    }

    /// Il pane (e la sua tab) che possiede l'evento (mark-read filtrato + click-to-focus).
    /// Inoltra al right pane.
    func owningPane(of event: NSEvent) -> (paneID: UUID, tabID: UUID)? {
        right.owningPane(of: event)
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
            // Senza sidebar la card del contenuto prende il margine sinistro dalla cornice.
            contentCard.setLeadingInset(collapsed ? FrameSplitView.gap : 0)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSidebarState() }
        }
    }

    /// La cornice segue il tema: è il fondo del terminale un gradino più scuro (vedi
    /// `RelayTheme.chromeFrame`). Si ri-arma sui cambi di tema.
    private func observeTheme() {
        withObservationTracking {
            let theme = settings.theme
            let frame = NSColor(relay: theme.chromeFrame)
            (splitView as? FrameSplitView)?.frameColor = frame
            splitView.wantsLayer = true
            splitView.layer?.backgroundColor = frame.cgColor
            let background = NSColor(relay: theme.background)
            sidebarCard.applyTheme(background: background, isDark: theme.isDark)
            contentCard.applyTheme(background: background, isDark: theme.isDark)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTheme() }
        }
    }
}
