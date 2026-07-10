import AppKit
import Panels
import WorkspaceModel

/// Esecuzione delle azioni rimappabili. Un unico punto: il monitor (per hotkey) e i menu (per clic,
/// via `performShortcut`) passano di qui. Le azioni riusano i metodi esistenti dove ci sono.
extension AppController {
    // swiftlint:disable:next cyclomatic_complexity
    func perform(_ action: ShortcutAction) {
        switch action {
        case .newWorkspace: newWorkspace(nil)
        case .openFolder: openFolderAsWorkspace(nil)
        case .closeWorkspace: closeCurrentWorkspace()
        case .newWindow: newWindow(nil)
        case .closeWindow: closeCurrentWindow()
        case .cycleWorkspaceForward: store.selectAdjacentWorkspace(forward: true)
        case .cycleWorkspaceBackward: store.selectAdjacentWorkspace(forward: false)
        case .newTab: newTab(nil)
        case .closeTab: closeCurrentTab(nil)
        case .cycleTabForward: store.selectAdjacentTab(forward: true)
        case .cycleTabBackward: store.selectAdjacentTab(forward: false)
        case .splitRight: splitFocusedPane(axis: .horizontal)
        case .splitDown: splitFocusedPane(axis: .vertical)
        case .closePane: closeFocusedPane()
        case .focusNextPane: store.focusAdjacentPane(forward: true)
        case .focusPrevPane: store.focusAdjacentPane(forward: false)
        case .nextAttention: store.focusNextAttention()
        case .prevAttention: store.focusPrevAttention()
        case .toggleDashboard: toggleDashboard()
        case .find: splitVC?.toggleFind()
        case .findNext: splitVC?.findStep(forward: true)
        case .findPrevious: splitVC?.findStep(forward: false)
        case .clear: splitVC?.clearActiveTerminal()
        case .toggleSidebar: toggleSidebar(nil)
        case .zoomIn: zoomIn(nil)
        case .zoomOut: zoomOut(nil)
        case .actualSize: resetZoom(nil)
        }
    }

    /// Voce di menu di un'azione rimappabile: l'azione è in `representedObject`.
    @objc func performShortcut(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ShortcutAction else { return }
        perform(action)
    }

    func closeCurrentWorkspace() {
        guard let workspace = store.selectedWorkspace else { return }
        requestCloseWorkspace(workspace)
    }

    /// Divide il pane focused e ci apre accanto (o sotto) una nuova tab, **dove stai lavorando**:
    /// la cwd la risolve l'area dalla shell viva del pane diviso, come fa `Cmd+T`.
    func splitFocusedPane(axis: SplitAxis) {
        guard let tab = store.selectedWorkspace?.selectedTab else { return }
        let cwd = splitVC?.currentDirectory(for: tab.id)
        store.splitFocusedPane(axis: axis, currentDirectory: cwd)
    }

    /// Chiude il pane focused **con le sue tab** (`Opt+Cmd+W`), passando dalla conferma sui
    /// processi in foreground come ogni chiusura.
    func closeFocusedPane() {
        guard let workspace = store.selectedWorkspace else { return }
        requestClosePane(workspace.focusedPaneID, in: workspace)
    }
}
