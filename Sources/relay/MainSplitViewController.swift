import AppKit
import Panels
import SwiftUI
import TerminalEngine
import WorkspaceModel

/// Split principale: sidebar (SwiftUI in NSHostingController) + area di lavoro a destra.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    init(store: WorkspaceStore, engine: TerminalEngine, onNewWorkspace: @escaping () -> Void) {
        super.init(nibName: nil, bundle: nil)

        let sidebar = NSHostingController(
            rootView: SidebarView(store: store, onNewWorkspace: onNewWorkspace)
        )
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 340
        addSplitViewItem(sidebarItem)

        let right = RightPaneController(store: store, engine: engine)
        addSplitViewItem(NSSplitViewItem(viewController: right))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("MainSplitViewController is programmatic-only")
    }
}
