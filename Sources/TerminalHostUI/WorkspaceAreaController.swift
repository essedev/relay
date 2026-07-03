import AppKit
import Core
import Observation
import TerminalEngine
import WorkspaceModel

/// Area AppKit che mostra il terminale della tab attualmente selezionata. Osserva lo store e
/// scambia la surface quando cambia workspace o tab. Solo il terminale: la tab bar e la sidebar
/// sono pannelli SwiftUI separati (confine AppKit/SwiftUI di ARCHITECTURE).
@MainActor
public final class WorkspaceAreaController: NSViewController {
    private let store: WorkspaceStore
    private let settings: AppSettings
    private let registry: SurfaceRegistry
    private let container = NSView()
    private var currentTerminal: NSView?
    private let attentionRing = AttentionRingView(frame: .zero)
    /// Ultimo stato del ring: rileva l'accensione di un completamento per il flash.
    private var lastRingState: RingState = .none

    public init(store: WorkspaceStore, engine: TerminalEngine, settings: AppSettings) {
        self.store = store
        self.settings = settings
        registry = SurfaceRegistry(engine: engine)
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
        mountAttentionRing()
        observe()
        observeRing()
    }

    /// Il ring di attenzione copre l'intera zona (il gap dal bordo lo dà il suo `strokeInset`),
    /// più esterno del terminale, che è inset di più: fra i due resta l'aria contenuto-ring.
    /// Overlay decorativo (`hitTest` nil): il terminale sotto riceve gli eventi. I terminali si
    /// inseriscono sotto di lui (`setTerminal`), così resta sempre in cima senza ri-montarlo.
    private func mountAttentionRing() {
        attentionRing.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(attentionRing)
        // Il ring copre l'intera zona (il gap dal bordo lo dà `strokeInset`): sta più esterno del
        // terminale, che è inset di più, così resta aria tra contenuto e ring.
        NSLayoutConstraint.activate([
            attentionRing.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            attentionRing.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            attentionRing.topAnchor.constraint(equalTo: container.topAnchor),
            attentionRing.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Nome del comando in foreground nella tab (o `nil` se al prompt / non realizzata). Inoltra
    /// alla registry; usato dalla conferma di chiusura nel composition root.
    public func foregroundProcess(for tabID: UUID) -> String? {
        registry.foregroundProcess(for: tabID)
    }

    /// Inietta testo nella surface della tab (resume dell'agente). Inoltra alla registry.
    public func sendText(to tabID: UUID, _ text: String) {
        registry.sendText(to: tabID, text)
    }

    /// Pulisce il terminale della tab attiva (Cmd+K).
    public func clearActiveTerminal() {
        guard let tabID = store.selectedWorkspace?.selectedTab?.id else { return }
        registry.clear(tabID)
    }

    /// Cerca nel terminale della tab attiva; ritorna posizione/totale per il contatore.
    public func searchActive(_ term: String, forward: Bool) -> (current: Int, total: Int) {
        guard let tabID = store.selectedWorkspace?.selectedTab?.id else { return (0, 0) }
        return registry.search(tabID, term: term, forward: forward)
    }

    /// Termina la ricerca nella tab attiva (pulisce selezione e stato).
    public func endSearchActive() {
        guard let tabID = store.selectedWorkspace?.selectedTab?.id else { return }
        registry.endSearch(tabID)
    }

    /// Restituisce il focus al terminale attivo (es. dopo aver chiuso la find bar).
    public func focusTerminal() {
        guard let terminal = currentTerminal else { return }
        view.window?.makeFirstResponder(terminal)
    }

    /// Surface attualmente vive (per la strumentazione di performance, misure M3).
    public var liveSurfaceCount: Int {
        registry.liveSurfaceCount
    }

    /// Bridge Observation -> AppKit: ri-renderizza quando cambiano le proprietà osservate lette
    /// in `render()`, poi si ri-arma.
    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    // MARK: - Ring di attenzione

    /// Stato del ring per la tab in vista. Coerente con `BadgeKind.forTab` (Panels): completato
    /// dipende da `attention`; needs_input/error sono stati persistenti.
    private enum RingState: Equatable {
        case none, completed, needsInput, error
    }

    /// Bridge Observation -> ring: aggiorna il bordo quando cambia stato/attention della tab in
    /// vista, la selezione o il tema. Separato da `observe()` perché **non** scrive `attention`
    /// (niente loop col reset della visita): un completamento sulla tab già in vista accende il
    /// ring
    /// senza spegnersi da solo. La visita reale la fa l'interazione (`surface.onInteraction`).
    private func observeRing() {
        withObservationTracking {
            updateRing()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeRing() }
        }
    }

    private func updateRing() {
        let state = ringState(for: store.selectedWorkspace?.selectedTab)
        if let spec = ringSpec(state, theme: settings.theme) {
            attentionRing.update(color: spec.color, pulsing: spec.pulsing)
        } else {
            attentionRing.update(color: nil, pulsing: false)
        }
        // Un completamento appena acceso fa un flash per richiamare l'occhio.
        if state == .completed, lastRingState != .completed {
            attentionRing.flash()
        }
        lastRingState = state
    }

    private func ringState(for tab: Tab?) -> RingState {
        guard let tab else { return .none }
        switch tab.agentState {
        case .needsInput: return .needsInput
        case .error: return .error
        // Il ring è il segnale forte: solo `unseen`. Un sospeso (`pending`) non accende il bordo
        // (segnale quieto: badge dimesso + dashboard), altrimenti userei la shell con un ring
        // verde permanente addosso.
        case .idle: return tab.attention == .unseen ? .completed : .none
        case .running, .unknown: return .none
        }
    }

    /// Colore (dai colori ANSI del tema, come i badge) e se pulsa. Completato = verde statico;
    /// aspetta-input = giallo pulsante; errore = rosso pulsante.
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

    /// Flash del ring al ritorno in foreground: richiama l'occhio su un completamento in vista.
    /// No-op se il ring è spento o pulsa già.
    public func flashAttentionRing() {
        attentionRing.flash()
    }

    private func render() {
        // Legge settings.theme: entra nel tracking, così un cambio tema/zoom ri-renderizza e
        // propaga il tema alle surface vive (no-op se invariato).
        registry.applyTheme(settings.theme)

        let aliveTabIDs = Set(store.workspaces.flatMap { $0.tabs.map(\.id) })
        registry.retain(aliveTabIDs)

        guard let workspace = store.selectedWorkspace, let tab = workspace.selectedTab else {
            setTerminal(nil)
            return
        }

        // Nota: selezionare la tab **non** spegne più `attention` (lo faceva il vecchio modello).
        // Aprire una tab completata mostra il ring verde + flash; il mark-read lo fa solo
        // l'interazione col terminale (monitor key/mouse). Vedi observeRing / gotcha attention.

        // La shell parte dalla cwd della tab (ereditata da Cmd+T o nota via OSC 7), fallback
        // sulla cartella del workspace.
        let surface = registry.surface(
            for: tab.id,
            cwd: tab.currentDirectory ?? workspace.rootPath,
            onTitle: { [weak tab] title in
                guard let tab, !tab.hasCustomTitle else { return }
                tab.title = title
            },
            onDirectory: { [weak tab] path in
                tab?.currentDirectory = path
            }
        )
        setTerminal(surface.view)
        surface.start()
        view.window?.makeFirstResponder(surface.view)

        // Cap LRU: dopo aver reso viva la tab corrente, sfratta le surface idle meno recenti oltre
        // il cap (mai la visibile né quelle con lavoro vivo). Rinascono lazy al re-focus.
        registry.enforceLRU(cap: liveSurfaceCap, keep: tab.id)
    }

    /// Massimo di surface vive tenute in memoria. Default 12, tarato sulle misure di memoria (M3,
    /// `docs/research/PERF.md`): ~0.3-0.5 MB per surface idle, 12 surface stanno ampiamente nel
    /// budget. Override via `RELAY_SURFACE_CAP` (le misure lo usano per esplorare la pendenza).
    private let liveSurfaceCap: Int = {
        let raw = ProcessInfo.processInfo.environment["RELAY_SURFACE_CAP"].flatMap(Int.init) ?? 0
        return raw > 0 ? raw : 12
    }()

    /// Respiro attorno al testo del terminale (il container ha lo stesso background del tema,
    /// quindi
    /// il padding è aria, non una cornice). Più largo del `strokeInset` del ring: lo spazio tra i
    /// due
    /// è l'aria fra contenuto e ring.
    private static let terminalInset: CGFloat = 12

    private func setTerminal(_ terminal: NSView?) {
        guard currentTerminal !== terminal else { return }
        currentTerminal?.removeFromSuperview()
        currentTerminal = terminal
        guard let terminal else { return }
        terminal.translatesAutoresizingMaskIntoConstraints = false
        // Sotto il ring di attenzione, che resta l'overlay in cima.
        container.addSubview(terminal, positioned: .below, relativeTo: attentionRing)
        let inset = Self.terminalInset
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
    }
}
