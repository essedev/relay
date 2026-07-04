import AgentProtocol
import AgentRuntime
import AppKit
import Core
import LayoutStore
import Panels
import SwiftUI
import TerminalEngine
import WorkspaceModel

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let log = RelayLog.logger("app")
    let store = WorkspaceStore()
    let settings = AppSettings() // internal: letto dal monitor/menu delle scorciatoie
    private let engine: TerminalEngine = SwiftTermEngine()
    private lazy var agentCoordinator = AgentCoordinator(store: store)
    private lazy var layoutStore = LayoutStore(path: RelayRuntimePaths.layoutPath)
    private var window: NSWindow!
    var splitVC: MainSplitViewController! // internal: usato dalle extension in altri file
    var rootController: RootOverlayController! // internal: overlay dashboard (extension)
    /// Host dell'overlay dashboard quando è aperta (`nil` = chiusa). Vedi AppControllerDashboard.
    var dashboardHost: NSView?
    private var settingsWindow: NSWindow?
    private var untitledCount = 0
    var keyMonitor: Any? // internal: installato dall'extension di navigazione
    private var demoDriver: DemoDriver?
    /// Autosave del layout, attivo solo in modalità normale (la demo non tocca il file reale).
    private var autosave: LayoutAutosave?
    /// Strumentazione di performance, attiva solo con `RELAY_PERF=1` (misure M3).
    private var perf: PerfSampler?
    /// Notifiche macOS, attive solo quando l'app gira dal bundle `.app` (serve un bundle id).
    private var notifications: NotificationCoordinator?

    func applicationDidFinishLaunching(_: Notification) {
        log.info("relay launched")
        observeKeybindings()
        installNavigationKeyMonitor()
        agentCoordinator.start()
        seedIfNeeded()

        let onNewWorkspace: () -> Void = { [weak self] in self?.newWorkspace(nil) }
        let split = MainSplitViewController(
            store: store,
            settings: settings,
            engine: engine,
            onNewWorkspace: onNewWorkspace,
            onCloseWorkspace: { [weak self] workspace in self?.requestCloseWorkspace(workspace) },
            onCloseTab: { [weak self] tab, workspace in self?.requestCloseTab(tab, in: workspace) }
        )
        splitVC = split

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Relay"
        // Sotto questa soglia sidebar + terminale non hanno più spazio utile: la sidebar tiene la
        // sua larghezza minima (200) e al terminale resta abbastanza per lavorare.
        window.contentMinSize = NSSize(width: 700, height: 460)
        // Il contenuto sale fino al bordo: il titolo visibile è la strip del right pane
        // (ContextTitleBar), centrata sul body. Il title nativo resta per Mission Control/Cmd+Tab.
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // Niente drag dal corpo: la finestra si sposta solo dalle strip in alto (title bar
        // custom), rese trascinabili con `WindowDragArea`. Vedi ContextTitleBar/SidebarView.
        window.isMovableByWindowBackground = false
        let root = RootOverlayController(content: split, overlay: makeSidebarToggleOverlay())
        rootController = root
        split.onSidebarWidthChange = { [weak root] width in
            root?.sidebarWidthDidChange(width)
        }
        window.contentViewController = root
        window.setFrameAutosaveName("RelayMainWindow")
        window.center()
        observeWindowTheme()
        observeWindowTitle()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startPerfSamplerIfEnabled()
        setupNotificationsIfBundled()
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
        notifications = coordinator
    }

    /// Attiva la strumentazione di performance solo su richiesta (`RELAY_PERF=1`). Legge le surface
    /// vive dallo split e ci si aggancia il timing del monitor di input.
    private func startPerfSamplerIfEnabled() {
        guard PerfSampler.isEnabled else { return }
        let perf = PerfSampler(
            store: store,
            liveSurfaceCount: { [weak splitVC] in splitVC?.liveSurfaceCount ?? 0 },
            inputHook: { [weak self] event in _ = self?.handleNavigationKey(event) }
        )
        perf.start()
        self.perf = perf
    }

    /// Toggle sidebar: overlay a posizione fissa accanto ai semafori, sopra il contenuto. Non si
    /// muove con l'animazione del collasso (un solo bottone per aprire e chiudere).
    private func makeSidebarToggleOverlay() -> NSView {
        let hosting = NSHostingView(
            rootView: SidebarToggleButton(settings: settings) { [weak self] in
                self?.settings.toggleSidebar()
            }
        )
        hosting.safeAreaRegions = []
        return hosting
    }

    /// Aggiorna il titolo nativo (nascosto in finestra, usato da Mission Control/Cmd+Tab).
    /// La strip visibile (ContextTitleBar) legge la stessa logica via Observation.
    private func observeWindowTitle() {
        withObservationTracking {
            let workspace = store.selectedWorkspace
            window.title = WindowTitle.compose(workspace: workspace, tab: workspace?.selectedTab)
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

    private func applyWindowChrome(_ theme: RelayTheme) {
        let appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        let background = NSColor(relay: theme.background)
        for target in [window, settingsWindow].compactMap(\.self) {
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
        splitVC?.flashAttentionRing()
        applyPendingDecayIfEnabled()
    }

    func applicationWillTerminate(_: Notification) {
        autosave?.flush() // flush sincrono finale (il debounce potrebbe non essere scaduto)
        perf?.stop()
        demoDriver?.stop()
        agentCoordinator.stop()
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

    /// Workspace senza cartella: parte da home, l'utente ci naviga con `cd`.
    private func createUntitledWorkspace() {
        untitledCount += 1
        store.createWorkspace(name: "Workspace \(untitledCount)", rootPath: NSHomeDirectory())
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

    @objc func newTab(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        store.addTab(to: workspace)
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

    @objc func openSettings(_: Any?) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        hosting.preferredContentSize = NSSize(width: 580, height: 400)
        let panel = NSWindow(contentViewController: hosting)
        panel.title = "Settings"
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.center()
        settingsWindow = panel
        applyWindowChrome(settings.theme) // appearance/background coerenti da subito
        panel.makeKeyAndOrderFront(nil)
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

// MARK: - Chiusura con conferma

/// Chiusura di tab e workspace con conferma quando c'è lavoro in corso. Vive in extension per
/// tenere il corpo di `AppController` sul solo wiring: la policy (quando chiedere) e la
/// presentazione (l'alert) stanno qui.
extension AppController {
    /// Chiude una tab, chiedendo conferma se nel suo pty gira un comando in foreground (build,
    /// ssh, Claude...). Shell al prompt o tab mai realizzata -> chiude subito. Lo stato agente
    /// arricchisce solo il messaggio. Chiudere l'ultima tab chiude il workspace (cascade nello
    /// store): quel caso è già coperto dalla conferma della tab, niente doppio prompt.
    func requestCloseTab(_ tab: WorkspaceModel.Tab, in workspace: Workspace) {
        guard let process = splitVC.foregroundProcess(for: tab.id) else {
            performCloseTab(tab, in: workspace)
            return
        }
        confirmClose(
            title: "Chiudere la tab «\(tab.title)»?",
            info: closeInfo(process: process, agentState: tab.agentState)
        ) { [weak self] in
            self?.performCloseTab(tab, in: workspace)
        }
    }

    /// Chiude un workspace, chiedendo conferma se una qualsiasi delle sue tab ha un comando in
    /// foreground.
    func requestCloseWorkspace(_ workspace: Workspace) {
        let busy = workspace.tabs.filter { splitVC.foregroundProcess(for: $0.id) != nil }
        guard !busy.isEmpty else {
            performCloseWorkspace(workspace)
            return
        }
        let info = busy.count == 1
            ? "1 tab ha un processo in esecuzione, che verrà terminato."
            : "\(busy.count) tab hanno processi in esecuzione, che verranno terminati."
        confirmClose(
            title: "Chiudere il workspace «\(workspace.name)»?",
            info: info
        ) { [weak self] in
            self?.performCloseWorkspace(workspace)
        }
    }

    /// Esegue la chiusura effettiva, poi ripristina l'invariante "almeno un workspace": chiudere
    /// l'ultima tab (cascade sul workspace) o l'ultimo workspace ne apre subito uno default, così
    /// la finestra non resta mai vuota.
    private func performCloseTab(_ tab: WorkspaceModel.Tab, in workspace: Workspace) {
        store.closeTab(tab.id, in: workspace)
        ensureAtLeastOneWorkspace()
    }

    private func performCloseWorkspace(_ workspace: Workspace) {
        store.closeWorkspace(workspace.id)
        ensureAtLeastOneWorkspace()
    }

    private func ensureAtLeastOneWorkspace() {
        if store.workspaces.isEmpty { createUntitledWorkspace() }
    }

    /// Messaggio della conferma: privilegia Claude per ogni stato di sessione viva - anche ferma
    /// al prompt (`idle`) il processo è in foreground e la chiusura la interrompe; il proc_name
    /// grezzo sarebbe la versione ("2.1.200"), incomprensibile. `.unknown` = nessuna sessione nota
    /// in questa run (mai partita, chiusa da SessionEnd, o tab appena ripristinata: `resume` non
    /// basta a dire "Claude", dopo un restore nel pty può girare tutt'altro): lì il nome del
    /// processo è l'informazione più onesta. Niente promessa di ripresa: chiudere la tab butta
    /// anche il suo `ResumeBinding`.
    private func closeInfo(process: String, agentState: AgentState) -> String {
        switch agentState {
        case .running:
            "Claude sta lavorando in questa tab. Chiudendo, la sessione verrà interrotta."
        case .needsInput:
            "Claude sta aspettando una tua risposta. Chiudendo, la sessione verrà interrotta."
        case .idle, .error:
            "In questa tab c'è una sessione Claude aperta. Chiudendo, verrà interrotta."
        case .unknown:
            "«\(process)» è in esecuzione. Chiudendo la tab il processo verrà terminato."
        }
    }

    /// Alert di conferma come sheet sulla finestra. Default sicuro: Invio annulla (non chiude).
    private func confirmClose(title: String, info: String, onConfirm: @escaping () -> Void) {
        guard let window else { onConfirm(); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = info
        let closeButton = alert.addButton(withTitle: "Chiudi")
        let cancelButton = alert.addButton(withTitle: "Annulla")
        closeButton.keyEquivalent = "" // Invio non deve chiudere per errore
        cancelButton.keyEquivalent = "\r"
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { onConfirm() }
        }
    }
}
