import AppKit
import Observation
import Panels
import SwiftUI
import TerminalEngine
import TerminalHostUI
import WorkspaceModel

/// Area destra: tab bar (SwiftUI, isolata) sopra, terminale della tab attiva (AppKit) sotto, più la
/// barra di resume (Panels) overlaid quando la tab selezionata ha una sessione da riprendere.
@MainActor
final class RightPaneController: NSViewController {
    private let store: WorkspaceStore
    private let settings: AppSettings
    private let engine: TerminalEngine
    private let onCloseTab: (WorkspaceModel.Tab, Workspace) -> Void
    private var resumeBarHost: NSView?
    private lazy var area = WorkspaceAreaController(
        store: store,
        engine: engine,
        settings: settings
    )

    init(
        store: WorkspaceStore,
        settings: AppSettings,
        engine: TerminalEngine,
        onCloseTab: @escaping (WorkspaceModel.Tab, Workspace) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.engine = engine
        self.onCloseTab = onCloseTab
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

    override func viewDidLoad() {
        super.viewDidLoad()

        // Strip del titolo in cima al right pane: stessa riga verticale dei semafori (full-size
        // content view), centrata sul body e non sull'intera finestra.
        let titleBar = NSHostingView(
            rootView: ContextTitleBar(
                store: store,
                settings: settings,
                onDoubleClick: { TitleBarActions.handleDoubleClick(in: NSApp.keyWindow) }
            )
        )
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        // Il layout della chrome è esplicito (constraint dal top della finestra): senza questo,
        // SwiftUI applicherebbe la safe area della title bar spingendo il contenuto in basso.
        titleBar.safeAreaRegions = []

        let tabBar = NSHostingView(
            rootView: TabBarView(store: store, settings: settings, onCloseTab: onCloseTab)
        )
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

        observeResume()
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
        guard let tab = store.selectedWorkspace?.selectedTab,
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
        let areaView = area.view
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: areaView.topAnchor),
            host.leadingAnchor.constraint(equalTo: areaView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: areaView.trailingAnchor),
        ])
        resumeBarHost = host
    }

    private func removeResumeBar() {
        resumeBarHost?.removeFromSuperview()
        resumeBarHost = nil
    }
}
