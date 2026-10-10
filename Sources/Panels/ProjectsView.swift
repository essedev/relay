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
                .frame(maxWidth: Theme.Metrics.pageMaxWidth, alignment: .leading)
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
        .frame(maxWidth: 320)
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
                ForEach(section.projects) { workspace in
                    ProjectRow(
                        workspace: workspace,
                        tint: tint,
                        now: now,
                        colors: colors,
                        onOpen: { onOpenProject(workspace) },
                        onClose: { onCloseProject(workspace) }
                    )
                }
            }
        }
        .padding(.top, Theme.Spacing.xl)
    }
}

/// Una riga del catalogo: colore del gruppo (pieno se aperto), nome e cartella, sessioni, ultima
/// attività, e su hover l'azione (Open su un chiuso, Close su un aperto). Click = apri.
private struct ProjectRow: View {
    let workspace: Workspace
    let tint: Color
    let now: Date
    let colors: ChromeColors
    let onOpen: () -> Void
    let onClose: () -> Void

    @State private var hovered = false

    var body: some View {
        let sessions = ProjectsModel.sessions(of: workspace)
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint.opacity(workspace.closed ? 0.35 : 1))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(workspace.name)
                    .font(Theme.Typography.item)
                    .fontWeight(workspace.closed ? .regular : .medium)
                    .foregroundStyle(workspace.closed ? colors.secondary : colors.foreground)
                    .lineLimit(1)
                if let path = workspace.rootPath {
                    Text(ProjectsModel.displayPath(path))
                        .font(Theme.Typography.excerpt)
                        .foregroundStyle(colors.secondary.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
            sessionSummary(sessions)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let age = SessionTriage.age(of: workspace.lastActiveAt, now: now) {
                Text(age)
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(colors.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            Button(workspace.closed ? "Open" : "Close", action: workspace.closed ? onOpen : onClose)
                .buttonStyle(PageButtonStyle(colors: colors))
                .opacity(hovered ? 1 : 0)
                .help(workspace.closed ? "Open with its tabs" : "Close, keeping its sessions")
        }
        .padding(.vertical, Theme.Spacing.xs + 2)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(hovered ? colors.hover.opacity(0.5) : Color.clear)
        )
        .padding(.horizontal, -Theme.Spacing.md)
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
