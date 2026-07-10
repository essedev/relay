import AppKit
import Core
import Observation
import TerminalEngine
import WorkspaceModel

/// Area AppKit che mostra i terminali del workspace attivo **di una finestra**: un pane per ogni
/// tab
/// montata, disposti secondo `Workspace.splitLayout`. Osserva lo store e ricostruisce l'albero di
/// view solo quando la sua *struttura* cambia; il drag di un divider riscrive solo i rapporti.
/// Solo i terminali: tab bar e sidebar sono pannelli SwiftUI separati (confine AppKit/SwiftUI).
@MainActor
public final class WorkspaceAreaController: NSViewController {
    let store: WorkspaceStore // internal: letto dal reconcile dell'albero (+PaneTree)
    let settings: AppSettings
    let registry: SurfaceRegistry
    /// La finestra a cui appartiene quest'area: mostra il workspace **che quella finestra ha
    /// selezionato**, non quello globale (due finestre mostrano due workspace insieme).
    let windowID: UUID
    let container = NSView()
    /// I pane montati, per tab. Chiave del riuso fra un reconcile e l'altro: rimontare una tab non
    /// deve ricrearne la surface, o il pty morirebbe.
    var panes: [UUID: PaneView] = [:]
    /// Struttura attualmente a schermo, per decidere se ricostruire (vedi `hasSameStructure`).
    var mountedTree: SplitNode?
    /// Il pane che ha il focus di tastiera: il first responder cambia solo quando cambia lui.
    var focusedTabID: UUID?
    /// Ultimo stato del ring per pane: rileva l'accensione di un completamento per il flash.
    var lastRingStates: [UUID: RingState] = [:]
    /// Stiamo applicando i rapporti alle `NSSplitView`: le callback di resize che ne derivano non
    /// devono rimbalzare nello store (sarebbe un loop, e sovrascriverebbe il ratio salvato).
    var isApplyingRatios = false

    /// Un divider è stato trascinato: il composition root scrive il nuovo rapporto nello store, che
    /// lo persiste. Iniettato perché l'area **mostra** il layout, non lo muta.
    public var onRatioChange: ((UUID, Double) -> Void)?

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
        guard let tabID = focusedTab?.id, let pane = panes[tabID] else { return }
        view.window?.makeFirstResponder(pane.terminalView)
    }

    /// La tab del pane che possiede l'evento, `nil` se non appartiene a nessun terminale in vista.
    /// Guida il mark-read: solo un uso **reale** del terminale (un tasto mentre ha il focus, o un
    /// click dentro la sua view) dice che hai visto quella conversazione. Un click di navigazione
    /// nella chrome o un tasto in un campo di rename non conta: quelle view non stanno in un pane.
    /// Con lo split serve sapere **quale** pane, perché l'evento può cadere su uno non focused.
    public func owningTab(of event: NSEvent) -> UUID? {
        guard let window = view.window, event.window === window else { return nil }
        switch event.type {
        case .keyDown:
            guard let responder = window.firstResponder as? NSView else { return nil }
            return panes.values.first { $0.owns(responder: responder) }?.tabID
        case .leftMouseDown:
            let point = event.locationInWindow
            return panes.values.first { $0.containsInTerminal(windowPoint: point) }?.tabID
        default:
            return nil
        }
    }

    /// Surface attualmente vive (strumentazione di performance, misure M3).
    public var liveSurfaceCount: Int {
        registry.liveSurfaceCount
    }

    /// Le tab a schermo in quest'area, una per pane. Interno: lo usano i test del reconcile, che
    /// senza AppKit vivo non possono ispezionare la gerarchia di view.
    var mountedTabIDs: Set<UUID> {
        Set(panes.keys)
    }

    /// La view del terminale montata per una tab (identità stabile: il riuso dei pane si verifica
    /// controllando che sia la **stessa** istanza dopo un reconcile).
    func mountedTerminal(for tabID: UUID) -> NSView? {
        panes[tabID]?.terminalView
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
        let focused = workspace.selectedTabID
        // Col pane singolo non c'è un focus da indicare: il bordo resta spento.
        let showsFocusBorder = workspace.splitLayout != nil
        for tabID in workspace.mountedTabIDs {
            guard let pane = panes[tabID],
                  let tab = workspace.tabs.first(where: { $0.id == tabID }) else { continue }
            let state = ringState(for: tab)
            if let spec = ringSpec(state, theme: theme) {
                pane.updateRing(color: spec.color, pulsing: spec.pulsing)
            } else {
                pane.updateRing(color: nil, pulsing: false)
            }
            // Un completamento appena acceso fa un flash per richiamare l'occhio.
            if state == .completed, lastRingStates[tabID] != .completed {
                pane.flashRing()
            }
            lastRingStates[tabID] = state
            let focusColor = showsFocusBorder && tabID == focused
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
