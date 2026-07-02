import Testing
@testable import WorkspaceModel

private let home = "/Users/doppia"

@Test @MainActor func programTitleWins() {
    let tab = Tab(title: "Branched rollout strategy", currentDirectory: "\(home)/dev")
    let workspace = Workspace(name: "w", rootPath: home, tabs: [tab])
    #expect(WindowTitle.compose(workspace: workspace, tab: tab, home: home)
        == "Branched rollout strategy")
}

@Test @MainActor func fallsBackToCurrentDirectoryAbbreviated() {
    let tab = Tab(currentDirectory: "\(home)/Development/Yellow/relay")
    let workspace = Workspace(name: "w", rootPath: home, tabs: [tab])
    #expect(WindowTitle.compose(workspace: workspace, tab: tab, home: home)
        == "~/Development/Yellow/relay")
}

@Test @MainActor func fallsBackToWorkspaceRootThenName() {
    let tab = Tab()
    let withRoot = Workspace(name: "w", rootPath: "\(home)/proj", tabs: [tab])
    #expect(WindowTitle.compose(workspace: withRoot, tab: tab, home: home) == "~/proj")

    let noRoot = Workspace(name: "Workspace 1", tabs: [Tab()])
    #expect(WindowTitle.compose(workspace: noRoot, tab: noRoot.tabs[0], home: home)
        == "Workspace 1")
}

@Test @MainActor func noWorkspaceShowsAppName() {
    #expect(WindowTitle.compose(workspace: nil, tab: nil, home: home) == "Relay")
}

@Test @MainActor func pathOutsideHomeIsNotAbbreviated() {
    let tab = Tab(currentDirectory: "/tmp/x")
    let workspace = Workspace(name: "w", tabs: [tab])
    #expect(WindowTitle.compose(workspace: workspace, tab: tab, home: home) == "/tmp/x")
}
