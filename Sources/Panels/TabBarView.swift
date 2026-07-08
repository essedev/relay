import SwiftUI
import WorkspaceModel

/// Tab bar del workspace selezionato: i terminali del progetto, gestiti a tab. Pannello SwiftUI
/// isolato, montato sopra l'area del terminale (che è AppKit). Colori derivati dal tema corrente.
/// La chiusura è delegata all'app (`onCloseTab`), che può chiedere conferma se la tab è occupata.
public struct TabBarView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    let onCloseTab: (WorkspaceModel.Tab, Workspace) -> Void
    /// Sposta la tab in un nuovo workspace (menu contestuale). Risale all'app perché il nuovo
    /// workspace prende un nome placeholder gestito lì (`Workspace N`); la surface resta viva.
    let onMoveTabToNewWorkspace: (WorkspaceModel.Tab, Workspace) -> Void

    // Stato del riordino via drag & drop (vedi Reorderable), in un @GestureState che si azzera
    // da solo anche a gesto annullato. Nessun segmento: l'ordine è unico e niente freeze (le tab
    // non si ri-partizionano da sole durante un drag).
    @GestureState(resetTransaction: Transaction(animation: .easeInOut(duration: 0.2)))
    private var drag = ReorderDragState()
    @State private var tabFrames: [Int: CGRect] = [:]

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onCloseTab: @escaping (WorkspaceModel.Tab, Workspace) -> Void,
        onMoveTabToNewWorkspace: @escaping (WorkspaceModel.Tab, Workspace) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.onCloseTab = onCloseTab
        self.onMoveTabToNewWorkspace = onMoveTabToNewWorkspace
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        return Group {
            if let workspace = store.selectedWorkspace {
                content(for: workspace, colors: colors)
            } else {
                Color.clear
            }
        }
        .frame(height: Theme.Metrics.tabBarHeight)
        .background(colors.background)
    }

    private func content(for workspace: Workspace, colors: ChromeColors) -> some View {
        let space = "tabbar-reorder"
        let tabs = workspace.tabs
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    TabItemView(
                        tab: tab,
                        selected: tab.id == workspace.selectedTabID,
                        // Spostare l'unica tab svuoterebbe il workspace: la voce compare solo con
                        // almeno due tab (coerente col no-op dello store).
                        canMoveToNewWorkspace: tabs.count > 1,
                        colors: colors,
                        onSelect: { store.selectTab(tab.id, in: workspace) },
                        onRename: { store.renameTab(tab.id, in: workspace, to: $0) },
                        onToggleUnread: { store.toggleUnread(tab.id) },
                        onMoveToNewWorkspace: { onMoveTabToNewWorkspace(tab, workspace) },
                        onClose: { onCloseTab(tab, workspace) }
                    )
                    .reorderableRow(ReorderRowConfig(
                        id: tab.id,
                        index: index,
                        axis: .horizontal,
                        space: space,
                        count: tabs.count,
                        frames: tabFrames,
                        drag: $drag,
                        state: drag,
                        perform: { performMove(of: tab.id, to: $0, in: workspace) }
                    ))
                }
                Button { store.addTab(to: workspace) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(colors.secondary)
                .help("New tab")
                Spacer(minLength: 0)
            }
            .reorderableContainer(ReorderContainerConfig(
                space: space,
                axis: .horizontal,
                count: tabs.count,
                frames: $tabFrames,
                insertion: drag.insertion,
                lineColor: colors.accent
            ))
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    /// Inserisce la tab trascinata prima della tab `insertion` (o in fondo). Ordine unico: nessun
    /// vincolo di segmento, l'indicatore riflette sempre l'esito. Il reset del drag lo fa la
    /// resetTransaction del @GestureState.
    private func performMove(of dragID: UUID, to insertion: Int, in workspace: Workspace) {
        let targetID = insertion < workspace.tabs.count ? workspace.tabs[insertion].id : nil
        store.moveTab(dragID, before: targetID, in: workspace)
    }
}

/// Singola tab. View separata per lo stato locale (hover + editing): la x compare su hover o sulla
/// tab selezionata, così è sempre raggiungibile (anche con una sola tab) senza affollare la barra;
/// il rename dal menu contestuale scambia il titolo con un `TextField` inline.
private struct TabItemView: View {
    let tab: WorkspaceModel.Tab
    let selected: Bool
    let canMoveToNewWorkspace: Bool
    let colors: ChromeColors
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onToggleUnread: () -> Void
    let onMoveToNewWorkspace: () -> Void
    let onClose: () -> Void

    @State private var hovered = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            AgentBadge(kind: .forTab(tab), colors: colors)
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.tab)
                    .foregroundStyle(colors.foreground)
                    .frame(width: 90)
                    .focused($nameFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commit() }
                    }
                    .onAppear { DispatchQueue.main.async { nameFocused = true } }
            } else {
                Text(tab.title)
                    .font(Theme.Typography.tab)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Theme.Metrics.maxTabWidth, alignment: .leading)
            }
            CloseButton(color: colors.secondary, size: 8, help: "Close tab", action: onClose)
                .opacity(hovered || selected ? 1 : 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(selected ? colors.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Rename", action: beginRename)
            // Toggle manuale del marker di attenzione (metafora unread), per-tab. Solo `unseen`
            // (segnale forte, non visto) è "unread": lì offro "Mark as Read". Un `pending` è già
            // visto (quieto), quindi lo si può solo ri-alzare a forte ("Mark as Unread").
            let unreadLabel = tab.attention == .unseen ? "Mark as Read" : "Mark as Unread"
            Button(unreadLabel, action: onToggleUnread)
            if canMoveToNewWorkspace {
                // Estrae la tab in un nuovo workspace senza toccare la sessione viva (stesso
                // Tab.id -> surface intatta). Nascosta con una sola tab (sarebbe un no-op).
                Button("Move to New Workspace", action: onMoveToNewWorkspace)
            }
            Button("Close", role: .destructive, action: onClose)
        }
    }

    private func beginRename() {
        draft = tab.title
        editing = true
    }

    private func commit() {
        guard editing else { return }
        editing = false
        onRename(draft)
    }

    private func cancel() {
        editing = false
    }
}
