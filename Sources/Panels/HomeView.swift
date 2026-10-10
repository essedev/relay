import AgentProtocol
import SwiftUI
import WorkspaceModel

/// Pagina Home: il triage dei progetti aperti. Il titolo dice la situazione ("3 sessions need
/// you"), poi le sessioni che ti aspettano con l'azione che serve, quelle al lavoro, i progetti
/// fermi da mettere via e quelli chiusi di recente. Copre il right pane della finestra
/// (`RelayWindow.page`), i terminali restano montati sotto.
///
/// Colonna leggibile (`Theme.Metrics.pageMaxWidth`): l'azione di una riga resta accanto al testo
/// che la motiva.
public struct HomeView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    /// Porta in vista una sessione (seleziona progetto e tab).
    let onOpenSession: (Workspace, WorkspaceModel.Tab) -> Void
    /// Riapre (o seleziona) un progetto.
    let onOpenProject: (Workspace) -> Void
    /// Chiude dei progetti fermi: il composition root chiede conferma se c'è lavoro in corso.
    let onCloseProjects: ([Workspace]) -> Void
    /// L'ultima riga dell'agente in una tab (la domanda, l'errore), se il terminale è vivo.
    let peek: (UUID) -> String?

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onOpenSession: @escaping (Workspace, WorkspaceModel.Tab) -> Void,
        onOpenProject: @escaping (Workspace) -> Void,
        onCloseProjects: @escaping ([Workspace]) -> Void,
        peek: @escaping (UUID) -> String? = { _ in nil }
    ) {
        self.store = store
        self.settings = settings
        self.onOpenSession = onOpenSession
        self.onOpenProject = onOpenProject
        self.onCloseProjects = onCloseProjects
        self.peek = peek
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        // L'età delle righe ("4m") invecchia anche a pagina ferma.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                content(colors, now: context.date)
                    .frame(maxWidth: Theme.Metrics.pageMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.page)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func content(_ colors: ChromeColors, now: Date) -> some View {
        let workspaces = store.workspaces
        let needs = HomeModel.needsYou(workspaces)
        let working = HomeModel.working(workspaces)
        let quiet = HomeModel.quiet(workspaces, now: now)
        let closed = HomeModel.recentlyClosed(workspaces)
        return VStack(alignment: .leading, spacing: 0) {
            Text(HomeModel.headline(needing: needs.count))
                .font(Theme.Typography.pageTitle)
                .foregroundStyle(colors.foreground)
            Text(summary(working: working.count, all: workspaces))
                .font(Theme.Typography.pageSubtitle)
                .foregroundStyle(colors.secondary)
                .padding(.top, Theme.Spacing.xs)
            if !needs.isEmpty { needsSection(needs, colors: colors, now: now) }
            if !working.isEmpty { workingSection(working, colors: colors, now: now) }
            if !quiet.isEmpty {
                heading("Quiet for a week", colors)
                QuietRow(projects: quiet, colors: colors) { onCloseProjects(quiet) }
            }
            if !closed.isEmpty { closedSection(closed, colors: colors, now: now) }
        }
    }

    private func needsSection(
        _ needs: [HomeModel.Entry], colors: ChromeColors, now: Date
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(needs.enumerated()), id: \.element.id) { index, entry in
                NeedsYouRow(
                    entry: entry,
                    excerpt: peek(entry.tab.id),
                    now: now,
                    colors: colors,
                    divided: index > 0,
                    onOpen: { onOpenSession(entry.workspace, entry.tab) }
                )
            }
        }
        .padding(.top, Theme.Spacing.lg)
    }

    @ViewBuilder
    private func workingSection(
        _ working: [HomeModel.Entry], colors: ChromeColors, now: Date
    ) -> some View {
        heading("Working", colors)
        ForEach(working) { entry in
            WorkingRow(entry: entry, now: now, colors: colors) {
                onOpenSession(entry.workspace, entry.tab)
            }
        }
    }

    @ViewBuilder
    private func closedSection(
        _ closed: [Workspace], colors: ChromeColors, now: Date
    ) -> some View {
        heading("Recently closed", colors)
        FlowLayout {
            ForEach(closed) { workspace in
                ProjectChip(
                    workspace: workspace,
                    tint: colors.tint(of: workspace, in: store),
                    now: now,
                    colors: colors
                ) {
                    onOpenProject(workspace)
                }
            }
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func summary(working: Int, all: [Workspace]) -> String {
        let agents = working == 1 ? "1 agent working" : "\(working) agents working"
        let open = all.count { !$0.closed }
        return "\(agents), \(open) projects open, \(all.count - open) closed."
    }

    private func heading(_ title: String, _ colors: ChromeColors) -> some View {
        Text(title)
            .font(Theme.Typography.pageHeading)
            .foregroundStyle(colors.foreground)
            .padding(.top, Theme.Spacing.page - Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xs)
    }
}

/// Una sessione che ti aspetta: progetto, stato a parole nel suo colore, chat, l'ultima riga
/// dell'agente e l'azione che serve. Il colore sta nel pallino e nella parola, non in una barra.
private struct NeedsYouRow: View {
    let entry: HomeModel.Entry
    let excerpt: String?
    let now: Date
    let colors: ChromeColors
    let divided: Bool
    let onOpen: () -> Void

    @State private var hovered = false

    var body: some View {
        let kind = BadgeKind.forTab(entry.tab)
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            StatusDot(color: kind.tint(colors))
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(entry.workspace.name)
                        .font(Theme.Typography.title)
                        .foregroundStyle(colors.foreground)
                    Text(Self.verb(kind))
                        .font(Theme.Typography.tab)
                        .foregroundStyle(kind.tint(colors))
                    Spacer(minLength: Theme.Spacing.sm)
                    if let age = SessionTriage.age(
                        of: SessionTriage.ageDate(for: entry.tab),
                        now: now
                    ) {
                        Text(age)
                            .font(Theme.Typography.subtitle)
                            .foregroundStyle(colors.secondary)
                    }
                }
                Text(entry.tab.title)
                    .font(Theme.Typography.item)
                    .foregroundStyle(colors.secondary)
                    .lineLimit(1)
                if let excerpt {
                    Text(excerpt)
                        .font(Theme.Typography.excerpt)
                        .foregroundStyle(colors.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs + 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                .fill(colors.terminalWell)
                        )
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            Button(Self.action(kind), action: onOpen)
                .buttonStyle(PageButtonStyle(colors: colors))
                .padding(.top, 1)
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .fill(hovered ? colors.hover.opacity(0.5) : Color.clear)
        )
        .overlay(alignment: .top) {
            if divided, !hovered {
                Rectangle().fill(colors.hairline).frame(height: 1)
                    .padding(.horizontal, Theme.Spacing.md)
            }
        }
        .padding(.horizontal, -Theme.Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovered = $0 }
    }

    /// Lo stato a parole: cosa sta succedendo dal tuo punto di vista.
    static func verb(_ kind: BadgeKind) -> String {
        switch kind {
        case .needsInput: "waiting for your answer"
        case .error: "stopped with an error"
        default: "finished, not reviewed"
        }
    }

    /// Il verbo del bottone dice cosa farai, non dove andrai.
    static func action(_ kind: BadgeKind) -> String {
        switch kind {
        case .needsInput: "Answer"
        case .error: "Check"
        default: "Review"
        }
    }
}

/// Una sessione al lavoro da sola: riga compatta, il dettaglio è nel terminale.
private struct WorkingRow: View {
    let entry: HomeModel.Entry
    let now: Date
    let colors: ChromeColors
    let onOpen: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            StatusDot(color: colors.running)
            Text(entry.workspace.name)
                .font(Theme.Typography.item)
                .fontWeight(.medium)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(entry.tab.title)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.secondary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.sm)
            if let age = SessionTriage.age(of: entry.tab.lastEventAt, now: now) {
                Text(age)
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(colors.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
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
}

/// Progetti aperti ma fermi: una frase e un'azione sola.
private struct QuietRow: View {
    let projects: [Workspace]
    let colors: ChromeColors
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            (Text(names).foregroundStyle(colors.foreground).fontWeight(.medium)
                + Text(projects.count == 1 ? " has" : " have")
                .foregroundStyle(colors.secondary)
                + Text(" not moved in over a week. Closing frees their terminals; the sessions "
                    + "stay resumable.").foregroundStyle(colors.secondary))
                .font(Theme.Typography.item)
                .lineSpacing(3)
            Spacer(minLength: 0)
            Button(projects.count == 1 ? "Close It" : "Close \(projects.count)", action: onClose)
                .buttonStyle(PageButtonStyle(colors: colors))
        }
    }

    private var names: String {
        let list = projects.map(\.name)
        guard list.count > 1 else { return list.first ?? "" }
        return list.dropLast().joined(separator: ", ") + " and " + (list.last ?? "")
    }
}

/// Un progetto in forma di chip: colore del gruppo, nome, da quanto è fermo. Click = apri.
struct ProjectChip: View {
    let workspace: Workspace
    /// Il colore del suo gruppo (grigio se non ne ha uno).
    let tint: Color
    let now: Date
    let colors: ChromeColors
    let onOpen: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(workspace.name)
                .font(Theme.Typography.tab)
                .foregroundStyle(colors.foreground)
            if let age = SessionTriage.age(of: workspace.lastActiveAt, now: now) {
                Text(age)
                    .font(Theme.Typography.tab)
                    .foregroundStyle(colors.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md - 1)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(hovered ? colors.hover : colors.surface.opacity(0.7))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovered = $0 }
        .help("Open \(workspace.name)")
    }
}

/// Bottone delle pagine: piccolo, pieno tenue, nel registro della chrome.
struct PageButtonStyle: ButtonStyle {
    let colors: ChromeColors
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.tab)
            .foregroundStyle(prominent ? colors.background : colors.foreground)
            .padding(.horizontal, Theme.Spacing.md - 1)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(prominent ? colors.accent : colors.selection.opacity(
                        configuration.isPressed ? 1 : 0.7
                    ))
            )
            .contentShape(Rectangle())
    }
}
