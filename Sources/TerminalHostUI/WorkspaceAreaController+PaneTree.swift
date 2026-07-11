import AppKit
import Core
import TerminalEngine
import WorkspaceModel

// Reconcile dell'albero di pane: da `Workspace.layout` a `NSSplitView` annidate. Estratto da
// `WorkspaceAreaController` per tenere il file principale entro il budget (vedi CONVENTIONS).
//
// Tre regole guidano tutto:
// 1. **Riuso, non rebuild**: le `PaneView` sono chiavate per `SplitPane.id` e sopravvivono al
//    reconcile; si ricostruiscono solo quando la *struttura* dell'albero cambia (nuovi pane, assi),
//    non per un cambio di selezione o di ratio.
// 2. **Il contenuto si scambia**: cambiare la tab selezionata di una strip attacca un'altra surface
//    allo stesso pane. Le surface vivono nella registry (per `Tab.id`) e non muoiono mai per un
//    cambio di layout.
// 3. **Il focus si prende solo se cambia** la coppia (pane focused, sua tab) - un render scatta
//    anche a ogni OSC 7 - **oppure dopo un rebuild**: staccare le view dalla finestra resetta il
//    first responder, e senza riprenderlo la tastiera resterebbe morta anche a focus invariato.

extension WorkspaceAreaController: NSSplitViewDelegate {
    func render() {
        // Legge settings.theme: entra nel tracking, così un cambio tema/zoom ri-renderizza e
        // propaga il tema alle surface vive (no-op se invariato).
        registry.applyTheme(settings.theme)

        let aliveTabIDs = Set(store.workspaces.flatMap { $0.tabs.map(\.id) })
        registry.retain(aliveTabIDs)

        guard let workspace = store.selectedWorkspace(in: windowID) else {
            unmountAll()
            return
        }

        let tree = workspace.layout
        let rebuilt = mount(tree, in: workspace)
        attachTerminals(tree, in: workspace)
        assertFocus(in: workspace, force: rebuilt)

        registry.enforceLRU(
            cap: liveSurfaceCap,
            keep: Set(tree.visibleTabIDs), // ogni pane a schermo è intoccabile, non solo il focused
            protectedTabIDs: protectedTabIDs(activeWorkspace: workspace)
        )
    }

    // MARK: - Montaggio

    /// Ricostruisce l'albero di view solo se la **struttura** è cambiata: durante il drag di un
    /// divider cambiano solo i rapporti, e per un cambio di selezione si scambia solo il terminale.
    /// Le `PaneView` vengono riusate per `SplitPane.id`, mai ricreate. Ritorna `true` se ha
    /// ricostruito (il chiamante deve riasserire il first responder).
    private func mount(_ tree: SplitNode, in _: Workspace) -> Bool {
        if let mounted = mountedTree, mounted.hasSameStructure(as: tree) {
            mountedTree = tree // i nuovi ratio restano registrati, senza toccare le view
            return false
        }
        let wanted = Set(tree.paneIDs)
        // I pane che escono di scena mollano il terminale: la surface resta viva nella registry (il
        // pty continua a lavorare) e può essere rimontata altrove.
        for (paneID, pane) in panes where !wanted.contains(paneID) {
            pane.detachTerminal()
            panes.removeValue(forKey: paneID)
            lastRingStates.removeValue(forKey: paneID)
        }
        container.subviews.forEach { $0.removeFromSuperview() }

        let root = makeView(for: tree)
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
        lastRatioSize = container.bounds.size
        return true
    }

    private func unmountAll() {
        panes.values.forEach { $0.detachTerminal() }
        panes.removeAll()
        lastRingStates.removeAll()
        container.subviews.forEach { $0.removeFromSuperview() }
        mountedTree = nil
        focusedKey = nil
    }

    private func makeView(for node: SplitNode) -> NSView {
        switch node {
        case let .pane(splitPane):
            return paneView(for: splitPane.id)
        case let .split(branchID, axis, _, first, second):
            let splitView = NSSplitView()
            // Figli affiancati = divider verticale. Il nome dell'asse descrive la disposizione dei
            // pane, non l'orientamento del divider: sono ortogonali.
            splitView.isVertical = axis == .horizontal
            splitView.dividerStyle = .thin
            splitView.delegate = self
            splitView.identifier = NSUserInterfaceItemIdentifier(branchID.uuidString)
            splitView.addArrangedSubview(makeView(for: first))
            splitView.addArrangedSubview(makeView(for: second))
            return splitView
        }
    }

    /// La `PaneView` del pane, riusata se già montata. La strip arriva dalla factory del
    /// composition root; senza (test senza chrome) una NSView vuota d'altezza **zero esplicita**:
    /// una view nuda non ha altezza intrinseca e lascerebbe il layout ambiguo.
    private func paneView(for paneID: UUID) -> PaneView {
        if let existing = panes[paneID] { return existing }
        let strip: NSView
        if let made = makePaneStrip?(paneID) {
            strip = made
        } else {
            strip = NSView()
            strip.heightAnchor.constraint(equalToConstant: 0).isActive = true
        }
        let pane = PaneView(paneID: paneID, strip: strip)
        panes[paneID] = pane
        return pane
    }

    /// Riconcilia il contenuto di ogni pane: attacca la surface della tab selezionata della sua
    /// strip. Gira a ogni render (è un confronto per pane); la surface nasce lazy alla prima
    /// visita.
    private func attachTerminals(_ tree: SplitNode, in workspace: Workspace) {
        for splitPane in tree.panes {
            guard let paneView = panes[splitPane.id] else { continue }
            guard let tabID = splitPane.selectedTabID,
                  let tab = workspace.tab(tabID)
            else {
                paneView.detachTerminal() // pane transitoriamente vuoto (workspace in chiusura)
                continue
            }
            guard paneView.currentTabID != tabID else { continue }
            let surface = registry.surface(
                for: tabID,
                // La shell parte dalla cwd della tab (ereditata o nota via OSC 7), fallback root.
                cwd: tab.currentDirectory ?? workspace.rootPath,
                onTitle: { [weak tab] title in
                    guard let tab, !tab.hasCustomTitle else { return }
                    tab.title = title
                },
                onDirectory: { [weak tab] path in
                    tab?.currentDirectory = path
                }
            )
            surface.start() // lazy: il pty nasce alla prima volta che la tab finisce a schermo
            paneView.attachTerminal(surface.view, for: tabID)
        }
    }

    /// First responder al terminale del pane focused. `force` dopo un rebuild: staccare le view
    /// dalla finestra ha resettato il responder anche se la coppia focused non è cambiata.
    private func assertFocus(in workspace: Workspace, force: Bool) {
        guard let tabID = workspace.selectedTabID else { return }
        let key = FocusKey(paneID: workspace.focusedPaneID, tabID: tabID)
        guard force || focusedKey != key else { return }
        focusedKey = key
        guard let terminal = panes[workspace.focusedPaneID]?.terminalView else { return }
        view.window?.makeFirstResponder(terminal)
    }

    // MARK: - Rapporti dei divider

    /// Applica i rapporti salvati alle `NSSplitView` appena montate. `isApplyingRatios` zittisce le
    /// callback di resize che ne derivano: rimbalzerebbero nello store e sovrascriverebbero il
    /// ratio appena letto.
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

    /// Riapplica i rapporti dello store quando il container cambia dimensione: il boot parte 0x0
    /// (i `setPosition` del mount non hanno effetto) e senza questo il primo layout vero
    /// distribuirebbe 50/50, che il write-back scriverebbe nello store stompando il ratio
    /// persistito.
    func reapplyRatiosIfNeeded() {
        guard let tree = mountedTree,
              container.bounds.size != lastRatioSize,
              container.bounds.width > 0, container.bounds.height > 0,
              let root = container.subviews.first else { return }
        lastRatioSize = container.bounds.size
        container.layoutSubtreeIfNeeded()
        applyRatios(tree, to: root)
    }

    /// L'utente ha trascinato un divider: il nuovo rapporto risale al composition root, che lo
    /// scrive nello store (e l'autosave lo persiste). Non ricostruiamo niente: la struttura non è
    /// cambiata. Il write-back parte **solo con un bottone del mouse premuto** (drag reale del
    /// divider o resize della finestra, dove il ratio proporzionale resta invariato): i layout
    /// pass programmatici (boot, `layoutSubtreeIfNeeded` del mount) non devono stompare il ratio
    /// salvato con un 50/50 transitorio.
    public func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isApplyingRatios,
              NSEvent.pressedMouseButtons & 0x1 != 0,
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
        // Anche i pane a schermo nelle **altre** finestre sono visibili: sfrattarli spegnerebbe un
        // terminale che l'utente sta guardando.
        for window in store.windows {
            store.selectedWorkspace(in: window.id).map { ids.formUnion($0.visibleTabIDs) }
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
