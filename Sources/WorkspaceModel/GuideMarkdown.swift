import Foundation

/// Rende `Guide.sections` in markdown: è `docs/GUIDE.md`, generato da `make guide-md` e verificato
/// da un test (`GuideMarkdownTests`), non scritto a mano. La resa in-app vive in `Panels/GuideView`
/// e legge lo stesso dato: due prose separate divergerebbero, una resa generata no.
///
/// Le combinazioni di tasti qui sono i **default** di fabbrica (`ShortcutAction.defaultCombo`), non
/// i binding dell'utente: un file committato non può dipendere da chi lo genera. Nel pannello, che
/// gira dentro l'app, le stesse righe mostrano le combo vere.
public enum GuideMarkdown {
    /// L'intero documento, header compreso. `combo` è iniettabile per i test.
    public static func render(
        sections: [GuideSection] = Guide.sections,
        combo: (ShortcutAction) -> String = { $0.defaultCombo.display }
    ) -> String {
        var lines: [String] = [
            "# Relay - user guide",
            "",
            "Everything Relay can do, in one place. Generated from the app's own guide "
                + "(`make guide-md`):",
            "edit `Sources/WorkspaceModel/Guide*.swift`, not this file.",
            "",
            "Open the same guide inside the app from **Help > Relay Guide**.",
            "",
        ]
        lines.append(contentsOf: tableOfContents(sections))
        for section in sections {
            lines.append(contentsOf: render(section: section, combo: combo))
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    private static func tableOfContents(_ sections: [GuideSection]) -> [String] {
        var lines = ["## Contents", ""]
        for section in sections {
            lines.append("- [\(section.title)](#\(section.id)) - \(section.summary)")
        }
        lines.append("")
        return lines
    }

    private static func render(
        section: GuideSection,
        combo: (ShortcutAction) -> String
    ) -> [String] {
        // L'ancora esplicita tiene lo slug stabile anche se il titolo cambia (GitHub la rispetta).
        var lines = ["<a id=\"\(section.id)\"></a>", "", "## \(section.title)", ""]
        for block in section.blocks {
            lines.append(contentsOf: render(block: block, combo: combo))
        }
        return lines
    }

    private static func render(
        block: GuideBlock,
        combo: (ShortcutAction) -> String
    ) -> [String] {
        switch block {
        case let .paragraph(text):
            wrap(text) + [""]
        case let .topics(topics):
            topics.flatMap { wrap("**\($0.title)** - \($0.detail)", bullet: "- ") } + [""]
        case let .steps(steps):
            steps.enumerated().flatMap { index, step in
                wrap(step, bullet: "\(index + 1). ")
            } + [""]
        case let .shortcuts(shortcuts):
            shortcutTable(shortcuts.map {
                Row(keys: $0.keys(combo), title: $0.title, detail: $0.detail)
            })
        case .allShortcuts:
            Guide.shortcutGroups.flatMap { group, actions in
                ["### \(group.title)", ""] + shortcutTable(actions.map {
                    Row(keys: combo($0), title: $0.label, detail: Guide.shortcutNotes[$0] ?? "")
                })
            }
        case let .command(command, note):
            ["```sh", command, "```", ""] + wrap(note) + [""]
        case let .note(text):
            wrap("**Note:** \(text)") + [""]
        }
    }

    /// Una riga della tabella scorciatoie nel markdown.
    private struct Row {
        let keys: String
        let title: String
        let detail: String
    }

    private static func shortcutTable(_ rows: [Row]) -> [String] {
        var lines = ["| Keys | Action | Notes |", "| --- | --- | --- |"]
        for row in rows {
            lines.append("| `\(row.keys)` | \(row.title) | \(row.detail) |")
        }
        lines.append("")
        return lines
    }

    /// A capo a 100 colonne, il limite di riga del progetto: un markdown generato deve passare gli
    /// stessi controlli del resto del repo. Le parole non si spezzano mai.
    private static func wrap(_ text: String, bullet: String = "", limit: Int = 100) -> [String] {
        let indent = String(repeating: " ", count: bullet.count)
        var lines: [String] = []
        var current = bullet
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty || current == bullet || current == indent
                ? current + word
                : current + " " + word
            if candidate.count > limit, current != bullet, current != indent {
                lines.append(current)
                current = indent + word
            } else {
                current = String(candidate)
            }
        }
        if current != bullet, current != indent { lines.append(current) }
        return lines
    }
}

public extension GuideShortcut {
    /// I tasti della riga: per un'azione li conosce il chiamante (binding vivi nel pannello,
    /// default nel markdown), per una riga fissa sono scritti nel contenuto.
    func keys(_ combo: (ShortcutAction) -> String) -> String {
        switch self {
        case let .action(action, _): combo(action)
        case let .fixed(keys, _, _): keys
        }
    }
}
