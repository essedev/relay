import Foundation
import SwiftUI
import WorkspaceModel

/// Logica pura della dashboard (filtri, ordinamento, formattazioni): separata dalla vista per i
/// test. L'unità è la *sessione agente* (tab con storia agente), flat e ordinata per urgenza -
/// l'appartenenza al workspace è un chip sulla card, non una sezione (col pattern reale ~1 tab
/// agente per workspace, le sezioni sarebbero solo overhead visivo).
public enum DashboardModel {
    /// Una riga della griglia: la coppia workspace/tab (riferimenti vivi: la card osserva lo
    /// stato che cambia mentre l'overlay è aperto).
    public struct Item: Identifiable {
        public let workspace: Workspace
        public let tab: WorkspaceModel.Tab

        public var id: UUID {
            tab.id
        }
    }

    /// È una sessione agente: ha uno stato vivo, un completamento (anche in sospeso a sessione
    /// finita) o un resume proponibile. Le shell nude restano fuori: sono rumore per il triage.
    static func isSession(_ tab: WorkspaceModel.Tab) -> Bool {
        tab.agentState != .unknown || tab.attention != .none || tab.resume != nil
    }

    /// Urgenza per l'ordinamento (desc). Diversa dalla severità dei badge: qui è triage, ciò che
    /// aspetta *te* (input, errore, completamenti) viene prima di ciò che lavora da solo.
    static func urgencyRank(_ tab: WorkspaceModel.Tab) -> Int {
        if tab.agentState == .needsInput { return 5 }
        if tab.agentState == .error { return 4 }
        if tab.attention == .unseen { return 3 }
        if tab.attention == .pending { return 2 }
        if tab.agentState == .running { return 1 }
        return 0 // idle / solo resume
    }

    /// Sessioni filtrate e ordinate: urgenza desc, poi evento più recente, poi ordine visivo
    /// stabile. La query filtra su titolo, nome workspace e cwd (case-insensitive).
    public static func items(
        workspaces: [Workspace],
        query: String = ""
    ) -> [Item] {
        let all = workspaces.flatMap { ws in
            ws.tabs.filter(isSession).map { Item(workspace: ws, tab: $0) }
        }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = needle.isEmpty ? all : all.filter { item in
            item.tab.title.lowercased().contains(needle)
                || item.workspace.name.lowercased().contains(needle)
                || (item.tab.currentDirectory?.lowercased().contains(needle) ?? false)
        }
        return filtered.enumerated().sorted { lhs, rhs in
            let lRank = urgencyRank(lhs.element.tab)
            let rRank = urgencyRank(rhs.element.tab)
            if lRank != rRank { return lRank > rRank }
            let lDate = lhs.element.tab.lastEventAt ?? .distantPast
            let rDate = rhs.element.tab.lastEventAt ?? .distantPast
            if lDate != rDate { return lDate > rDate }
            return lhs.offset < rhs.offset // tiebreak stabile: ordine visivo
        }.map(\.element)
    }

    /// Timestamp che rappresenta l'età di una card: per un marker (unseen/pending) è da quando il
    /// marker è in vigore (`attentionSince`), altrimenti l'ultimo evento. Così un no-op
    /// (SessionEnd,
    /// idle->idle) che avanza `lastEventAt` per la monotonicità non ringiovanisce un sospeso.
    static func ageDate(for tab: WorkspaceModel.Tab) -> Date? {
        tab.attention == .none ? tab.lastEventAt : (tab.attentionSince ?? tab.lastEventAt)
    }

    /// Età compatta di un timestamp ("adesso", "45s", "3m", "2h", "5d"). `nil` senza timestamp.
    public static func age(of date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<10: return "now"
        case ..<60: return "\(Int(seconds))s"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }

    /// Indice ANSI (1...6: red, green, yellow, blue, magenta, cyan) stabile per workspace: stesso
    /// colore a ogni avvio, così il chip "rilega" all'occhio le card dello stesso progetto.
    static func chipColorIndex(_ id: UUID) -> Int {
        let sum = id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return (sum % 6) + 1
    }
}

/// Overlay effimero della dashboard: griglia flat di sessioni agente ordinate per urgenza, filtro
/// type-to-search, navigazione da tastiera (frecce + Invio), dismiss dei sospesi. Aperta e chiusa
/// da hotkey (azione rimappabile); il wiring vive nel composition root.
public struct DashboardView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    let onJump: (Workspace, WorkspaceModel.Tab) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private static let columns = 3

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onJump: @escaping (Workspace, WorkspaceModel.Tab) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.onJump = onJump
        self.onClose = onClose
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let items = DashboardModel.items(workspaces: store.workspaces, query: query)
        ZStack {
            // Backdrop: attenua il resto e chiude al click fuori dal pannello.
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
            panel(items, colors)
                .padding(.horizontal, Theme.Spacing.lg)
        }
        .onChange(of: query) { _, _ in selection = 0 }
        .onChange(of: items.count) { _, count in
            selection = min(selection, max(0, count - 1))
        }
    }

    private func panel(_ items: [DashboardModel.Item], _ colors: ChromeColors) -> some View {
        VStack(spacing: 0) {
            searchField(items, colors)
            Divider()
            if items.isEmpty {
                emptyState(colors)
            } else {
                grid(items, colors)
            }
            Divider()
            hints(colors)
        }
        .frame(maxWidth: 720)
        .frame(maxHeight: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(colors.hover, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func searchField(
        _ items: [DashboardModel.Item],
        _ colors: ChromeColors
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.secondary)
            TextField("Filter sessions", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .focused($searchFocused)
                .onAppear { searchFocused = true }
                .onSubmit { jump(items) }
                .onExitCommand(perform: onClose)
                .onKeyPress(.leftArrow) { move(-1, in: items) }
                .onKeyPress(.rightArrow) { move(1, in: items) }
                .onKeyPress(.upArrow) { move(-Self.columns, in: items) }
                .onKeyPress(.downArrow) { move(Self.columns, in: items) }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 44)
    }

    private func grid(_ items: [DashboardModel.Item], _ colors: ChromeColors) -> some View {
        // Ogni 30s le età si aggiornano ("2m" -> "3m") anche a overlay fermo.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm),
                            count: Self.columns
                        ),
                        spacing: Theme.Spacing.sm
                    ) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            SessionCard(
                                item: item,
                                selected: index == selection,
                                now: context.date,
                                colors: colors,
                                onJump: { onJump(item.workspace, item.tab) },
                                onDismiss: { store.dismissAttention(item.tab.id) }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
                // Le frecce spostano la selezione: tienila in vista se esce dall'area scrollabile.
                .onChange(of: selection) { _, sel in
                    guard items.indices.contains(sel) else { return }
                    withAnimation { proxy.scrollTo(items[sel].id, anchor: .center) }
                }
            }
        }
    }

    private func emptyState(_ colors: ChromeColors) -> some View {
        Text(query.isEmpty ? "No agent sessions" : "No sessions match \u{201C}\(query)\u{201D}")
            .font(Theme.Typography.item)
            .foregroundStyle(colors.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.lg * 2)
    }

    private func hints(_ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            hint("↑↓←→", "navigate", colors)
            hint("↩", "open", colors)
            hint("esc", "close", colors)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 28)
    }

    private func hint(_ keys: String, _ label: String, _ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(keys)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.foreground.opacity(0.8))
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
        }
    }

    private func move(_ delta: Int, in items: [DashboardModel.Item]) -> KeyPress.Result {
        guard !items.isEmpty else { return .handled }
        selection = min(max(selection + delta, 0), items.count - 1)
        return .handled
    }

    private func jump(_ items: [DashboardModel.Item]) {
        guard items.indices.contains(selection) else { return }
        let item = items[selection]
        onJump(item.workspace, item.tab)
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
                .fill(hovered ? colors.hover : colors.selection.opacity(0.35))
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
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.secondary)
                .help("Dismiss")
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
        switch BadgeKind.forTab(item.tab) {
        case .pending:
            Circle().strokeBorder(colors.completed.opacity(0.55), lineWidth: 1.5)
                .frame(width: 7, height: 7)
        case .none:
            Circle().strokeBorder(colors.secondary.opacity(0.5), lineWidth: 1.5)
                .frame(width: 7, height: 7)
        case let kind:
            Circle().fill(statusColor(kind)).frame(width: 7, height: 7)
        }
    }

    private func statusColor(_ kind: BadgeKind) -> Color {
        switch kind {
        case .needsInput: colors.needsInput
        case .error: colors.error
        case .running: colors.running
        case .completed: colors.completed
        case .pending, .none: colors.secondary
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
