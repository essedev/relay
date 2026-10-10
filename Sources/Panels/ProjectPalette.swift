import SwiftUI
import WorkspaceModel

/// Palette "Go to project" (`⌘P`): scrivi un pezzo del nome, frecce per scegliere, Invio per
/// andarci. Un progetto chiuso si riapre con le sue tab, pronte da riprendere. Overlay
/// full-window (`FullOverlayPresenter`): mentre è su, il monitor tastiera si fa da parte.
public struct ProjectPalette: View {
    let store: WorkspaceStore
    let settings: AppSettings
    let onOpen: (Workspace) -> Void
    let onNewProject: () -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedID: UUID?
    @FocusState private var fieldFocused: Bool

    private static let width: CGFloat = 580

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onOpen: @escaping (Workspace) -> Void,
        onNewProject: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.onOpen = onOpen
        self.onNewProject = onNewProject
        self.onClose = onClose
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let results = PaletteModel.results(store.workspaces, query: query)
        // GeometryReader: l'host dell'overlay non propone una misura, e senza il fondo si
        // stringerebbe attorno al pannello invece di coprire la finestra.
        GeometryReader { _ in
            ZStack(alignment: .top) {
                // Fondo: attenua il resto e chiude al click fuori dal pannello.
                Color.black.opacity(0.45)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                panel(results, colors)
                    .padding(.top, 70)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onExitCommand(perform: onClose)
        .onAppear { selectedID = results.first?.id }
        .onChange(of: query) { _, _ in
            selectedID = PaletteModel.results(store.workspaces, query: query).first?.id
        }
        // Il focus del campo: l'`onAppear` corre contro il primo layout, il `task` ritenta.
        .task { fieldFocused = true }
    }

    private func panel(_ results: [Workspace], _ colors: ChromeColors) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md - 2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(colors.secondary)
                TextField("Go to project\u{2026}", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(colors.foreground)
                    .focused($fieldFocused)
                    .onSubmit { open(results) }
                    .onKeyPress(.downArrow) { move(1, in: results) }
                    .onKeyPress(.upArrow) { move(-1, in: results) }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            Rectangle().fill(colors.hairline).frame(height: 1)
            ScrollViewReader { scroller in
                ScrollView {
                    list(results, colors)
                        .padding(Theme.Spacing.xs + 2)
                }
                .relayScrollIndicator(colors)
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selectedID) { _, id in scroller.scrollTo(id) }
            }
            Rectangle().fill(colors.hairline).frame(height: 1)
            hints(colors)
        }
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: 14).fill(colors.raised))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
    }

    @ViewBuilder
    private func list(_ results: [Workspace], _ colors: ChromeColors) -> some View {
        if results.isEmpty {
            Text("No project matches. Return creates one from a folder.")
                .font(Theme.Typography.tab)
                .foregroundStyle(colors.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, workspace in
                    if index == 0 || results[index - 1].closed != workspace.closed {
                        Text(workspace.closed ? "Closed" : "Open")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(colors.secondary)
                            .padding(.horizontal, Theme.Spacing.sm + 2)
                            .padding(.top, Theme.Spacing.sm)
                            .padding(.bottom, Theme.Spacing.xs)
                    }
                    PaletteRow(
                        workspace: workspace,
                        tint: colors.tint(of: workspace, in: store),
                        selected: workspace.id == selectedID,
                        colors: colors
                    )
                    .id(workspace.id)
                    .onTapGesture { onOpen(workspace) }
                    .onHover { if $0 { selectedID = workspace.id } }
                }
            }
        }
    }

    private func hints(_ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            Text("\u{2191}\u{2193} choose")
            Text("\u{21A9} open, or reopen with its sessions")
            Text("esc close")
        }
        .font(Theme.Typography.subtitle)
        .foregroundStyle(colors.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func move(_ step: Int, in results: [Workspace]) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        let current = results.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + step, 0), results.count - 1)
        selectedID = results[next].id
        return .handled
    }

    private func open(_ results: [Workspace]) {
        if let workspace = results.first(where: { $0.id == selectedID }) ?? results.first {
            onOpen(workspace)
        } else {
            onNewProject()
        }
    }
}

/// Una riga della palette: colore del gruppo, nome, cartella, e a destra cosa succede aprendolo.
private struct PaletteRow: View {
    let workspace: Workspace
    let tint: Color
    let selected: Bool
    let colors: ChromeColors

    var body: some View {
        HStack(spacing: Theme.Spacing.md - 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(workspace.name)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .fixedSize()
            if let path = workspace.rootPath {
                Text(ProjectsModel.displayPath(path))
                    .font(Theme.Typography.excerpt)
                    .foregroundStyle(colors.secondary.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(detail)
                .font(Theme.Typography.tab)
                .foregroundStyle(colors.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, Theme.Spacing.xs + 3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(selected ? colors.selection : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var detail: String {
        guard workspace.closed else { return workspace.selectedTab?.title ?? "" }
        let sessions = ProjectsModel.sessions(of: workspace).count
        return sessions == 0 ? "fresh shell" : "\(sessions) to resume"
    }
}
