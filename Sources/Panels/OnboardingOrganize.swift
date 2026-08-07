import SwiftUI
import WorkspaceModel

/// Pagina "organizzazione" dell'onboarding: come si tiene in ordine la sidebar quando i workspace
/// diventano tanti - gruppi, pin, archivio e l'ordine che si muove da solo. Come le altre pagine
/// non usa screenshot: la mini sidebar a destra è fatta con la **card vera** (`GroupCard`) e i
/// componenti del design system, quindi segue il tema e non invecchia col codice.
struct OrganizePage: View {
    let colors: ChromeColors

    /// La card di esempio è viva: cliccando l'header si apre e si chiude come quella vera.
    @State private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            PageHeader(
                "Keep the sidebar calm",
                subtitle: "Workspaces pile up. Group the ones that belong together, pin what "
                    + "you live in, archive the rest.",
                colors: colors
            )
            HStack(alignment: .top, spacing: Theme.Spacing.lg * 1.5) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    point("rectangle.3.group", "Groups",
                          "A colored card around related workspaces. Right-click a row to make "
                              + "one, or drag rows in and out. Collapse it and the card tells you "
                              + "how many members still need you.")
                    point("pin", "Pinned stays on top",
                          "Pin a row or a whole group and it leads the list.")
                    point("archivebox", "Archive is one drag away",
                          "Drag a row onto the Archive section at the bottom, and back out when "
                              + "the project wakes up.")
                    point("arrow.right.doc.on.clipboard", "Tabs move between workspaces",
                          "Drag a tab out of its strip onto a workspace row: it lands there with "
                              + "its terminal still running.")
                }
                .frame(width: 250)
                miniSidebar
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(.top, Theme.Spacing.xs)
            Spacer(minLength: 0)
            Text("A workspace that finishes work while you are elsewhere moves to the top of "
                + "wherever it lives: the list, or its own group. A group stays where you put it.")
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(Theme.Typography.rowIcon)
                .foregroundStyle(colors.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.item.weight(.medium))
                    .foregroundStyle(colors.foreground)
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Mini sidebar: una riga pinned, la card (aperta o chiusa) e l'ancora dell'archivio.
    private var miniSidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            demoRow("pin.fill", "relay", tint: colors.accent)
            GroupCard(tint: tint, colors: colors, collapsed: collapsed) {
                cardHeader
                if !collapsed {
                    demoRow("folder", "api", tint: colors.secondary)
                    demoRow("folder", "web", tint: colors.secondary)
                    Color.clear.frame(height: Theme.Spacing.xs)
                }
            }
            demoRow("folder", "scratch", tint: colors.secondary)
            Divider().padding(.vertical, Theme.Spacing.xs)
            demoRow("archivebox", "Archive", tint: colors.secondary)
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(colors.surface)
        )
    }

    private var cardHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .frame(width: 10)
                Text("Client work")
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(colors.foreground)
                Spacer(minLength: 0)
                Text(collapsed ? "1" : "2")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(collapsed ? tint : colors.secondary)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func demoRow(_ symbol: String, _ name: String, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(Theme.Typography.rowIcon)
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(name)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            Spacer(minLength: 0)
            if name == "api" {
                AgentBadge(kind: .completed, colors: colors)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 5)
    }

    private var tint: Color {
        colors.group(WorkspaceGroup.colorIndices[3]) // blu della palette dei gruppi
    }
}
