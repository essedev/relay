import SwiftUI
import WorkspaceModel

/// Resa di un blocco della guida coi componenti del design system. Il gemello di questo file è
/// `GuideMarkdown` (WorkspaceModel), che rende gli stessi blocchi in `docs/GUIDE.md`: se aggiungi
/// un `GuideBlock`, i posti da toccare sono due e il compilatore te li indica entrambi.
///
/// Le combinazioni di tasti vengono da `settings.binding(for:)`: se l'utente rimappa un'azione, la
/// guida mostra la sua combinazione. È il motivo per cui il contenuto cita `ShortcutAction` invece
/// di scrivere i tasti.
struct GuideBlockView: View {
    let block: GuideBlock
    let settings: AppSettings
    let colors: ChromeColors

    var body: some View {
        switch block {
        case let .paragraph(text):
            Text(text)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .topics(topics):
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(topics) { topic in
                    topicRow(topic)
                }
            }
        case let .steps(steps):
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    stepRow(index + 1, step)
                }
            }
        case let .shortcuts(shortcuts):
            shortcutTable(shortcuts)
        case .allShortcuts:
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(Guide.shortcutGroups, id: \.group) { group, actions in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(group.title.uppercased())
                            .font(Theme.Typography.sectionHeader)
                            .foregroundStyle(colors.secondary)
                        shortcutTable(actions.map {
                            .action($0, Guide.shortcutNotes[$0] ?? "")
                        })
                    }
                }
            }
        case let .command(command, note):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                CommandChip(command, colors: colors, selectable: true)
                Text(note)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .note(text):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(colors.accent)
                Text(text)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(colors.surface)
            )
        }
    }

    private func topicRow(_ topic: GuideTopic) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: topic.symbol)
                .font(Theme.Typography.rowIcon)
                .foregroundStyle(colors.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(Theme.Typography.item.weight(.medium))
                    .foregroundStyle(colors.foreground)
                Text(topic.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text("\(number)")
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(colors.accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(colors.selection))
            Text(text)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Griglia tasti/azione/nota. `Grid` e non una tabella: le colonne si allineano da sole e la
    /// nota può andare a capo senza spingere la colonna dei tasti.
    private func shortcutTable(_ shortcuts: [GuideShortcut]) -> some View {
        Grid(
            alignment: .leadingFirstTextBaseline,
            horizontalSpacing: Theme.Spacing.md,
            verticalSpacing: Theme.Spacing.xs
        ) {
            ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                GridRow {
                    CommandChip(keys(shortcut), colors: colors, minWidth: 52)
                        .gridColumnAlignment(.trailing)
                    Text(shortcut.title)
                        .font(Theme.Typography.item)
                        .foregroundStyle(colors.foreground)
                        .fixedSize()
                    Text(shortcut.detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(colors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .gridColumnAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func keys(_ shortcut: GuideShortcut) -> String {
        shortcut.keys { settings.binding(for: $0).display }
    }
}
