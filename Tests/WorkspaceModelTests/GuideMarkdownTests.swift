import Foundation
import Testing
@testable import WorkspaceModel

/// La guida ha una fonte sola (`Guide.sections`) e due rese: il pannello in-app e `docs/GUIDE.md`.
/// Il file su disco è generato (`make guide-md`), quindi l'unico modo di sbagliare è dimenticarsi
/// di rigenerarlo: questo test è quel promemoria, e gira in CI come tutti gli altri.
struct GuideMarkdownTests {
    /// Risale alla root del package da questo file: i test non hanno una cwd garantita.
    private var repositoryRoot: URL {
        URL(filePath: #filePath) // Tests/WorkspaceModelTests/GuideMarkdownTests.swift
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func committedGuideMatchesTheGeneratedOne() throws {
        let path = repositoryRoot.appending(path: "docs/GUIDE.md")
        let committed = try String(contentsOf: path, encoding: .utf8)
        #expect(
            committed == GuideMarkdown.render(),
            "docs/GUIDE.md è disallineato dal contenuto della guida: lancia `make guide-md`."
        )
    }

    @Test func everySectionIsReachableAndUnique() {
        let ids = Guide.sections.map(\.id)
        #expect(Set(ids).count == ids.count) // gli slug finiscono nei link: niente collisioni
        for section in Guide.sections {
            #expect(!section.blocks.isEmpty)
            #expect(Guide.section(id: section.id)?.title == section.title)
        }
    }

    /// La tabella delle scorciatoie è generata dal modello: se qualcuno aggiunge un'azione senza
    /// toccare la guida deve comparire lo stesso. Qui si verifica che nessuna resti fuori.
    @Test func everyRemappableActionAppearsInTheShortcutTable() {
        let listed = Guide.shortcutGroups.flatMap(\.actions)
        #expect(Set(listed) == Set(ShortcutAction.allCases))
        #expect(Guide.sections.contains { section in
            section.blocks.contains { if case .allShortcuts = $0 { true } else { false } }
        })
    }

    @Test func searchNeedsEveryWordToMatch() {
        guard let sidebar = Guide.section(id: "sidebar") else {
            Issue.record("sezione sidebar assente")
            return
        }
        #expect(sidebar.matches("archive"))
        #expect(sidebar.matches("drag tab"))
        #expect(sidebar.matches("")) // filtro vuoto: passa tutto
        #expect(!sidebar.matches("archive kubernetes"))
    }

    /// Il markdown non deve dipendere dalle preferenze di chi lo genera: le combo sono i default.
    @Test func markdownUsesShippedDefaultsForShortcuts() {
        let rendered = GuideMarkdown.render(combo: { _ in "REMAPPED" })
        #expect(rendered.contains("REMAPPED"))
        #expect(!GuideMarkdown.render().contains("REMAPPED"))
        #expect(GuideMarkdown.render().contains(ShortcutAction.newTab.defaultCombo.display))
    }
}
