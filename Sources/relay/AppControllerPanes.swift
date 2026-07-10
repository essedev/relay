import AppKit
import Panels
import WorkspaceModel

/// Azioni delle strip dei pane (modello cmux), estratte dal corpo di `AppController` per tenerlo
/// sul solo wiring: cwd risolta dalla shell viva del pane giusto, conferme di chiusura, nomi
/// placeholder. Il `workspace` arriva dalla strip (quella della sua finestra), mai dalla
/// proiezione della key: un click su una finestra di sfondo deve agire lì.
extension AppController {
    func makePaneActions() -> PaneTabBarActions {
        PaneTabBarActions(
            newTab: { [weak self] paneID, workspace in
                guard let self else { return }
                store.addTab(
                    toPane: paneID, in: workspace,
                    currentDirectory: currentDirectory(ofPane: paneID, in: workspace)
                )
            },
            splitPane: { [weak self] paneID, axis, workspace in
                guard let self else { return }
                store.splitPane(
                    paneID, axis: axis, in: workspace,
                    currentDirectory: currentDirectory(ofPane: paneID, in: workspace)
                )
            },
            closePane: { [weak self] paneID, workspace in
                self?.requestClosePane(paneID, in: workspace)
            },
            closeTab: { [weak self] tab, workspace in self?.requestCloseTab(tab, in: workspace) },
            moveTabToNewWorkspace: { [weak self] tab, workspace in
                self?.moveTabToNewWorkspace(tab, from: workspace)
            }
        )
    }

    /// Cwd migliore nota della tab a schermo di un pane (shell viva > OSC 7 > root), chiesta allo
    /// split della finestra **del workspace**: con più finestre la strip può non stare nella key.
    private func currentDirectory(ofPane paneID: UUID, in workspace: Workspace) -> String? {
        guard let tabID = workspace.layout.pane(paneID)?.selectedTabID else { return nil }
        let split = windowControllers[workspace.windowID]?.splitVC ?? splitVC
        return split?.currentDirectory(for: tabID)
    }
}
