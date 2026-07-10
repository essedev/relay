import AppKit
import Core
import Observation
import TerminalEngine
import WorkspaceModel

/// Area AppKit che mostra i pane del workspace attivo **di una finestra**, disposti secondo
/// `Workspace.layout` (modello cmux: ogni pane ospita le sue tab, a schermo c'è la selezionata di
/// ognuno). Osserva lo store e ricostruisce l'albero di view solo quando la sua *struttura*
/// cambia; un cambio di selezione dentro un pane scambia solo il terminale attaccato, e il drag di
/// un divider riscrive solo i rapporti. Le strip di tab dei pane sono SwiftUI iniettata dal
/// composition root (`makePaneStrip`): quest'area non dipende da Panels.
@MainActor
public final class WorkspaceAreaController: NSViewController {
    let store: WorkspaceStore // internal: letto dal reconcile dell'albero (+PaneTree)
    let settings: AppSettings
    let registry: SurfaceRegistry
    /// La finestra a cui appartiene quest'area: mostra il workspace **che quella finestra ha
    /// selezionato**, non quello globale (due finestre mostrano due workspace insieme).
    let windowID: UUID
    let container = NSView()
    /// I pane montati, per `SplitPane.id`. Chiave del riuso fra un reconcile e l'altro: le surface
    /// dentro restano legate per `Tab.id` alla registry e non muoiono mai per un cambio di layout.
    var panes: [UUID: PaneView] = [:]
    /// Struttura attualmente a schermo, per decidere se ricostruire (vedi `hasSameStructure`).
    var mountedTree: SplitNode?
    /// La coppia (pane focused, sua tab selezionata) per cui abbiamo già asserito il first
    /// responder: si riprende solo quando cambia (un render scatta anche a ogni OSC 7).
    var focusedKey: FocusKey?
    /// Ultimo stato del ring per pane: rileva l'accensione di un completamento per il flash.
    var lastRingStates: [UUID: RingState] = [:]
    /// Stiamo applicando i rapporti alle `NSSplitView`: le callback di resize che ne derivano non
    /// devono rimbalzare nello store (sarebbe un loop, e sovrascriverebbe il ratio salvato).
    var isApplyingRatios = false
    /// Dimensione del container all'ultima applicazione dei rapporti: al primo layout con
    /// dimensioni vere (il boot parte 0x0) i rapporti salvati vanno riapplicati, o NSSplitView
    /// distribuirebbe 50/50 e il write-back stomperebbe il ratio persistito.
    var lastRatioSize: CGSize = .zero

    struct FocusKey: Equatable {
        let paneID: UUID
        let tabID: UUID
    }

    /// Un divider è stato trascinato: il composition root scrive il nuovo rapporto nello store, che
    /// lo persiste. Iniettato perché l'area **mostra** il layout, non lo muta.
    public var onRatioChange: ((UUID, Double) -> Void)?
    /// Factory della strip di tab di un pane (NSHostingView di Panels, creata dal composition
    /// root). `nil` (test senza chrome) = strip vuota d'altezza zero.
    public var makePaneStrip: ((UUID) -> NSView)?

    public init(
        store: WorkspaceStore,
        engine: TerminalEngine,
        settings: AppSettings,
        windowID: UUID = RelayWindow.mainID,
        registry: SurfaceRegistry? = nil
    ) {
        self.store = store
        self.settings = settings
        self.windowID = windowID
        // La registry arriva da fuori quando le finestre la condividono: una tab ha una surface
        // sola, ovunque sia montata.
        self.registry = registry ?? SurfaceRegistry(engine: engine)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("WorkspaceAreaController is programmatic-only")
    }

    override public func loadView() {
        container.wantsLayer = true
        view = container
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        observe()
        observeRing()
    }

    /// Al primo layout con dimensioni vere i rapporti salvati vanno riapplicati (vedi
    /// `lastRatioSize`); idem quando la finestra cambia dimensione, per riasserire il ratio dello
    /// store contro i drift dei min-size di NSSplitView.
    override public func viewDidLayout() {
        super.viewDidLayout()
        reapplyRatiosIfNeeded()
    }

    // MARK: - Query per tab (inoltrate alla registry)

    public func foregroundProcess(for tabID: UUID) -> String? {
        registry.foregroundProcess(for: tabID)
    }

    public func foregroundCommandLine(for tabID: UUID) -> [String]? {
        registry.foregroundCommandLine(for: tabID)
    }

    /// Cwd migliore nota per la tab: shell viva, poi l'ultimo OSC 7 noto, poi la root del workspace
    /// (precedenza in `Core.CurrentDirectory`). Serve a `Cmd+T`, che deve ereditare la cwd anche
    /// dalle shell senza integrazione OSC 7 - cioè zsh di default, vedi il tipo.
    public func currentDirectory(for tabID: UUID) -> String? {
        guard let workspace = store.workspaces.first(where: { workspace in
            workspace.tabs.contains { $0.id == tabID }
        }), let tab = workspace.tabs.first(where: { $0.id == tabID }) else { return nil }
        return CurrentDirectory.resolve(
            live: registry.currentDirectory(for: tabID),
            lastKnown: tab.currentDirectory,
            workspaceRoot: workspace.rootPath
        )
    }

    public func sendText(to tabID: UUID, _ text: String) {
        registry.sendText(to: tabID, text)
    }

    /// Le azioni "sul terminale" (`Cmd+K`, find) colpiscono il pane **focused**, non tutti i
    /// montati.
    var focusedTab: Tab? {
        store.selectedWorkspace(in: windowID)?.selectedTab
    }

    public func clearActiveTerminal() {
        guard let tabID = focusedTab?.id else { return }
        registry.clear(tabID)
    }

    public func searchActive(_ term: String, forward: Bool) -> (current: Int, total: Int) {
        guard let tabID = focusedTab?.id else { return (0, 0) }
        return registry.search(tabID, term: term, forward: forward)
    }

    public func endSearchActive() {
        guard let tabID = focusedTab?.id else { return }
        registry.endSearch(tabID)
    }

    /// Restituisce il focus al terminale del pane focused (es. dopo aver chiuso la find bar).
    public func focusTerminal() {
        guard let workspace = store.selectedWorkspace(in: windowID),
              let pane = panes[workspace.focusedPaneID],
              let terminal = pane.terminalView else { return }
        view.window?.makeFirstResponder(terminal)
    }

    /// Il pane (e la sua tab a schermo) che possiede l'evento, `nil` se non cade su nessun
    /// terminale in vista. Due consumatori: il mark-read (serve la tab: solo un uso **reale** del
    /// terminale dice che hai visto quella conversazione) e il click-to-focus (serve il pane: un
    /// click dentro un terminale deve dare il focus al suo pane, come in ogni terminale con split).
    /// Un click di navigazione nella chrome o un tasto in un campo di rename non contano: quelle
    /// view non stanno nell'area del terminale.
    public func owningPane(of event: NSEvent) -> (paneID: UUID, tabID: UUID)? {
        guard let window = view.window, event.window === window else { return nil }
        let pane: PaneView? = switch event.type {
        case .keyDown:
            (window.firstResponder as? NSView).flatMap { responder in
                panes.values.first { $0.owns(responder: responder) }
            }
        case .leftMouseDown:
            panes.values.first { $0.containsInTerminal(windowPoint: event.locationInWindow) }
        default:
            nil
        }
        guard let pane, let tabID = pane.currentTabID else { return nil }
        return (pane.paneID, tabID)
    }

    /// Surface attualmente vive (strumentazione di performance, misure M3).
    public var liveSurfaceCount: Int {
        registry.liveSurfaceCount
    }

    /// Le tab a schermo in quest'area, una per pane. Interno: lo usano i test del reconcile, che
    /// senza AppKit vivo non possono ispezionare la gerarchia di view.
    var visibleTabIDs: Set<UUID> {
        Set(panes.values.compactMap(\.currentTabID))
    }

    /// La view del terminale a schermo per una tab (identità stabile: il riuso delle surface si
    /// verifica controllando che sia la **stessa** istanza dopo un reconcile).
    func mountedTerminal(for tabID: UUID) -> NSView? {
        panes.values.first { $0.currentTabID == tabID }?.terminalView
    }

    /// Forza un reconcile sincrono. Interno: `observe()` ri-renderizza su un `Task`, che in un test
    /// sincrono non gira.
    func renderNow() {
        render()
    }

    /// Bridge Observation -> AppKit: ri-renderizza quando cambiano le proprietà osservate lette in
    /// `render()`, poi si ri-arma.
    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    // MARK: - Ring di attenzione (uno per pane)

    enum RingState: Equatable {
        case none, completed, needsInput, error
    }

    /// Bridge Observation -> ring: aggiorna il bordo di **ogni pane montato** quando cambiano stato
    /// o
    /// attention delle sue tab, il focus o il tema. Separato da `render()` perché **non** scrive
    /// `attention` (niente loop col reset della visita): un completamento su un pane in vista
    /// accende
    /// il ring senza spegnersi da solo. La visita reale la fa l'interazione (monitor key/mouse).
    private func observeRing() {
        withObservationTracking {
            updateRings()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeRing() }
        }
    }

    private func updateRings() {
        guard let workspace = store.selectedWorkspace(in: windowID) else { return }
        let theme = settings.theme
        // Col pane singolo non c'è un focus da indicare: il bordo resta spento.
        let showsFocusBorder = workspace.layout.paneIDs.count > 1
        for splitPane in workspace.layout.panes {
            guard let pane = panes[splitPane.id],
                  let tab = splitPane.selectedTabID.flatMap({ workspace.tab($0) })
            else { continue }
            let state = ringState(for: tab)
            if let spec = ringSpec(state, theme: theme) {
                pane.updateRing(color: spec.color, pulsing: spec.pulsing)
            } else {
                pane.updateRing(color: nil, pulsing: false)
            }
            // Un completamento appena acceso fa un flash per richiamare l'occhio.
            if state == .completed, lastRingStates[splitPane.id] != .completed {
                pane.flashRing()
            }
            lastRingStates[splitPane.id] = state
            let focusColor = showsFocusBorder && splitPane.id == workspace.focusedPaneID
                ? NSColor(relay: theme.cursor)
                : nil
            pane.updateFocusBorder(color: focusColor)
        }
    }

    private func ringState(for tab: Tab) -> RingState {
        switch tab.agentState {
        case .needsInput: .needsInput
        case .error: .error
        // Il ring è il segnale forte: solo `unseen`. Un sospeso (`pending`) non accende il bordo
        // (segnale quieto: badge ad anello + dashboard), altrimenti useresti la shell con un ring
        // verde permanente addosso. `unknown` come `idle`: un completamento a sessione finita resta
        // `unseen` nel reducer, e il ring deve concordare (verde + flash), come fa BadgeKind.
        case .idle, .unknown: tab.attention == .unseen ? .completed : .none
        case .running: .none
        }
    }

    private func ringSpec(
        _ state: RingState,
        theme: RelayTheme
    ) -> (color: NSColor, pulsing: Bool)? {
        switch state {
        case .none: nil
        case .completed: (NSColor(relay: theme.ansiColor(2)), false)
        case .needsInput: (NSColor(relay: theme.ansiColor(3)), true)
        case .error: (NSColor(relay: theme.ansiColor(1)), true)
        }
    }

    /// Flash dei ring accesi al ritorno in foreground: richiama l'occhio sui completamenti in
    /// vista.
    /// No-op sui pane col ring spento o già pulsante.
    public func flashAttentionRing() {
        for pane in panes.values {
            pane.flashRing()
        }
    }

    // Il reconcile dell'albero di pane (render, mount, ratio, LRU) vive in
    // `WorkspaceAreaController+PaneTree.swift`.
}
