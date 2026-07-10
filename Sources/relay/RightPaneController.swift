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
    private let onNewTab: () -> Void
    private let onCloseTab: (WorkspaceModel.Tab, Workspace) -> Void
    private let onMoveTabToNewWorkspace: (WorkspaceModel.Tab, Workspace) -> Void
    private var resumeBarHost: NSView?
    private let findModel = FindModel()
    private var findBarHost: NSView?
    /// Top dell'area terminale: pinnato a `tabBar` senza barra, alla barra quando c'è (così la
    /// barra spinge giù il terminale invece di coprirlo). Riferimenti stabili per lo swap.
    private var tabBar: NSView!
    private var areaTopConstraint: NSLayoutConstraint!
    private lazy var area = WorkspaceAreaController(
        store: store,
        engine: engine,
        settings: settings
    )

    init(
        store: WorkspaceStore,
        settings: AppSettings,
        engine: TerminalEngine,
        onNewTab: @escaping () -> Void,
        onCloseTab: @escaping (WorkspaceModel.Tab, Workspace) -> Void,
        onMoveTabToNewWorkspace: @escaping (WorkspaceModel.Tab, Workspace) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.engine = engine
        self.onNewTab = onNewTab
        self.onCloseTab = onCloseTab
        self.onMoveTabToNewWorkspace = onMoveTabToNewWorkspace
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

    /// L'evento appartiene al terminale in vista (mark-read filtrato). Inoltra all'area.
    func terminalOwns(_ event: NSEvent) -> Bool {
        area.terminalOwns(event)
    }

    // MARK: - Ricerca (Cmd+F)

    /// Mostra o chiude la find bar (overlay flottante sul terminale).
    func toggleFind() {
        if findBarHost == nil { showFindBar() } else { closeFind() }
    }

    /// Find next/prev: apre la find bar se chiusa (poi cerchi digitando), altrimenti scorre.
    func findStep(forward: Bool) {
        if findBarHost == nil { showFindBar() } else { runSearch(forward: forward) }
    }

    private func showFindBar() {
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
        guard findBarHost != nil else { return }
        let result = area.searchActive(findModel.query, forward: forward)
        findModel.current = result.current
        findModel.total = result.total
    }

    private func closeFind() {
        guard let host = findBarHost else { return }
        area.endSearchActive()
        host.removeFromSuperview()
        findBarHost = nil
        findModel.query = ""
        findModel.resetCounts()
        area.focusTerminal() // il focus torna al terminale
    }

    /// Surface vive nell'area (strumentazione di performance, misure M3).
    var liveSurfaceCount: Int {
        area.liveSurfaceCount
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Strip del titolo in cima al right pane: stessa riga verticale dei semafori (full-size
        // content view), centrata sul body e non sull'intera finestra.
        let titleBar = NSHostingView(
            rootView: ContextTitleBar(store: store, settings: settings)
        )
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        // Il layout della chrome è esplicito (constraint dal top della finestra): senza questo,
        // SwiftUI applicherebbe la safe area della title bar spingendo il contenuto in basso.
        titleBar.safeAreaRegions = []

        let tabBar = NSHostingView(
            rootView: TabBarView(
                store: store,
                settings: settings,
                onNewTab: onNewTab,
                onCloseTab: onCloseTab,
                onMoveTabToNewWorkspace: onMoveTabToNewWorkspace
            )
        )
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.safeAreaRegions = []
        self.tabBar = tabBar

        addChild(area)
        let areaView = area.view
        areaView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleBar)
        view.addSubview(tabBar)
        view.addSubview(areaView)
        areaTopConstraint = areaView.topAnchor.constraint(equalTo: tabBar.bottomAnchor)
        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: view.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: Theme.Metrics.titleBarHeight),
            tabBar.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: Theme.Metrics.tabBarHeight),
            areaTopConstraint,
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
        view.addSubview(host)
        // La barra è una riga vera tra tab bar e terminale: ripinta il top dell'area sotto di lei,
        // così spinge giù il terminale invece di coprirne la prima riga.
        areaTopConstraint.isActive = false
        areaTopConstraint = area.view.topAnchor.constraint(equalTo: host.bottomAnchor)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
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
        // Ripristina il terminale attaccato alla tab bar.
        areaTopConstraint.isActive = false
        areaTopConstraint = area.view.topAnchor.constraint(equalTo: tabBar.bottomAnchor)
        areaTopConstraint.isActive = true
    }
}
