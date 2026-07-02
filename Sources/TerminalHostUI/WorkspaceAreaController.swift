import AppKit
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
        observe()
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

        // Visita: la tab in vista non ha più novità da segnalare. `attention` non è letta qui,
        // quindi la scrittura aggiorna i badge senza ri-armare questo observe (nessun loop).
        tab.attention = false

        let surface = registry.surface(
            for: tab.id,
            cwd: workspace.rootPath,
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
    }

    private func setTerminal(_ terminal: NSView?) {
        guard currentTerminal !== terminal else { return }
        currentTerminal?.removeFromSuperview()
        currentTerminal = terminal
        guard let terminal else { return }
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
