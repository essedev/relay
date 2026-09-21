import AppKit
import Core
import TerminalEngine
@testable import TerminalHostUI
import Testing

// L'ambiente di una surface è l'unico canale fra l'app e gli hook dell'agente: la shell non eredita
// l'ambiente del processo (l'engine ne costruisce uno minimo), quindi ciò che non è iniettato qui
// per l'hook non esiste. Sbagliarlo non rompe niente in modo visibile, semplicemente gli eventi
// vanno altrove.

@MainActor
@Test func theSurfaceEnvironmentBindsTheTabTheRunAndTheSocket() {
    let engine = RecordingEngine()
    let registry = SurfaceRegistry(engine: engine, socketPath: "/tmp/relay-test.sock")
    let tabID = UUID()

    _ = registry.surface(for: tabID, cwd: nil, onTitle: { _ in }, onDirectory: { _ in })

    #expect(engine.lastEnv["RELAY_TAB_ID"] == tabID.uuidString)
    #expect(engine.lastEnv["RELAY_RUN_ID"] == RelayRunID.current)
    // Senza, l'hook ricade sul socket di default: un'istanza di sviluppo manderebbe i suoi eventi
    // al Relay di tutti i giorni.
    #expect(engine.lastEnv["RELAY_SOCKET"] == "/tmp/relay-test.sock")
}

@MainActor
@Test func withoutASocketPathTheHookFallsBackToTheDefault() {
    let engine = RecordingEngine()
    let registry = SurfaceRegistry(engine: engine)

    _ = registry.surface(for: UUID(), cwd: nil, onTitle: { _ in }, onDirectory: { _ in })

    #expect(engine.lastEnv["RELAY_SOCKET"] == nil)
}

@MainActor
private final class RecordingEngine: TerminalEngine {
    var lastEnv: [String: String] = [:]

    func makeSurface(
        cwd _: String?,
        shell _: String?,
        env: [String: String]
    ) -> TerminalSurfaceHandle {
        lastEnv = env
        return RecordingSurface()
    }
}

@MainActor
private final class RecordingSurface: TerminalSurfaceHandle {
    let id = UUID()
    let view = NSView()
    var onTitleChanged: ((String) -> Void)?
    var onDirectoryChanged: ((String) -> Void)?
    private(set) var wasTornDown = false

    func start() {}
    func teardown() {
        wasTornDown = true
    }

    func apply(theme _: RelayTheme) {}
    func foregroundProcessName() -> String? {
        nil
    }

    func foregroundCommandLine() -> [String]? {
        nil
    }

    func currentDirectory() -> String? {
        nil
    }

    func hasRunningChildren() -> Bool {
        false
    }

    func sendText(_: String) {}
    func clear() {}
    func search(
        _: String,
        options _: TerminalSearchOptions,
        forward _: Bool
    ) -> (current: Int, total: Int) {
        (0, 0)
    }

    func endSearch() {}
}
