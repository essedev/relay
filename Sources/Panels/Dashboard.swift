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

    // MARK: - Kanban

    /// Colonna del kanban: una corsia di triage, non un singolo stato. Ordine = ciclo di vita di
    /// una sessione (quanto reclama *te*, da sinistra): aspetta te -> lavora -> fatto -> quieto.
    /// La card porta comunque lo stato preciso (pallino + label), la corsia è il raggruppamento.
    public enum Lane: Int, CaseIterable, Identifiable, Sendable {
        case waiting // needs input + error: bloccata, serve un tuo intervento
        case running // sta lavorando da sola
        case done // completata e non ancora vista (unseen)
        case idle // pending (visto ma non ripreso) + idle + solo resume: segnale quieto

        public var id: Int {
            rawValue
        }

        public var title: String {
            switch self {
            case .waiting: "Needs You"
            case .running: "Running"
            case .done: "Done"
            case .idle: "Idle"
            }
        }
    }

    /// Corsia di una tab, dal suo badge (stessa mappatura di `BadgeKind`, aggregata per triage).
    static func lane(for tab: WorkspaceModel.Tab) -> Lane {
        switch BadgeKind.forTab(tab) {
        case .needsInput, .error: .waiting
        case .running: .running
        case .completed: .done
        case .pending, .none: .idle
        }
    }

    /// Una colonna renderizzabile: la corsia e le sue sessioni (già filtrate e ordinate).
    public struct Column: Identifiable {
        public let lane: Lane
        public let items: [Item]
        public var id: Int {
            lane.rawValue
        }
    }

    /// Sessioni partizionate per corsia, **tutte** le corsie sempre presenti (una colonna vuota è
    /// informazione, non un buco). L'ordine dentro ogni colonna è quello di `items` (urgenza desc,
    /// poi evento recente): la stessa fonte del grid, così le due viste concordano.
    public static func columns(
        workspaces: [Workspace],
        query: String = ""
    ) -> [Column] {
        let all = items(workspaces: workspaces, query: query)
        return Lane.allCases.map { lane in
            Column(lane: lane, items: all.filter { self.lane(for: $0.tab) == lane })
        }
    }
}

/// Overlay effimero della dashboard: sessioni agente in kanban per stato (`board`) o griglia flat
/// per urgenza (`grid`, la vista storica), con toggle. Filtro type-to-search, navigazione da
/// tastiera (frecce + Invio), dismiss dei sospesi. Aperta e chiusa da hotkey (azione rimappabile);
/// il wiring vive nel composition root.
public struct DashboardView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    let onJump: (Workspace, WorkspaceModel.Tab) -> Void
    let onClose: () -> Void

    /// `query`/`selectedID` sono internal (non `private`): il rendering delle due viste e la
    /// navigazione vivono in `Dashboard+Board.swift` e vi accedono. `selectedID` è la selezione
    /// per *id* (non per indice): sopravvive a reorder e riclassificazioni mentre l'overlay è
    /// aperto, e vale identica in griglia e kanban.
    @State var query = ""
    @State var selectedID: UUID?
    @FocusState private var searchFocused: Bool

    static let gridColumns = 3
    /// Dimensione unica del pannello: identica in griglia e kanban (cambia solo il contenuto
    /// interno). Leggermente più grande dell'originale (720x520).
    private static let panelWidth: CGFloat = 820
    private static let panelHeight: CGFloat = 580

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

    var layout: DashboardLayout {
        settings.dashboardLayout
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
        .onAppear { if selectedID == nil { selectedID = items.first?.id } }
        .onChange(of: query) { _, q in
            selectedID = DashboardModel.items(workspaces: store.workspaces, query: q).first?.id
        }
        .onChange(of: items.count) { _, _ in
            if selectedID == nil || !items.contains(where: { $0.id == selectedID }) {
                selectedID = items.first?.id
            }
        }
    }

    // MARK: - Panel

    private func panel(_ items: [DashboardModel.Item], _ colors: ChromeColors) -> some View {
        // Pannello identico nelle due viste: stessa barra di ricerca, stessa dimensione fissa;
        // il toggle scambia solo il contenuto interno (griglia <-> kanban), niente resize.
        VStack(spacing: 0) {
            header(items, colors)
            Divider()
            content(items, colors)
            Divider()
            hints(colors)
        }
        .frame(width: Self.panelWidth, height: Self.panelHeight)
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

    private func content(_ items: [DashboardModel.Item], _ colors: ChromeColors) -> some View {
        // Ogni 30s le età si aggiornano ("2m" -> "3m") anche a overlay fermo.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if items.isEmpty {
                emptyState(colors)
            } else if layout == .board {
                board(colors, now: context.date)
            } else {
                grid(items, colors, now: context.date)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header (search + toggle)

    private func header(_ items: [DashboardModel.Item], _ colors: ChromeColors) -> some View {
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
                .onKeyPress(.leftArrow) { moveSelection(dx: -1, dy: 0, items: items) }
                .onKeyPress(.rightArrow) { moveSelection(dx: 1, dy: 0, items: items) }
                .onKeyPress(.upArrow) { moveSelection(dx: 0, dy: -1, items: items) }
                .onKeyPress(.downArrow) { moveSelection(dx: 0, dy: 1, items: items) }
            layoutToggle(colors)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 44)
    }

    private func layoutToggle(_ colors: ChromeColors) -> some View {
        HStack(spacing: 2) {
            toggleButton(.board, systemImage: "rectangle.split.3x1", help: "Board view", colors)
            toggleButton(.grid, systemImage: "square.grid.2x2", help: "Grid view", colors)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(colors.surface))
    }

    private func toggleButton(
        _ mode: DashboardLayout,
        systemImage: String,
        help: String,
        _ colors: ChromeColors
    ) -> some View {
        let active = layout == mode
        return Button {
            settings.setDashboardLayout(mode)
            searchFocused = true // il toggle è un click: riporta il focus al campo per la tastiera
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? colors.background : colors.secondary)
                .frame(width: 26, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm - 2)
                        .fill(active ? colors.accent : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Empty state + hints

    private func emptyState(_ colors: ChromeColors) -> some View {
        Text(query.isEmpty ? "No agent sessions" : "No sessions match \u{201C}\(query)\u{201D}")
            .font(Theme.Typography.item)
            .foregroundStyle(colors.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
