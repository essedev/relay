import SwiftUI
import WorkspaceModel

/// Rendering delle due viste della dashboard (griglia storica + kanban per stato) e navigazione da
/// tastiera, estratti dal corpo di `DashboardView` per tenere file e tipo entro i limiti di lint.
/// Accedono a `store`/`query`/`selectedID`/`layout`/`card` (internal) del tipo principale.
extension DashboardView {
    // MARK: - Grid (vista storica)

    func grid(
        _ items: [DashboardModel.Item],
        _ colors: ChromeColors,
        now: Date
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm),
                        count: Self.gridColumns
                    ),
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(items) { item in
                        card(item, colors, now: now).id(item.id)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            // Le frecce spostano la selezione: tienila in vista se esce dall'area scrollabile.
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    // MARK: - Board (kanban per stato)

    func board(_ colors: ChromeColors, now: Date) -> some View {
        let columns = DashboardModel.columns(workspaces: store.workspaces, query: query)
        return ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ForEach(columns) { column in
                    lane(column, colors, now: now)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func lane(
        _ column: DashboardModel.Column,
        _ colors: ChromeColors,
        now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            laneHeader(column, colors)
            if column.items.isEmpty {
                lanePlaceholder(colors)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(column.items) { item in
                            card(item, colors, now: now).id(item.id)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.sm)
                }
            }
        }
        // Colonne flessibili: si dividono equamente la larghezza fissa del pannello (non la
        // dettano), così la dimensione resta identica alla vista a griglia.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func laneHeader(
        _ column: DashboardModel.Column,
        _ colors: ChromeColors
    ) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(laneTint(column.lane, colors))
                .frame(width: 6, height: 6)
            Text(column.lane.title)
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(colors.foreground.opacity(0.85))
            Spacer()
            Text("\(column.items.count)")
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(colors.secondary)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func lanePlaceholder(_ colors: ChromeColors) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.sm)
            .fill(colors.surface.opacity(0.4))
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay(
                Text("empty")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.secondary.opacity(0.6))
            )
    }

    /// Tinta della corsia dai colori del tema, coerente con badge/ring: aspetta te = ambra,
    /// lavora = blu, fatto = verde, quieto = secondario.
    private func laneTint(_ lane: DashboardModel.Lane, _ colors: ChromeColors) -> Color {
        switch lane {
        case .waiting: colors.needsInput
        case .running: colors.running
        case .done: colors.completed
        case .idle: colors.secondary
        }
    }

    // MARK: - Navigazione da tastiera

    /// Frecce: in griglia muove sull'ordine flat (3 colonne per su/giù); in kanban è 2D reale
    /// (su/giù dentro la corsia, sinistra/destra alla corsia non vuota adiacente).
    func moveSelection(
        dx: Int,
        dy: Int,
        items: [DashboardModel.Item]
    ) -> KeyPress.Result {
        guard !items.isEmpty else { return .handled }
        let current = selectedID ?? items.first?.id
        if layout == .board {
            selectedID = boardTarget(from: current, dx: dx, dy: dy) ?? current
        } else {
            let step = dy != 0 ? dy * Self.gridColumns : dx
            selectedID = gridTarget(from: current, step: step, items: items)
        }
        return .handled
    }

    private func gridTarget(
        from id: UUID?,
        step: Int,
        items: [DashboardModel.Item]
    ) -> UUID? {
        let cur = items.firstIndex { $0.id == id } ?? 0
        let next = min(max(cur + step, 0), items.count - 1)
        return items[next].id
    }

    private func boardTarget(from id: UUID?, dx: Int, dy: Int) -> UUID? {
        let columns = DashboardModel.columns(workspaces: store.workspaces, query: query)
        guard let (col, row) = locate(id, in: columns) else {
            return columns.first { !$0.items.isEmpty }?.items.first?.id
        }
        if dy != 0 {
            let laneItems = columns[col].items
            let r = min(max(row + dy, 0), laneItems.count - 1)
            return laneItems[r].id
        }
        var c = col + dx
        while columns.indices.contains(c) {
            let laneItems = columns[c].items
            if !laneItems.isEmpty {
                return laneItems[min(row, laneItems.count - 1)].id
            }
            c += dx
        }
        return id
    }

    private func locate(
        _ id: UUID?,
        in columns: [DashboardModel.Column]
    ) -> (col: Int, row: Int)? {
        guard let id else { return nil }
        for (c, column) in columns.enumerated() {
            if let r = column.items.firstIndex(where: { $0.id == id }) { return (c, r) }
        }
        return nil
    }

    func jump(_ items: [DashboardModel.Item]) {
        let id = selectedID ?? items.first?.id
        guard let item = items.first(where: { $0.id == id }) else { return }
        onJump(item.workspace, item.tab)
    }

    /// Card di una sessione, condivisa da griglia e kanban. `SessionCard` è privata a questo file,
    /// quindi la factory vive qui e i due rendering (griglia/board) la richiamano.
    func card(
        _ item: DashboardModel.Item,
        _ colors: ChromeColors,
        now: Date
    ) -> some View {
        SessionCard(
            item: item,
            selected: item.id == selectedID,
            now: now,
            colors: colors,
            onJump: { onJump(item.workspace, item.tab) },
            onDismiss: { store.dismissAttention(item.tab.id) }
        )
    }
}

/// Card di una sessione: stato (pallino + label), titolo, chip del workspace, età dell'ultimo
/// evento. Su hover, x di dismiss per spegnere un completamento (unseen o in sospeso).
private struct SessionCard: View {
    let item: DashboardModel.Item
    let selected: Bool
    let now: Date
    let colors: ChromeColors
    let onJump: () -> Void
    let onDismiss: () -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            statusRow
            Text(item.tab.title)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
            chipRow
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(hovered ? colors.hover : colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(selected ? colors.accent : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onJump)
        .onHover { hovered = $0 }
    }

    private var statusRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            statusDot
            Text(statusLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
            Spacer()
            if hovered, item.tab.attention != .none {
                CloseButton(color: colors.secondary, size: 8, help: "Dismiss", action: onDismiss)
            } else if let age = DashboardModel.age(
                of: DashboardModel.ageDate(for: item.tab),
                now: now
            ) {
                Text(age)
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(colors.secondary)
            }
        }
    }

    @ViewBuilder private var statusDot: some View {
        let kind = BadgeKind.forTab(item.tab)
        let compact = Theme.Metrics.statusDotCompact
        switch kind {
        case .pending:
            StatusDot(color: colors.completed.opacity(0.55), style: .ring, size: compact)
        case .none:
            StatusDot(color: colors.secondary.opacity(0.5), style: .ring, size: compact)
        default:
            StatusDot(color: kind.tint(colors), size: compact)
        }
    }

    private var statusLabel: String {
        switch BadgeKind.forTab(item.tab) {
        case .needsInput: "needs input"
        case .error: "error"
        case .running: "running"
        case .completed: "done"
        case .pending: "pending"
        case .none: item.tab.pendingResume ? "resumable" : "idle"
        }
    }

    private var chipRow: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(chipColor)
                .frame(width: 6, height: 6)
            Text(item.workspace.name)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Colore del chip dai colori ANSI del tema, stabile per workspace (vedi `chipColorIndex`).
    private var chipColor: Color {
        Color(colors.theme.ansiColor(DashboardModel.chipColorIndex(item.workspace.id)))
    }
}
