import AppKit
import Observation
import Panels
import SwiftUI
import TerminalEngine
import TerminalHostUI
import WorkspaceModel

/// Area destra: strip del titolo (SwiftUI) sopra, pane del workspace attivo (AppKit) sotto. Ogni
/// pane porta la **sua** tab strip (modello cmux), montata dentro la `PaneView` via factory: qui
/// si costruisce la vista SwiftUI (`PaneTabBar`), l'area resta indipendente da Panels. In più la
/// barra di resume (Panels) overlaid quando la tab focused ha una sessione da riprendere.
@MainActor
final class RightPaneController: NSViewController {
    private let store: WorkspaceStore
    private let settings: AppSettings
    private let engine: TerminalEngine
    /// La finestra che ospita il pane: strip, titolo e terminali seguono la selezione **di questa
    /// finestra**, non quella globale.
    private let windowID: UUID
    private let registry: SurfaceRegistry
    private let paneActions: PaneTabBarActions
    private var resumeBarHost: NSView?
    private let findModel = FindModel()
    private var findBarHost: NSView?
    /// La tab su cui la find bar è aperta. La ricerca resta legata a **questa** tab anche se il
    /// focus si sposta, così alla chiusura pulisce quella giusta e i tasti non colpiscono un'altra
    /// tab. `nil` = find bar chiusa.
    private var findTabID: UUID?
    /// Top dell'area terminale: pinnato alla title bar senza resume bar, alla barra quando c'è
    /// (così la barra spinge giù i pane invece di coprirli). Riferimenti stabili per lo swap.
    private var titleBar: NSView!
    private var areaTopConstraint: NSLayoutConstraint!
    private lazy var area = WorkspaceAreaController(
        store: store,
        engine: engine,
        settings: settings,
        windowID: windowID,
        registry: registry // condivisa fra le finestre: una tab ha una surface sola
    )

    init(
        store: WorkspaceStore,
        settings: AppSettings,
        engine: TerminalEngine,
        windowID: UUID,
        registry: SurfaceRegistry,
        paneActions: PaneTabBarActions
    ) {
        self.store = store
        self.settings = settings
        self.engine = engine
        self.windowID = windowID
        self.registry = registry
        self.paneActions = paneActions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("RightPaneController is programmatic-only")
    }

    override func loadView() {
        view = NSView()
    }

    /// Inoltra la query "processo in foreground" della tab all'area (registry delle surface).
    func foregroundProcess(for tabID: UUID) -> String? {
        area.foregroundProcess(for: tabID)
    }

    /// Inoltra la query "argv in foreground" della tab all'area (nomina automatica del workspace).
    func foregroundCommandLine(for tabID: UUID) -> [String]? {
        area.foregroundCommandLine(for: tabID)
    }

    /// Cwd migliore nota della tab, includendo il fallback al processo shell quando OSC 7 manca.
    func currentDirectory(for tabID: UUID) -> String? {
        area.currentDirectory(for: tabID)
    }

    /// Pulisce il terminale della tab attiva (Cmd+K).
    func clearActiveTerminal() {
        area.clearActiveTerminal()
    }

    /// Flash del ring di attenzione (ritorno in foreground).
    func flashAttentionRing() {
        area.flashAttentionRing()
    }

    /// Riporta il focus al terminale attivo (dopo la chiusura di un overlay).
    func focusTerminal() {
        area.focusTerminal()
    }

    /// Inietta testo nella surface della tab (play dell'update). Inoltra all'area.
    func sendText(to tabID: UUID, _ text: String) {
        area.sendText(to: tabID, text)
    }

    /// Il pane (e la sua tab) che possiede l'evento (mark-read + click-to-focus). Inoltra all'area.
    func owningPane(of event: NSEvent) -> (paneID: UUID, tabID: UUID)? {
        area.owningPane(of: event)
    }

    // MARK: - Ricerca (Cmd+F)

    /// Mostra la find bar, o - se già aperta - le rimette il focus e ne seleziona il testo (Cmd+F a
    /// barra aperta rifocalizza, come Safari: non chiude). La chiusura è Esc o la x.
    func toggleFind() {
        if findBarHost == nil {
            showFindBar()
        } else {
            findModel.requestFocus()
        }
    }

    /// Find next/prev: apre la find bar se chiusa (poi cerchi digitando), altrimenti scorre.
    func findStep(forward: Bool) {
        if findBarHost == nil { showFindBar() } else { runSearch(forward: forward) }
    }

    private func showFindBar() {
        guard let tabID = store.selectedWorkspace(in: windowID)?.selectedTab?.id else { return }
        findTabID = tabID
        let bar = FindBar(
            model: findModel,
            theme: settings.theme,
            onSearch: { [weak self] forward in self?.runSearch(forward: forward) },
            onClose: { [weak self] in self?.closeFind() }
        )
        let host = NSHostingView(rootView: bar)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.safeAreaRegions = []
        view.addSubview(host)
        // Flotta in alto a destra dell'area terminale, senza spostare il layout.
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: area.view.topAnchor, constant: Theme.Spacing.sm),
            host.trailingAnchor.constraint(
                equalTo: area.view.trailingAnchor,
                constant: -Theme.Spacing.md
            ),
        ])
        findBarHost = host
        view.window?.makeFirstResponder(host)
    }

    private func runSearch(forward: Bool) {
        guard let findTabID else { return }
        let result = area.search(
            inTab: findTabID,
            term: findModel.query,
            options: findModel.options,
            forward: forward
        )
        findModel.current = result.current
        findModel.total = result.total
    }

    private func closeFind() {
        guard let host = findBarHost else { return }
        if let findTabID { area.endSearch(inTab: findTabID) }
        host.removeFromSuperview()
        findBarHost = nil
        findTabID = nil
        findModel.query = ""
        findModel.resetCounts()
        area.focusTerminal() // il focus torna al terminale
    }

    /// Bridge Observation -> AppKit: se la tab (o il pane) focused cambia mentre la find bar è
    /// aperta su un'altra tab, chiude la ricerca (pulendo la tab su cui era aperta). Evita una find
    /// bar orfana con contatore stantio che colpisce la tab sbagliata. Si ri-arma.
    private func observeFindTarget() {
        withObservationTracking {
            _ = store.selectedWorkspace(in: windowID)?.focusedPaneID
            _ = store.selectedWorkspace(in: windowID)?.selectedTab?.id
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.closeFindIfTargetChanged()
                self?.observeFindTarget()
            }
        }
    }

    private func closeFindIfTargetChanged() {
        guard findBarHost != nil, let findTabID else { return }
        if store.selectedWorkspace(in: windowID)?.selectedTab?.id != findTabID {
            closeFind()
        }
    }

    /// Surface vive nell'area (strumentazione di performance, misure M3).
    var liveSurfaceCount: Int {
        area.liveSurfaceCount
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Il drag di un divider torna nello store, che persiste il rapporto: l'area mostra il
        // layout, non lo muta. Il reconcile non ricostruisce nulla (la struttura non è cambiata).
        area.onRatioChange = { [weak self] branchID, ratio in
            guard let self, let workspace = store.selectedWorkspace(in: windowID) else { return }
            store.setSplitRatio(ratio, forBranch: branchID, in: workspace)
        }

        // La strip di tab di ogni pane: SwiftUI (Panels) montata dentro la PaneView (AppKit).
        // Costruita qui perché l'area non dipende da Panels; il contenuto osserva lo store e si
        // aggiorna da solo, la view resta viva finché vive il pane.
        area.makePaneStrip = { [store, settings, windowID, paneActions] paneID in
            let strip = NSHostingView(rootView: PaneTabBar(
                store: store,
                settings: settings,
                windowID: windowID,
                paneID: paneID,
                actions: paneActions
            ))
            strip.safeAreaRegions = [] // gotcha: senza, la safe area spinge il contenuto
            return strip
        }

        // Strip del titolo in cima al right pane: stessa riga verticale dei semafori (full-size
        // content view), centrata sul body e non sull'intera finestra.
        let titleBar = NSHostingView(
            rootView: ContextTitleBar(store: store, settings: settings, windowID: windowID)
        )
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        // Il layout della chrome è esplicito (constraint dal top della finestra): senza questo,
        // SwiftUI applicherebbe la safe area della title bar spingendo il contenuto in basso.
        titleBar.safeAreaRegions = []
        self.titleBar = titleBar

        addChild(area)
        let areaView = area.view
        areaView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleBar)
        view.addSubview(areaView)
        areaTopConstraint = areaView.topAnchor.constraint(equalTo: titleBar.bottomAnchor)
        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: view.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: Theme.Metrics.titleBarHeight),
            areaTopConstraint,
            areaView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            areaView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            areaView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        observeResume()
        observeFindTarget()
    }

    // MARK: - Barra di resume

    /// Bridge Observation -> AppKit: mostra/nasconde la barra quando cambia la tab selezionata, il
    /// suo `pendingResume`, il setting o il tema. Si ri-arma.
    private func observeResume() {
        withObservationTracking {
            renderResumeBar()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeResume() }
        }
    }

    private func renderResumeBar() {
        guard let tab = store.selectedWorkspace(in: windowID)?.selectedTab,
              tab.pendingResume, let binding = tab.resume
        else {
            removeResumeBar()
            return
        }
        // Auto-resume (opt-in): inietta da solo, con un piccolo ritardo per far arrivare la shell
        // al prompt. Altrimenti mostra la barra e lascia decidere all'utente.
        if settings.autoResumeAgents {
            removeResumeBar()
            let command = binding.resumeCommand
            let tabID = tab.id
            tab.resume = nil // best-effort, evita ri-innesco
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.area.sendText(to: tabID, command + "\n")
            }
            return
        }
        showResumeBar(binding: binding, tab: tab)
    }

    private func showResumeBar(binding: ResumeBinding, tab: WorkspaceModel.Tab) {
        removeResumeBar()
        let tabID = tab.id
        let bar = ResumeBar(
            label: binding.label,
            theme: settings.theme,
            onResume: { [weak self] in
                self?.area.sendText(to: tabID, binding.resumeCommand + "\n")
                tab.resume = nil
            },
            onDismiss: { tab.resume = nil }
        )
        let host = NSHostingView(rootView: bar)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.safeAreaRegions = []
        view.addSubview(host)
        // La barra è una riga vera tra title bar e area dei pane: ripinta il top dell'area sotto
        // di lei, così spinge giù i terminali invece di coprirne la prima riga.
        areaTopConstraint.isActive = false
        areaTopConstraint = area.view.topAnchor.constraint(equalTo: host.bottomAnchor)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            areaTopConstraint,
        ])
        resumeBarHost = host
    }

    private func removeResumeBar() {
        guard let host = resumeBarHost else { return }
        host.removeFromSuperview()
        resumeBarHost = nil
        // Ripristina i pane attaccati alla title bar.
        areaTopConstraint.isActive = false
        areaTopConstraint = area.view.topAnchor.constraint(equalTo: titleBar.bottomAnchor)
        areaTopConstraint.isActive = true
    }
}
