import SwiftUI
import WorkspaceModel

// Rendering e comandi delle card di gruppo. Estratti da `SidebarView` per il budget di dimensione
// dei tipi (vedi CONVENTIONS).

extension SidebarView {
    /// Card di un gruppo: header, membri rientrati e la riga di coda che dà uno slot proprio al
    /// "sotto la card" (vedi `SidebarLayout`).
    func groupCard(
        _ group: WorkspaceGroup,
        members: [Workspace],
        plan: SidebarLayout.Plan,
        colors: ChromeColors
    ) -> some View {
        GroupCard(
            tint: colors.group(group.safeColorIndex),
            colors: colors,
            collapsed: group.collapsed
        ) {
            draggable(.group(group.id), plan: plan, row: .groupHeader(group.id)) {
                GroupHeaderRow(
                    group: group,
                    members: members,
                    colors: colors,
                    actions: groupActions(group)
                )
            }
            if !group.collapsed {
                ForEach(members) { member in
                    draggable(
                        .workspace(member.id),
                        plan: plan,
                        row: .member(member.id, group: group.id)
                    ) {
                        makeRow(member, colors: colors)
                    }
                }
                // Riga di coda: è insieme il padding inferiore della card e lo slot "sotto la
                // card" del drag. Alta quanto il padding degli altri lati, non di più.
                Color.clear
                    .frame(height: Theme.Spacing.xs)
                    .sidebarReorderSlot(
                        index: plan.index(of: .groupTail(group.id)),
                        space: Self.space,
                        onFrame: { frames[$0] = $1 }
                    )
            }
        }
    }

    func groupActions(_ group: WorkspaceGroup) -> GroupActions {
        GroupActions(
            onToggleCollapse: {
                withAnimation(.easeInOut(duration: 0.2)) { store.toggleGroupCollapsed(group.id) }
            },
            onRename: { store.renameGroup(group.id, to: $0) },
            onSetColor: { store.setGroupColor(group.id, colorIndex: $0) },
            onTogglePin: { withAnimation { store.toggleGroupPin(group.id) } },
            onUngroup: { withAnimation { store.ungroup(group.id) } }
        )
    }

    /// Voci di gruppo del menu contestuale di una riga. Un archiviato non le ha: nell'archivio non
    /// ci sono card (entrare in un gruppo lo ripescherebbe fuori, che è il lavoro di "Unarchive").
    func groupMenu(for workspace: Workspace) -> WorkspaceGroupMenu? {
        guard !workspace.archived else { return nil }
        let others = store.groups.filter { group in
            group.id != workspace.groupID
                && store.members(of: group.id).contains { $0.windowID == windowID }
        }
        return WorkspaceGroupMenu(
            inGroup: workspace.groupID != nil,
            available: others.map { ($0.id, $0.name) },
            onNewGroup: {
                withAnimation {
                    _ = store.createGroup(name: "New Group", with: [workspace.id])
                }
            },
            onAddToGroup: { groupID in
                withAnimation { store.addToGroup(workspace.id, group: groupID) }
            },
            onRemoveFromGroup: { withAnimation { store.removeFromGroup(workspace.id) } }
        )
    }
}
