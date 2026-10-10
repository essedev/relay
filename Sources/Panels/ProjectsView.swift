import SwiftUI
import WorkspaceModel

/// Pagina Projects: il catalogo di tutti i progetti, aperti e chiusi, per gruppo come la sidebar.
/// Da qui si riapre un progetto chiuso (click sulla riga) o si chiude uno aperto. Copre il right
/// pane della finestra (`RelayWindow.page`).
public struct ProjectsView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    let onOpenProject: (Workspace) -> Void
    let onCloseProject: (Workspace) -> Void
    let onNewProject: () -> Void

    @State private var query = ""
    @State private var filter: ProjectsModel.Filter = .all
    @State private var collapsed: Set<UUID?> = []
    @FocusState private var searchFocused: Bool

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onOpenProject: @escaping (Workspace) -> Void,
        onCloseProject: @escaping (Workspace) -> Void,
        onNewProject: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.onOpenProject = onOpenProject
        self.onCloseProject = onCloseProject
        self.onNewProject = onNewProject
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let all = store.workspaces
        let sections = ProjectsModel.sections(
            workspaces: all, groups: store.groups, query: query, filter: filter
        )
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(all: all, colors: colors)
                    if sections.isEmpty {
                        Text(query
                            .isEmpty ? "No projects here." :
                            "No project matches \u{201C}\(query)\u{201D}.")
                            .font(Theme.Typography.item)
                            .foregroundStyle(colors.secondary)
                            .padding(.top, Theme.Spacing.xl)
                    }
                    ForEach(sections) { section in
                        sectionView(section, colors: colors, now: context.date)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.page)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func header(all: [Workspace], colors: ChromeColors) -> some View {
        let open = all.count { !$0.closed }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Projects")
                .font(Theme.Typography.pageTitle)
                .foregroundStyle(colors.foreground)
            Text("\(all.count) projects, \(open) open. Closing one keeps its group, its tabs and "
                + "its sessions.")
                .font(Theme.Typography.pageSubtitle)
                .foregroundStyle(colors.secondary)
                .padding(.top, Theme.Spacing.xs)
            HStack(spacing: Theme.Spacing.sm) {
                searchField(colors)
                filterControl(all: all, colors: colors)
                Spacer(minLength: 0)
                Button("New Project", action: onNewProject)
                    .buttonStyle(PageButtonStyle(colors: colors))
            }
            .padding(.top, Theme.Spacing.lg)
        }
    }

    private func searchField(_ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.rowIcon)
                .foregroundStyle(colors.secondary)
            TextField("Filter by name or folder", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .focused($searchFocused)
                .onExitCommand { query = "" }
        }
        .padding(.horizontal, Theme.Spacing.md - 2)
        .padding(.vertical, Theme.Spacing.xs + 3)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md).fill(colors.terminalWell)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(colors.hairline, lineWidth: 1)
        )
    }

    private func filterControl(all: [Workspace], colors: ChromeColors) -> some View {
        HStack(spacing: 2) {
            ForEach(ProjectsModel.Filter.allCases, id: \.self) { option in
                let count = all.count(where: option.admits)
                Button {
                    filter = option
                } label: {
                    Text("\(option.title) \(count)")
                        .font(Theme.Typography.tab)
                        .foregroundStyle(filter == option ? colors.foreground : colors.secondary)
                        .padding(.horizontal, Theme.Spacing.sm + 2)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm - 1)
                                .fill(filter == option ? colors.selection : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(colors.terminalWell))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(colors.hairline, lineWidth: 1)
        )
    }

    /// Larghezza sotto la quale una card non sta più: nome, cartella e una sessione devono
    /// leggersi senza troncarsi a metà.
    private static let cardMinWidth: CGFloat = 280

    private func sectionView(
        _ section: ProjectsModel.Section, colors: ChromeColors, now: Date
    ) -> some View {
        let tint = section.group.map { colors.group($0.colorIndex) } ?? colors.secondary
        let shut = collapsed.contains(section.id) && query.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if shut { collapsed.remove(section.id) } else { collapsed.insert(section.id) }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(shut ? 0 : 90))
                    Text(section.group?.name ?? "Ungrouped")
                        .font(Theme.Typography.title)
                    Text("\(section.projects.count)")
                        .font(Theme.Typography.subtitle)
                        .foregroundStyle(colors.secondary)
                }
                .foregroundStyle(tint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, Theme.Spacing.xs)
            if !shut {
                // Griglia che segue la larghezza: una colonna su una finestra stretta, quattro su
                // una larga. Lo spazio diventa più progetti a vista, non righe più lunghe.
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: Self.cardMinWidth), spacing: Theme.Spacing.md),
                    ],
                    alignment: .leading,
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(section.projects) { workspace in
                        ProjectCard(
                            workspace: workspace,
                            tint: tint,
                            now: now,
                            colors: colors,
                            onOpen: { onOpenProject(workspace) },
                            onClose: { onCloseProject(workspace) }
                        )
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(.top, Theme.Spacing.xl)
    }
}

/// Un progetto del catalogo, in forma di card: il colore del gruppo sul bordo (pieno se aperto),
/// nome e da quanto è fermo sulla stessa riga, la cartella, le sessioni, e su hover l'azione
/// (Open su un chiuso, Close su un aperto). Click = apri.
private struct ProjectCard: View {
    let workspace: Workspace
    let tint: Color
    let now: Date
    let colors: ChromeColors
    let onOpen: () -> Void
    let onClose: () -> Void

    @State private var hovered = false

    var body: some View {
        let sessions = ProjectsModel.sessions(of: workspace)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(workspace.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(workspace.closed ? colors.secondary : colors.foreground)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if let age = SessionTriage.age(of: workspace.lastActiveAt, now: now) {
                    Text(age)
                        .font(Theme.Typography.subtitle)
                        .foregroundStyle(colors.secondary)
                }
            }
            Text(workspace.rootPath.map { ProjectsModel.displayPath($0) } ?? " ")
                .font(Theme.Typography.excerpt)
                .foregroundStyle(colors.secondary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: Theme.Spacing.sm) {
                sessionSummary(sessions)
                Spacer(minLength: Theme.Spacing.sm)
                Button(
                    workspace.closed ? "Open" : "Close",
                    action: workspace.closed ? onOpen : onClose
                )
                .buttonStyle(PageButtonStyle(colors: colors))
                .opacity(hovered ? 1 : 0)
                .help(workspace.closed ? "Open with its tabs" : "Close, keeping its sessions")
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(.leading, Theme.Spacing.md + 3)
        .padding(.trailing, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(hovered ? colors.rowSelected : colors.rowHover)
        )
        // Il colore del gruppo come bordo sinistro: dice l'appartenenza senza un'etichetta.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tint.opacity(workspace.closed ? 0.35 : 1))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private func sessionSummary(_ sessions: [WorkspaceModel.Tab]) -> some View {
        if let first = sessions.first {
            HStack(spacing: Theme.Spacing.xs + 2) {
                if !workspace.closed {
                    ForEach(sessions.prefix(4)) { tab in
                        let kind = BadgeKind.forTab(tab)
                        if kind == .none || kind == .pending {
                            StatusDot(color: colors.secondary, style: .ring, size: 7)
                        } else {
                            StatusDot(color: kind.tint(colors), size: 7)
                        }
                    }
                }
                Text(summary(first: first, count: sessions.count))
                    .font(Theme.Typography.tab)
                    .foregroundStyle(colors.secondary)
                    .lineLimit(1)
            }
        } else {
            Text(workspace.closed ? "No sessions" : "Shell")
                .font(Theme.Typography.tab)
                .foregroundStyle(colors.secondary.opacity(0.7))
        }
    }

    private func summary(first: WorkspaceModel.Tab, count: Int) -> String {
        let more = count > 1 ? ", +\(count - 1)" : ""
        let title = first.resume?.label ?? first.title
        return workspace.closed
            ? (count == 1 ? "1 to resume: " : "\(count) to resume: ") + title
            : title + more
    }
}
