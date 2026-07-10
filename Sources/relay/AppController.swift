import AgentProtocol
import AgentRuntime
import AppKit
import Core
import HookInstaller
import LayoutStore
import Panels
import SwiftUI
import TerminalEngine
import TerminalHostUI
import WorkspaceModel

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let log = RelayLog.logger("app")
    let store = WorkspaceStore()
    let settings = AppSettings() // internal: letto dal monitor/menu delle scorciatoie
    private let engine: TerminalEngine = SwiftTermEngine()
    private lazy var agentCoordinator = AgentCoordinator(store: store)
    private lazy var layoutStore = LayoutStore(path: RelayRuntimePaths.layoutPath)
    /// **Una sola** registry per tutta l'app, condivisa fra le finestre: una tab ha una surface
    /// sola ovunque sia montata, e il cap LRU ragiona sul totale vivo, non per finestra.
    private lazy var registry = SurfaceRegistry(engine: engine)
    /// Le finestre vive, per `RelayWindow.id`. Internal: le extension lavorano su quella key.
    var windowControllers: [UUID: RelayWindowController] = [:]

    /// La finestra col focus: menu, scorciatoie e overlay agiscono su di lei. Le extension che la
    /// usano degradano a no-op quando non c'è (avvio, ultima chiusura).
    var keyWindowController: RelayWindowController? {
        windowControllers[store.keyWindowID] ?? windowControllers.values.first
    }

    var window: NSWindow? {
        keyWindowController?.window
    } // sheet di conferma chiusura
    var splitVC: MainSplitViewController? {
        keyWindowController?.splitVC
    }

    var rootController: RootOverlayController? {
        keyWindowController?.rootController
    }

    /// Presenter degli overlay full-window (dashboard/onboarding) **della finestra key**: un host
    /// per finestra, mutua esclusione per costruzione.
    var overlayPresenter: FullOverlayPresenter? {
        keyWindowController?.overlayPresenter
    }

    var settingsWindow: NSWindow? // internal: aperto/chiuso dall'extension delle impostazioni
    var aboutWindow: NSWindow? // internal: pannello "About Relay" (extension impostazioni)
    var statsWindow: NSWindow? // internal: runtime stats panel
    var runtimeStatsSampler: RuntimeStatsSampler?
    private var untitledCount = 0
    /// L'app sta chiudendo: le `windowWillClose` che seguono non devono rimpatriare i workspace
    /// (collasserebbero il layout multi-window in una finestra sola prima del flush).
    var isTerminating = false
    var keyMonitor: Any? // internal: installato dall'extension di navigazione
    /// Timer del "flash" di completamento sulla tab in vista, per tab: alla scadenza declassa il
    /// marker forte (`unseen`) a "in sospeso" (`pending`), un mark-read differito. Keyed per tab
    /// così un nuovo completamento sulla stessa tab rimpiazza il timer pendente. Internal: gestito
    /// da `scheduleCompletionFlashDecay` nell'extension di navigazione.
    var completionFlashTimers: [UUID: DispatchWorkItem] = [:]
    private var demoDriver: DemoDriver?
    /// Autosave del layout, attivo solo in modalità normale (la demo non tocca il file reale).
    private var autosave: LayoutAutosave?
    /// Strumentazione di performance, attiva solo con `RELAY_PERF=1` (misure M3).
    private var perf: PerfSampler?
    /// Notifiche macOS, attive solo quando l'app gira dal bundle `.app` (serve un bundle id).
    private var notifications: NotificationCoordinator?
    /// Check aggiornamenti (canale brew): pill in sidebar + voce di menu. No-op da `swift run`.
    private lazy var updateController = UpdateController(settings: settings)
    /// Custode della API key per la nomina automatica (file 0600 in `~/.relay`). Internal: letto
    /// dall'extension delle impostazioni.
    let namingCredentials = NamingCredentialStore()
    /// Nomina automatica dei workspace via LLM. Attiva solo fuori dalla demo; inerte senza API key.
    /// Internal: il wiring vive nell'extension `AppControllerNaming`.
    var namingController: NamingController?

    func applicationDidFinishLaunching(_: Notification) {
        log.info("relay launched")
        observeKeybindings()
        installNavigationKeyMonitor()
        configureStoreForRun()
        agentCoordinator.start()
        seedIfNeeded()

        // Una finestra per ogni `RelayWindow` del layout ripristinato (di solito una sola). La key
        // per ultima, così resta davanti.
        for relayWindow in store.windows {
            let controller = makeWindowController(for: relayWindow)
            windowControllers[relayWindow.id] = controller
            controller.show()
        }
        keyWindowController?.activate()

        observeWindowTheme()
        observeWindowTitle()

        startPerfSamplerIfEnabled()
        setupNotificationsIfBundled()
        updateController.checkOnLaunch()
        // Onboarding al primo avvio, mai in demo mode (lì l'app serve a mostrare, non a spiegare).
        if demoDriver == nil { showOnboardingIfFirstLaunch() }
    }

    /// Costruisce lo split di una finestra con le closure d'azione (create/close workspace e tab,
    /// move tab in un nuovo workspace, config sidebar). Fuori dal launch per tenerlo corto.
    func makeSplitViewController(windowID: UUID) -> MainSplitViewController {
        MainSplitViewController(
            store: store,
            settings: settings,
            engine: engine,
            windowID: windowID,
            registry: registry,
            updateConfig: updateController.makeSidebarConfig(
                onRunUpdate: { [weak self] in self?.runUpdateInTab() }
            ),
            onNewWorkspace: { [weak self] in self?.newWorkspace(nil) },
            onNewTab: { [weak self] in self?.newTab(nil) },
            onCloseWorkspace: { [weak self] workspace in self?.requestCloseWorkspace(workspace) },
            onCloseTab: { [weak self] tab, workspace in self?.requestCloseTab(tab, in: workspace) },
            onMoveTabToNewWorkspace: { [weak self] tab, workspace in
                self?.moveTabToNewWorkspace(tab, from: workspace)
            }
        )
    }

    /// Config dello store legata alla run corrente (soglie di scarto eventi + hook imperativi),
    /// fuori dal launch per tenerlo corto e raccogliere in un punto ciò che dipende dall'avvio.
    private func configureStoreForRun() {
        // Soglia anti-stantio timbrata prima di ricevere: gli eventi generati prima di questo avvio
        // sono di sessioni morte (le surface di questa run non esistono ancora) e non devono
        // azzerare i resume binding ripristinati (il RELAY_TAB_ID è stabile tra i riavvii).
        store.eventFloor = Date()
        // Fence di run: scarta anche gli eventi eseguiti *dopo* il boot ma nati da sessioni di run
        // precedenti (claude orfani sopravvissuti al riavvio), che il floor non può distinguere.
        store.runID = RelayRunID.current
        // Flash di completamento sulla tab in vista: nasce forte (unseen) e dopo qualche secondo si
        // declassa a "in sospeso". Il timer vive nel composition root (lo store puro non ne ha).
        store.onVisibleCompletion = { [weak self] tabID in
            self?.scheduleCompletionFlashDecay(for: tabID)
        }
    }

    @objc func checkForUpdates(_: Any?) {
        updateController.checkManually()
    }

    /// Notifiche macOS: solo dal bundle `.app` (`UNUserNotificationCenter` richiede un bundle id;
    /// da `swift run` crasherebbe). Aggancia l'effetto puro dello store al coordinatore.
    private func setupNotificationsIfBundled() {
        guard Bundle.main.bundleIdentifier != nil else {
            log.info("notifications off: no bundle id (usa make run-app per abilitarle)")
            return
        }
        let coordinator = NotificationCoordinator(settings: settings)
        coordinator.requestAuthorization()
        store.onNotifiableTransition = { [weak self] request in
            self?.notifications?.handle(request)
        }
        coordinator.onActivate = { [weak self] workspaceID, tabID in
            self?.activateTab(workspaceID: workspaceID, tabID: tabID)
        }
        notifications = coordinator
    }

    /// Riporta in vista la tab di una notifica cliccata: seleziona workspace+tab e porta la
    /// finestra
    /// in primo piano. Se un workspace archiviato genera una notifica lo ripristina, altrimenti la
    /// selezione punterebbe a una riga fuori dalla lista visibile.
    /// Riporta in vista la tab: `reveal` seleziona workspace+tab e **attiva la finestra che li
    /// possiede** (i workspace sono partizionati), poi la portiamo davanti.
    private func activateTab(workspaceID: UUID, tabID: UUID) {
        store.reveal(workspaceID: workspaceID, tabID: tabID)
        keyWindowController?.activate()
    }

    /// Attiva la strumentazione di performance solo su richiesta (`RELAY_PERF=1`). Legge le surface
    /// vive dallo split e ci si aggancia il timing del monitor di input.
    private func startPerfSamplerIfEnabled() {
        guard PerfSampler.isEnabled else { return }
        let perf = PerfSampler(
            store: store,
            liveSurfaceCount: { [weak self] in self?.registry.liveSurfaceCount ?? 0 },
            inputHook: { [weak self] event in _ = self?.handleNavigationKey(event) }
        )
        perf.start()
        self.perf = perf
    }

    /// Toggle sidebar: overlay a posizione fissa accanto ai semafori, sopra il contenuto. Non si
    /// muove con l'animazione del collasso (un solo bottone per aprire e chiudere).
    func makeSidebarToggleOverlay() -> NSView {
        let hosting = NSHostingView(
            rootView: SidebarToggleButton(settings: settings) { [weak self] in
                self?.settings.toggleSidebar()
            }
        )
        hosting.safeAreaRegions = []
        return hosting
    }

    /// Aggiorna il titolo nativo di **ogni** finestra (nascosto in finestra, usato da Mission
    /// Control/Cmd+Tab): ognuna nomina il workspace che mostra. La strip visibile (ContextTitleBar)
    /// legge la stessa logica via Observation.
    private func observeWindowTitle() {
        withObservationTracking {
            for (windowID, controller) in windowControllers {
                let workspace = store.selectedWorkspace(in: windowID)
                controller.window.title = WindowTitle.compose(
                    workspace: workspace, tab: workspace?.selectedTab
                )
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeWindowTitle() }
        }
    }

    // MARK: - Tema della finestra

    /// L'appearance AppKit segue il tema (darkAqua/aqua): i controlli di sistema (liste, header,
    /// bottoni) restano leggibili su qualunque background. Title bar trasparente sul background
    /// del tema, così la strip coi semafori è integrata. Si ri-arma sui cambi (Observation).
    private func observeWindowTheme() {
        withObservationTracking {
            applyWindowChrome(settings.theme)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeWindowTheme() }
        }
    }

    func applyWindowChrome(_ theme: RelayTheme) {
        let appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        let background = NSColor(relay: theme.background)
        for controller in windowControllers.values {
            controller.applyChrome(theme)
        }
        for target in [settingsWindow, aboutWindow].compactMap(\.self) {
            target.appearance = appearance
            target.titlebarAppearsTransparent = true
            target.backgroundColor = background
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    /// Tornando in primo piano, un completamento sulla tab in vista fa un flash del ring per
    /// richiamare l'occhio. Il marker **non** si spegne qui: lo fa solo l'interazione col
    /// terminale. La decadenza dei sospesi (se attiva) si applica qui: momento naturale di
    /// rientro, senza bisogno di timer.
    func applicationDidBecomeActive(_: Notification) {
        // Il flash richiama l'occhio sui completamenti in vista di **ogni** finestra, non solo la
        // key.
        for controller in windowControllers.values {
            controller.splitVC.flashAttentionRing()
        }
        applyPendingDecayIfEnabled()
    }

    func applicationWillTerminate(_: Notification) {
        isTerminating = true
        // Stop del receiver PRIMA del flush: i SessionEnd delle sessioni morenti (chiusura con la
        // X: le surface muoiono prima del terminate) sono di questa run e passerebbero il fence,
        // azzerando i resume binding proprio nello snapshot finale.
        agentCoordinator.stop()
        autosave?.flush() // flush sincrono finale (il debounce potrebbe non essere scaduto)
        perf?.stop()
        namingController?.stop()
        demoDriver?.stop()
    }

    /// All'avvio: la demo ha il suo seed e non tocca il layout persistito; altrimenti si ripristina
    /// dal disco (fallback al seed di default se manca/corrotto) e si attiva il salvataggio.
    private func seedIfNeeded() {
        if let config = DemoConfig.parse(from: CommandLine.arguments) {
            seedDemo(config)
            return
        }
        if let snapshot = layoutStore.load(), !snapshot.workspaces.isEmpty {
            store.restore(from: snapshot)
            log.info("layout restored: \(snapshot.workspaces.count) workspaces")
            applyPendingDecayIfEnabled() // i sospesi scaduti mentre l'app era chiusa
        } else if store.workspaces.isEmpty {
            createUntitledWorkspace()
        }
        let autosave = LayoutAutosave(store: store, layoutStore: layoutStore)
        autosave.start()
        self.autosave = autosave
        // Nomina automatica: solo fuori dalla demo (che ha già fatto `return`). La surface viene
        // letta lazy al poll, quindi va bene avviarla prima che lo split esista.
        setupWorkspaceNaming()
    }

    /// Demo mode: popola lo store (logica in `DemoMode`) e avvia le sessioni simulate su ogni tab.
    /// Le tab restano `unrealized` finché non le visiti: i badge vivono comunque.
    private func seedDemo(_ config: DemoConfig) {
        let tabIDs = DemoSeeder.seed(config, into: store)
        let driver = DemoDriver()
        demoDriver = driver
        driver.start(tabIDs: tabIDs)
        log.info("demo mode: \(config.workspaces) workspaces x \(config.tabsPerWorkspace) tabs")
    }

    /// Workspace senza cartella: parte da home, l'utente ci naviga con `cd`. Internal: usato
    /// dall'extension di chiusura (ripristino dell'invariante "almeno un workspace").
    func createUntitledWorkspace() {
        untitledCount += 1
        store.createWorkspace(name: "Workspace \(untitledCount)", rootPath: NSHomeDirectory())
    }

    /// Sposta una tab in un nuovo workspace placeholder ("Workspace N", eleggibile alla nomina
    /// automatica). Lo store sposta lo stesso oggetto `Tab`, quindi la surface/pty resta viva: il
    /// lavoro dentro la tab non si tocca (vedi `WorkspaceStore.moveTabToNewWorkspace`).
    func moveTabToNewWorkspace(_ tab: WorkspaceModel.Tab, from workspace: Workspace) {
        untitledCount += 1
        store.moveTabToNewWorkspace(tab.id, from: workspace, name: "Workspace \(untitledCount)")
    }

    // MARK: - Actions

    @objc func newWorkspace(_: Any?) {
        createUntitledWorkspace()
    }

    @objc func openFolderAsWorkspace(_: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.createWorkspace(name: url.lastPathComponent, rootPath: url.path)
    }

    /// La nuova tab parte dove stai lavorando: la cwd la risolve l'area (shell viva > OSC 7 > root
    /// del workspace), qui c'è solo il wiring. Il risultato **non** si scrive su
    /// `Tab.currentDirectory`, che è l'ultimo OSC 7 noto e alimenta anche titolo, sottotitolo e
    /// snapshot: una cwd letta dal processo li congelerebbe a quella dell'ultimo `Cmd+T`.
    @objc func newTab(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        let cwd = workspace.selectedTab.flatMap { splitVC?.currentDirectory(for: $0.id) }
        store.addTab(to: workspace, currentDirectory: cwd ?? workspace.rootPath)
    }

    @objc func zoomIn(_: Any?) {
        settings.adjustFontSize(by: 1)
    }

    @objc func zoomOut(_: Any?) {
        settings.adjustFontSize(by: -1)
    }

    @objc func resetZoom(_: Any?) {
        settings.resetFontSize()
    }

    @objc func toggleSidebar(_: Any?) {
        settings.toggleSidebar()
    }

    @objc func closeCurrentTab(_: Any?) {
        guard let workspace = store.selectedWorkspace,
              let tab = workspace.selectedTab else { return }
        requestCloseTab(tab, in: workspace)
    }

    // MARK: - Menu

    /// Ricostruisce il menu quando cambia un keybinding (i titoli portano la combo), e si ri-arma.
    private func observeKeybindings() {
        withObservationTracking {
            NSApp.mainMenu = MainMenuBuilder.build(target: self, settings: settings)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeKeybindings() }
        }
    }
}
