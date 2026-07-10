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
private func makeArea(
    store: WorkspaceStore,
    liveDirectory: String? = nil,
    windowID: UUID = RelayWindow.mainID,
    registry: SurfaceRegistry? = nil
) -> WorkspaceAreaController {
    let area = WorkspaceAreaController(
        store: store,
        engine: FakeEngine(liveDirectory: liveDirectory),
        settings: AppSettings(),
        windowID: windowID,
        registry: registry
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

// MARK: - Reconcile dell'albero di pane

@MainActor
@Test func splittingMountsASecondPaneWithoutRecreatingTheFirst() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay", rootPath: "/repo")
    let first = ws.tabs[0]
    let area = makeArea(store: store, liveDirectory: nil)
    let firstTerminal = try #require(area.mountedTerminal(for: first.id))

    let second = try #require(store.splitFocusedPane(axis: .horizontal))
    area.renderNow()

    #expect(area.mountedTabIDs == Set([first.id, second.id]))
    // Il pane preesistente non è stato ricreato: la sua surface (e il pty) sopravvive al reconcile.
    #expect(area.mountedTerminal(for: first.id) === firstTerminal)
    #expect(area.liveSurfaceCount == 2)
}

@MainActor
@Test func closingAPaneUnmountsItButKeepsTheSurfaceAlive() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay", rootPath: "/repo")
    let first = ws.tabs[0]
    let area = makeArea(store: store, liveDirectory: nil)
    let second = try #require(store.splitFocusedPane(axis: .vertical))
    area.renderNow()

    store.closeFocusedPane()
    area.renderNow()

    #expect(area.mountedTabIDs == Set([first.id]))
    // La tab resta viva nella tab bar, quindi la sua surface non va distrutta: solo smontata.
    #expect(area.liveSurfaceCount == 2)
    #expect(ws.tabs.contains { $0.id == second.id })
}

@MainActor
@Test func closingATabTearsDownItsSurface() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay", rootPath: "/repo")
    let area = makeArea(store: store, liveDirectory: nil)
    let second = try #require(store.splitFocusedPane(axis: .horizontal))
    area.renderNow()
    #expect(area.liveSurfaceCount == 2)

    store.closeTab(second.id, in: ws)
    area.renderNow()

    #expect(area.mountedTabIDs.count == 1)
    #expect(area.liveSurfaceCount == 1) // qui la sessione muore davvero
}

@MainActor
@Test func aWindowShowsItsOwnWorkspaceNotTheKeyOne() throws {
    let store = WorkspaceStore()
    let main = store.createWorkspace(name: "main")
    let other = store.createWorkspace(name: "other")
    let window = try #require(store.moveWorkspaceToNewWindow(other.id))
    // L'area della finestra principale, mentre la key è l'altra.
    let area = makeArea(store: store, liveDirectory: nil, windowID: RelayWindow.mainID)

    #expect(store.keyWindowID == window.id)
    #expect(area.mountedTabIDs == Set(main.tabs.map(\.id))) // mostra il suo, non quello della key
}

@MainActor
@Test func twoWindowsShareOneSurfacePerTab() throws {
    // La registry è condivisa: una tab ha una surface sola, ovunque sia montata. Se ogni finestra
    // avesse la sua, spostare un workspace di finestra ricreerebbe i pty e ucciderebbe le sessioni.
    let store = WorkspaceStore()
    let main = store.createWorkspace(name: "main")
    let moved = store.createWorkspace(name: "moved")
    let registry = SurfaceRegistry(engine: FakeEngine(liveDirectory: nil))
    let window = try #require(store.moveWorkspaceToNewWindow(moved.id))

    let mainArea = makeArea(store: store, windowID: RelayWindow.mainID, registry: registry)
    let otherArea = makeArea(store: store, windowID: window.id, registry: registry)

    #expect(mainArea.mountedTabIDs == Set(main.tabs.map(\.id)))
    #expect(otherArea.mountedTabIDs == Set(moved.tabs.map(\.id)))
    // Due aree, due tab, due surface: nessuna duplicazione, nessuna surface per finestra.
    #expect(registry.liveSurfaceCount == 2)
    #expect(mainArea.liveSurfaceCount == otherArea.liveSurfaceCount)
}
