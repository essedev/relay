import AppKit
import Core
import TerminalEngine
import WorkspaceModel

// Reconcile dell'albero di pane: da `Workspace.splitLayout` a `NSSplitView` annidate. Estratto da
// `WorkspaceAreaController` per tenere il file principale entro il budget (vedi CONVENTIONS).
//
// Due regole guidano tutto:
// 1. **Riuso, non rebuild**: le `PaneView` sono chiavate per `Tab.id` e sopravvivono al reconcile,
//    quindi la surface (e il pty) non si tocca mai per un cambio di layout. Le view si
//    ricostruiscono
//    solo quando la *struttura* dell'albero cambia, non quando cambiano i rapporti dei divider.
// 2. **Il focus si prende solo se cambia**: un render scatta anche a ogni OSC 7 dello shell, e
//    rubare il first responder lì strapperebbe la find bar o un overlay mentre digiti.

extension WorkspaceAreaController: NSSplitViewDelegate {
    func render() {
        // Legge settings.theme: entra nel tracking, così un cambio tema/zoom ri-renderizza e
        // propaga
        // il tema alle surface vive (no-op se invariato).
        registry.applyTheme(settings.theme)

        let aliveTabIDs = Set(store.workspaces.flatMap { $0.tabs.map(\.id) })
        registry.retain(aliveTabIDs)

        guard let workspace = store.selectedWorkspace(in: windowID),
              let focused = workspace.selectedTabID
        else {
            unmountAll()
            return
        }

        // Senza split il pane singolo è la tab focused: una sola forma per lo stesso stato.
        let tree = workspace.splitLayout ?? .leaf(focused)
        mount(tree, in: workspace)

        // Nota: montare una tab **non** spegne `attention` (lo faceva il vecchio modello). Aprire
        // una tab completata mostra il ring verde + flash; il mark-read lo fa solo l'interazione
        // col terminale (monitor key/mouse). Vedi observeRing e il gotcha attention.

        if focusedTabID != focused {
            focusedTabID = focused
            panes[focused].map { view.window?.makeFirstResponder($0.terminalView) }
        }

        registry.enforceLRU(
            cap: liveSurfaceCap,
            keep: Set(tree.leaves), // ogni pane a schermo è intoccabile, non solo il focused
            protectedTabIDs: protectedTabIDs(activeWorkspace: workspace)
        )
    }

    // MARK: - Montaggio

    /// Ricostruisce l'albero di view solo se la **struttura** è cambiata: durante il drag di un
    /// divider cambiano solo i rapporti, e rifare le view sotto il puntatore darebbe flicker e
    /// perdita di focus. Le `PaneView` vengono riusate per tab, mai ricreate.
    private func mount(_ tree: SplitNode, in workspace: Workspace) {
        if let mounted = mountedTree, mounted.hasSameStructure(as: tree) {
            mountedTree = tree // i nuovi ratio restano registrati, senza toccare le view
            return
        }
        let wanted = Set(tree.leaves)
        // I pane che escono di scena mollano il terminale: la surface resta viva nella registry (il
        // pty continua a lavorare) e può essere rimontata altrove.
        for (tabID, pane) in panes where !wanted.contains(tabID) {
            pane.detachTerminal()
            panes.removeValue(forKey: tabID)
            lastRingStates.removeValue(forKey: tabID)
        }
        container.subviews.forEach { $0.removeFromSuperview() }

        let root = makeView(for: tree, in: workspace)
        root.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root)
        let inset = Self.containerInset
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            root.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
        ])
        mountedTree = tree
        // I divider vogliono dimensioni reali: prima il layout, poi i rapporti.
        container.layoutSubtreeIfNeeded()
        applyRatios(tree, to: root)
    }

    private func unmountAll() {
        panes.values.forEach { $0.detachTerminal() }
        panes.removeAll()
        lastRingStates.removeAll()
        container.subviews.forEach { $0.removeFromSuperview() }
        mountedTree = nil
        focusedTabID = nil
    }

    private func makeView(for node: SplitNode, in workspace: Workspace) -> NSView {
        switch node {
        case let .leaf(tabID):
            return pane(for: tabID, in: workspace)
        case let .split(branchID, axis, _, first, second):
            let splitView = NSSplitView()
            // Figli affiancati = divider verticale. Il nome dell'asse descrive la disposizione dei
            // pane, non l'orientamento del divider: sono ortogonali.
            splitView.isVertical = axis == .horizontal
            splitView.dividerStyle = .thin
            splitView.delegate = self
            splitView.identifier = NSUserInterfaceItemIdentifier(branchID.uuidString)
            splitView.addArrangedSubview(makeView(for: first, in: workspace))
            splitView.addArrangedSubview(makeView(for: second, in: workspace))
            return splitView
        }
    }

    /// Il pane della tab, riusato se già montato. La surface nasce lazy alla prima visita e viene
    /// legata alla `PaneView`; da lì in poi il pane sopravvive ai reconcile.
    private func pane(for tabID: UUID, in workspace: Workspace) -> PaneView {
        if let existing = panes[tabID] { return existing }
        guard let tab = workspace.tabs.first(where: { $0.id == tabID }) else {
            return PaneView(tabID: tabID, terminal: NSView())
        }
        // La shell parte dalla cwd della tab (ereditata o nota via OSC 7), fallback sul workspace.
        let surface = registry.surface(
            for: tabID,
            cwd: tab.currentDirectory ?? workspace.rootPath,
            onTitle: { [weak tab] title in
                guard let tab, !tab.hasCustomTitle else { return }
                tab.title = title
            },
            onDirectory: { [weak tab] path in
                tab?.currentDirectory = path
            }
        )
        surface.start() // lazy: il pty nasce alla prima volta che la tab finisce in un pane
        let pane = PaneView(tabID: tabID, terminal: surface.view)
        panes[tabID] = pane
        return pane
    }

    // MARK: - Rapporti dei divider

    /// Applica i rapporti salvati alle `NSSplitView` appena montate. `isApplyingRatios` zittisce le
    /// callback di resize che ne derivano: rimbalzerebbero nello store e sovrascriverebbero il
    /// ratio
    /// appena letto.
    private func applyRatios(_ node: SplitNode, to view: NSView) {
        guard case let .split(_, axis, ratio, first, second) = node,
              let splitView = view as? NSSplitView,
              splitView.arrangedSubviews.count == 2 else { return }
        isApplyingRatios = true
        let total = axis == .horizontal ? splitView.bounds.width : splitView.bounds.height
        if total > 0 {
            splitView.setPosition(total * ratio, ofDividerAt: 0)
        }
        isApplyingRatios = false
        applyRatios(first, to: splitView.arrangedSubviews[0])
        applyRatios(second, to: splitView.arrangedSubviews[1])
    }

    /// L'utente ha trascinato un divider: il nuovo rapporto risale al composition root, che lo
    /// scrive
    /// nello store (e l'autosave lo persiste). Non ricostruiamo niente: la struttura non è
    /// cambiata.
    public func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isApplyingRatios,
              let splitView = notification.object as? NSSplitView,
              let rawID = splitView.identifier?.rawValue,
              let branchID = UUID(uuidString: rawID),
              splitView.arrangedSubviews.count == 2 else { return }
        let firstView = splitView.arrangedSubviews[0]
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        guard total > 0 else { return }
        let used = splitView.isVertical ? firstView.bounds.width : firstView.bounds.height
        onRatioChange?(branchID, Double(used / total))
    }

    /// Un pane non si trascina fino a sparire: sotto questa soglia il terminale non mostra più una
    /// riga utile. Coerente col clamp del `ratio` nel model.
    public func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMin: CGFloat,
        ofSubviewAt _: Int
    ) -> CGFloat {
        max(proposedMin, Self.minimumPaneSize(vertical: splitView.isVertical))
    }

    public func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMax: CGFloat,
        ofSubviewAt _: Int
    ) -> CGFloat {
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        return min(proposedMax, total - Self.minimumPaneSize(vertical: splitView.isVertical))
    }

    private static func minimumPaneSize(vertical: Bool) -> CGFloat {
        vertical ? 220 : 120
    }

    // MARK: - Cap LRU

    func protectedTabIDs(activeWorkspace workspace: Workspace) -> Set<UUID> {
        var ids = Set(workspace.tabs.map(\.id))
        // Anche i pane montati nelle **altre** finestre sono a schermo: sfrattarli spegnerebbe un
        // terminale che l'utente sta guardando.
        for window in store.windows {
            store.selectedWorkspace(in: window.id).map { ids.formUnion($0.mountedTabIDs) }
        }
        for candidateWorkspace in store.workspaces {
            for tab in candidateWorkspace.tabs where hasFreshAttention(tab) {
                ids.insert(tab.id)
            }
        }
        return ids
    }

    private func hasFreshAttention(_ tab: Tab) -> Bool {
        tab.agentState == .needsInput || tab.agentState == .error || tab.attention == .unseen
    }

    /// Massimo di surface vive tenute in memoria. Default 12, tarato sulle misure di memoria (M3,
    /// `docs/research/PERF.md`). Override via `RELAY_SURFACE_CAP`.
    var liveSurfaceCap: Int {
        let raw = ProcessInfo.processInfo.environment["RELAY_SURFACE_CAP"].flatMap(Int.init) ?? 0
        return raw > 0 ? raw : 12
    }

    /// Aria fra i pane e il bordo dell'area. I pane aggiungono il loro inset interno: fra due pane
    /// affiancati lo spazio è la somma dei due, sul bordo è questo più uno.
    private static let containerInset: CGFloat = 6
}
