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

        let tabBar = NSHostingView(rootView: TabBarView(store: store, settings: settings))
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        addChild(area)
        let areaView = area.view
        areaView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBar)
        view.addSubview(areaView)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor),
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
