import AppKit
import Core
import TerminalEngine
import WorkspaceModel

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let log = RelayLog.logger("app")
    private let store = WorkspaceStore()
    private let engine: TerminalEngine = SwiftTermEngine()
    private var window: NSWindow!
    private var untitledCount = 0
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_: Notification) {
        log.info("relay launched")
        buildMenu()
        installKeyMonitor()
        seedIfNeeded()

        let split = MainSplitViewController(store: store, engine: engine) { [weak self] in
            self?.newWorkspace(nil)
        }

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

    @objc func closeCurrentTab(_: Any?) {
        guard let workspace = store.selectedWorkspace,
              let tabID = workspace.selectedTabID else { return }
        store.closeTab(tabID, in: workspace)
    }

    /// Navigazione a due assi (stile cmux). Via event monitor e non menu key equivalent: le
    /// equivalenze di menu con solo Option non scattano in modo affidabile (e dipendono dal
    /// layout di tastiera).
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handleShortcut(event) } ? nil : event
        }
    }

    /// Cmd+1..9 -> workspace, Option+1..9 -> tab nel workspace corrente. Ritorna true se consuma.
    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == .option,
              let chars = event.charactersIgnoringModifiers,
              let digit = Int(chars), (1 ... 9).contains(digit)
        else { return false }
        let index = digit - 1

        if flags == .command {
            guard index < store.workspaces.count else { return true }
            store.selectWorkspace(store.workspaces[index].id)
        } else {
            guard let workspace = store.selectedWorkspace, index < workspace.tabs.count else {
                return true
            }
            store.selectTab(workspace.tabs[index].id, in: workspace)
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

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
}
