import SwiftUI
import WorkspaceModel

/// Singola tab della strip. View separata per lo stato locale (hover + editing): la x compare su
/// hover o sulla tab selezionata; il rename dal menu contestuale scambia il titolo con un
/// `TextField` inline.
struct PaneTabItem: View {
    let tab: WorkspaceModel.Tab
    /// La tab a schermo in questo pane (la selezionata della strip).
    let selected: Bool
    /// Il pane della strip ha il focus di tastiera: la selezione si mostra piena, altrove tenue.
    let focusedPane: Bool
    let canLeavePane: Bool
    let canMoveToNewWorkspace: Bool
    let canClosePane: Bool
    let canDeactivate: Bool
    let colors: ChromeColors
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onToggleUnread: () -> Void
    let onOpenInSplit: (SplitAxis) -> Void
    let onClosePane: () -> Void
    let onMoveToNewWorkspace: () -> Void
    let onDeactivate: () -> Void
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
            CloseButton(color: colors.secondary, size: 8, help: "Close Tab", action: onClose)
                .opacity(hovered || selected ? 1 : 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        // Lo stato è il riempimento: piena la selezionata del pane focused, tenue quella dei pane
        // non focused, trasparenti le altre. (Un pallino confliggerebbe col badge di stato agente.)
        .background(backgroundFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Rename…", action: beginRename)
            if canLeavePane {
                // Sposta la tab in un nuovo pane accanto, con la sua sessione viva (pattern
                // bonsplit). Nascosta se è l'unica della strip: dividerla accanto a sé stessa non
                // produce niente, e lo store lo rifiuterebbe.
                Button("Open in Split Right") { onOpenInSplit(.horizontal) }
                Button("Open in Split Down") { onOpenInSplit(.vertical) }
            }
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
            if canDeactivate {
                // Spegne l'agente ma tiene il binding: la tab resta, e riaprendola te lo
                // ripropone. Il costo di una sessione e' ~200 MB e una decina di processi, quello
                // di una tab spenta e' zero.
                Divider()
                Button("Deactivate Session", action: onDeactivate)
            }
            Divider()
            if canClosePane {
                // Chiude il pane e tutte le sue tab (le sessioni muoiono: conferma a monte).
                Button("Close Pane", role: .destructive, action: onClosePane)
            }
            Button("Close Tab", role: .destructive, action: onClose)
        }
    }

    /// Riempimento della pill: piena per la selezionata del pane focused, tenue se il pane non ha
    /// il focus (a schermo, ma la tastiera è altrove).
    private var backgroundFill: Color {
        guard selected else { return .clear }
        return focusedPane ? colors.selection : colors.selection.opacity(0.4)
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
