import AppKit
import Core
import Panels
import SwiftUI
import TerminalEngine
import WorkspaceModel

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let log = RelayLog.logger("app")
    private let store = WorkspaceStore()
    private let settings = AppSettings()
    private let engine: TerminalEngine = SwiftTermEngine()
    private lazy var agentCoordinator = AgentCoordinator(store: store)
    private var window: NSWindow!
    private var settingsWindow: NSWindow?
    private var untitledCount = 0
    private var keyMonitor: Any?
    private var demoDriver: DemoDriver?

    func applicationDidFinishLaunching(_: Notification) {
        log.info("relay launched")
        buildMenu()
        installNavigationKeyMonitor()
        agentCoordinator.start()
        seedIfNeeded()

        let onNewWorkspace: () -> Void = { [weak self] in self?.newWorkspace(nil) }
        let split = MainSplitViewController(
            store: store,
            settings: settings,
            engine: engine,
            onNewWorkspace: onNewWorkspace
        )

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Relay"
        // Il contenuto sale fino al bordo: il titolo visibile è la strip del right pane
        // (ContextTitleBar), centrata sul body. Il title nativo resta per Mission Control/Cmd+Tab.
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        let root = RootOverlayController(content: split, overlay: makeSidebarToggleOverlay())
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

    func applicationWillTerminate(_: Notification) {
        demoDriver?.stop()
        agentCoordinator.stop()
    }

    private func seedIfNeeded() {
        if let config = DemoConfig.parse(from: CommandLine.arguments) {
            seedDemo(config)
            return
        }
        guard store.workspaces.isEmpty else { return }
        createUntitledWorkspace()
    }

    /// Demo mode: N workspace da M tab, con sessioni agente simulate su ogni tab (eventi via
    /// socket reale). Le tab restano `unrealized` finché non le visiti: i badge vivono comunque.
    private func seedDemo(_ config: DemoConfig) {
        let tabTitles = ["agent", "build", "server", "tests", "logs", "repl", "infra", "docs", "db"]
        var allTabIDs: [UUID] = []
        for index in 1 ... config.workspaces {
            let workspace = store.createWorkspace(
                name: "Demo \(index)",
                rootPath: NSHomeDirectory()
            )
            // createWorkspace aggiunge già una tab: rinominala e aggiungi le altre.
            store.renameTab(workspace.tabs[0].id, in: workspace, to: tabTitles[0])
            for tabIndex in 1 ..< config.tabsPerWorkspace {
                let title = tabTitles[tabIndex % tabTitles.count]
                store.addTab(to: workspace, title: title)
            }
            workspace.selectedTabID = workspace.tabs.first?.id
            allTabIDs.append(contentsOf: workspace.tabs.map(\.id))
        }
        store.selectWorkspace(store.workspaces[0].id)

        let driver = DemoDriver()
        demoDriver = driver
        driver.start(tabIDs: allTabIDs)
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
        hosting.preferredContentSize = NSSize(width: 380, height: 220)
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
              let tabID = workspace.selectedTabID else { return }
        store.closeTab(tabID, in: workspace)
    }

    /// Cmd+1..9: seleziona il workspace all'indice (tag 0-based).
    @objc func selectWorkspaceByShortcut(_ sender: NSMenuItem) {
        guard sender.tag < store.workspaces.count else { return }
        store.selectWorkspace(store.workspaces[sender.tag].id)
    }

    /// Option+1..9: seleziona la tab all'indice nel workspace corrente (tag 0-based).
    @objc func selectTabByShortcut(_ sender: NSMenuItem) {
        guard let workspace = store.selectedWorkspace,
              sender.tag < workspace.tabs.count else { return }
        store.selectTab(workspace.tabs[sender.tag].id, in: workspace)
    }

    // MARK: - Navigazione da tastiera (Cmd/Option + 1..9)

    /// Gli shortcut menu con solo Option non fanno match (AppKit confronta il carattere
    /// trasformato, es. Option+1 = "¡"), quindi intercettiamo Cmd/Option + cifra qui, prima che
    /// l'evento arrivi al terminale.
    private func installNavigationKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, handleNavigationKey(event) else { return event }
            return nil // consumato
        }
    }

    private func handleNavigationKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == .option else { return false }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let digit = Int(chars), (1 ... 9).contains(digit) else { return false }
        let index = digit - 1

        if flags == .command {
            if index < store.workspaces.count {
                store.selectWorkspace(store.workspaces[index].id)
            }
        } else {
            if let workspace = store.selectedWorkspace, index < workspace.tabs.count {
                store.selectTab(workspace.tabs[index].id, in: workspace)
            }
        }
        return true
    }

    // MARK: - Menu

    private func buildMenu() {
        NSApp.mainMenu = MainMenuBuilder.build(target: self)
    }
}
