import Foundation
@testable import Panels
import Testing
import WorkspaceModel

// La palette "Go to project": quali progetti, in che ordine.

private func project(_ name: String, closed: Bool = false, path: String? = nil) -> Workspace {
    Workspace(name: name, rootPath: path, closed: closed, tabs: [Tab()])
}

@Test func openProjectsComeBeforeClosedOnes() {
    let results = PaletteModel.results(
        [project("Nexus closed", closed: true), project("Nexus")], query: "nex"
    )
    #expect(results.map(\.name) == ["Nexus", "Nexus closed"])
}

@Test func aBetterMatchWinsWithinTheSameState() {
    let results = PaletteModel.results(
        [
            project("Relay docs", path: "~/x"),
            project("Old", path: "~/Projects/docs-site"),
            project("Docs"),
            project("Yellow Docs"),
        ],
        query: "docs"
    )
    #expect(results.map(\.name) == ["Docs", "Relay docs", "Yellow Docs", "Old"])
}

@Test func lettersInOrderFindAProject() {
    let results = PaletteModel.results(
        [project("Yellow AI Adoption"), project("Zeno")], query: "yad"
    )
    #expect(results.map(\.name) == ["Yellow AI Adoption"])
}

@Test func anEmptyQueryListsEverythingUpToTheLimit() {
    let many = (0 ..< 20).map { project("p\($0)") }
    #expect(PaletteModel.results(many, query: " ").count == PaletteModel.limit)
}
