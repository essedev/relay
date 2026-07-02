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
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Relay"
        window.contentViewController = split
        window.setFrameAutosaveName("RelayMainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_: Notification) {
        agentCoordinator.stop()
    }

    private func seedIfNeeded() {
        guard store.workspaces.isEmpty else { return }
        createUntitledWorkspace()
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

    @objc func openSettings(_: Any?) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let panel = NSWindow(contentViewController: hosting)
        panel.title = "Settings"
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.center()
        settingsWindow = panel
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
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        addItem(to: appMenu, "Settings…", #selector(openSettings(_:)), ",")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Relay",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        addItem(to: fileMenu, "New Workspace", #selector(newWorkspace(_:)), "n")
        addItem(to: fileMenu, "New Tab", #selector(newTab(_:)), "t")
        addItem(
            to: fileMenu,
            "Open Folder as Workspace…",
            #selector(openFolderAsWorkspace(_:)),
            "o"
        )
        fileMenu.addItem(.separator())
        addItem(to: fileMenu, "Close Tab", #selector(closeCurrentTab(_:)), "w")

        mainMenu.addItem(makeGoMenuItem())

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        addItem(to: viewMenu, "Zoom In", #selector(zoomIn(_:)), "=")
        addItem(to: viewMenu, "Zoom Out", #selector(zoomOut(_:)), "-")
        addItem(to: viewMenu, "Actual Size", #selector(resetZoom(_:)), "0")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        NSApp.mainMenu = mainMenu
    }

    /// Menu "Go": Cmd+1..9 per i workspace, Option+1..9 per le tab (i due assi, stile cmux).
    private func makeGoMenuItem() -> NSMenuItem {
        let goItem = NSMenuItem()
        let goMenu = NSMenu(title: "Go")
        goItem.submenu = goMenu

        // Nessun keyEquivalent: gli shortcut sono gestiti dal monitor (vedi
        // installNavigationKeyMonitor). Qui le voci restano cliccabili, con hint nel titolo.
        for index in 1 ... 9 {
            let item = NSMenuItem(
                title: "Workspace \(index)  (⌘\(index))",
                action: #selector(selectWorkspaceByShortcut(_:)),
                keyEquivalent: ""
            )
            item.tag = index - 1
            item.target = self
            goMenu.addItem(item)
        }
        goMenu.addItem(.separator())
        for index in 1 ... 9 {
            let item = NSMenuItem(
                title: "Tab \(index)  (⌥\(index))",
                action: #selector(selectTabByShortcut(_:)),
                keyEquivalent: ""
            )
            item.tag = index - 1
            item.target = self
            goMenu.addItem(item)
        }
        return goItem
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
}
