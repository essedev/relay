import AppKit
import Panels
import SwiftUI
import TerminalEngine
import TerminalHostUI
import WorkspaceModel

/// Area destra: tab bar (SwiftUI, isolata) sopra, terminale della tab attiva (AppKit) sotto.
@MainActor
final class RightPaneController: NSViewController {
    private let store: WorkspaceStore
    private let settings: AppSettings
    private let engine: TerminalEngine
    private lazy var area = WorkspaceAreaController(
        store: store,
        engine: engine,
        settings: settings
    )

    init(store: WorkspaceStore, settings: AppSettings, engine: TerminalEngine) {
        self.store = store
        self.settings = settings
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("RightPaneController is programmatic-only")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Strip del titolo in cima al right pane: stessa riga verticale dei semafori (full-size
        // content view), centrata sul body e non sull'intera finestra.
        let titleBar = NSHostingView(
            rootView: ContextTitleBar(
                store: store,
                settings: settings,
                onDoubleClick: { TitleBarActions.handleDoubleClick(in: NSApp.keyWindow) },
                onToggleSidebar: { [settings] in settings.toggleSidebar() }
            )
        )
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        // Il layout della chrome è esplicito (constraint dal top della finestra): senza questo,
        // SwiftUI applicherebbe la safe area della title bar spingendo il contenuto in basso.
        titleBar.safeAreaRegions = []

        let tabBar = NSHostingView(rootView: TabBarView(store: store, settings: settings))
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.safeAreaRegions = []

        addChild(area)
        let areaView = area.view
        areaView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleBar)
        view.addSubview(tabBar)
        view.addSubview(areaView)
        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: view.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: Theme.Metrics.titleBarHeight),
            tabBar.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: Theme.Metrics.tabBarHeight),
            areaView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            areaView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            areaView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            areaView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
