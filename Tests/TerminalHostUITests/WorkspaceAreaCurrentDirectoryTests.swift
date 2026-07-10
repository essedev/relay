import AppKit
import Core
import Foundation
import TerminalEngine
@testable import TerminalHostUI
import Testing
import WorkspaceModel

// Precedenza delle fonti della cwd nell'area: la shell viva batte l'ultimo OSC 7 noto. Regressione
// del bug in cui l'ordine era invertito: siccome dopo il primo `Cmd+T` la tab ha sempre una cwd
// memorizzata, la lettura live non veniva mai consultata e l'ereditarietà restava cieca ai `cd`.

/// Surface finta: dichiara una cwd viva diversa da quella memorizzata sulla tab. Nessun pty (il pty
/// vero è coperto in `TerminalEngineTests`), qui interessa solo quale fonte vince.
@MainActor
private final class FakeSurface: TerminalSurfaceHandle {
    let id = UUID()
    let view = NSView()
    var onTitleChanged: ((String) -> Void)?
    var onDirectoryChanged: ((String) -> Void)?
    var liveDirectory: String?

    init(liveDirectory: String?) {
        self.liveDirectory = liveDirectory
    }

    func start() {}
    func teardown() {}
    func apply(theme _: RelayTheme) {}
    func foregroundProcessName() -> String? {
        nil
    }

    func foregroundCommandLine() -> [String]? {
        nil
    }

    func currentDirectory() -> String? {
        liveDirectory
    }

    func hasRunningChildren() -> Bool {
        false
    }

    func sendText(_: String) {}
    func clear() {}
    func search(_: String, forward _: Bool) -> (current: Int, total: Int) {
        (0, 0)
    }

    func endSearch() {}
}

@MainActor
private final class FakeEngine: TerminalEngine {
    var liveDirectory: String?

    init(liveDirectory: String?) {
        self.liveDirectory = liveDirectory
    }

    func makeSurface(
        cwd _: String?,
        shell _: String?,
        env _: [String: String]
    ) -> TerminalSurfaceHandle {
        FakeSurface(liveDirectory: liveDirectory)
    }
}

/// Monta l'area e realizza la surface della tab selezionata (è `render()` a crearla, al primo
/// accesso alla view).
@MainActor
private func makeArea(store: WorkspaceStore, liveDirectory: String?) -> WorkspaceAreaController {
    let area = WorkspaceAreaController(
        store: store,
        engine: FakeEngine(liveDirectory: liveDirectory),
        settings: AppSettings()
    )
    area.loadViewIfNeeded()
    return area
}

@MainActor
@Test func liveShellDirectoryWinsOverTheStoredOne() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "relay", rootPath: "/repo")
    let tab = workspace.tabs[0]
    tab.currentDirectory = "/repo" // ultimo OSC 7 noto, fermo a un prompt precedente
    let area = makeArea(store: store, liveDirectory: "/repo/Sources")

    // La shell è viva e sa di essere altrove: `Cmd+T` deve aprire lì, non su /repo.
    #expect(area.currentDirectory(for: tab.id) == "/repo/Sources")
}

@MainActor
@Test func storedDirectoryServesWhenTheShellIsNotRealized() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "relay", rootPath: "/repo")
    let tab = workspace.tabs[0]
    tab.currentDirectory = "/repo/Sources"
    // Surface realizzata ma senza cwd viva (shell morta / sfrattata dal cap LRU).
    let area = makeArea(store: store, liveDirectory: nil)

    #expect(area.currentDirectory(for: tab.id) == "/repo/Sources")
}

@MainActor
@Test func workspaceRootIsTheLastResortInTheArea() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "relay", rootPath: "/repo")
    let tab = workspace.tabs[0]
    let area = makeArea(store: store, liveDirectory: nil) // nessuna fonte, nessun OSC 7

    #expect(area.currentDirectory(for: tab.id) == "/repo")
}

@MainActor
@Test func unknownTabHasNoDirectory() {
    let store = WorkspaceStore()
    store.createWorkspace(name: "relay", rootPath: "/repo")
    let area = makeArea(store: store, liveDirectory: "/live")

    #expect(area.currentDirectory(for: UUID()) == nil)
}
