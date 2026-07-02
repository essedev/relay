import AppKit
import Foundation
import SwiftTerm

/// Backend v1 basato su SwiftTerm. Tenuto dietro `TerminalEngine` così l'app non dipende da
/// SwiftTerm: nessun tipo SwiftTerm esce da questo modulo.
@MainActor
public final class SwiftTermEngine: TerminalEngine {
    public init() {}

    public func makeSurface(
        cwd: String?,
        shell: String?,
        env: [String: String]
    ) -> TerminalSurfaceHandle {
        SwiftTermSurface(cwd: cwd, shell: shell, env: env)
    }
}

@MainActor
final class SwiftTermSurface: NSObject, TerminalSurfaceHandle, LocalProcessTerminalViewDelegate {
    let id = UUID()
    var onTitleChanged: ((String) -> Void)?

    private let terminal: LocalProcessTerminalView
    private let cwd: String?
    private let shell: String
    private let extraEnv: [String: String]
    private var started = false

    var view: NSView {
        terminal
    }

    init(cwd: String?, shell: String?, env: [String: String]) {
        self.cwd = cwd
        self.shell = shell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        extraEnv = env
        terminal = LocalProcessTerminalView(frame: .zero)
        super.init()
        terminal.processDelegate = self
    }

    func start() {
        guard !started else { return }
        started = true
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        for (key, value) in extraEnv {
            env.append("\(key)=\(value)")
        }
        terminal.startProcess(executable: shell, environment: env, currentDirectory: cwd)
    }

    func teardown() {
        guard started else { return }
        terminal.terminate()
    }

    // MARK: - LocalProcessTerminalViewDelegate (requisiti nonisolated del protocollo SwiftTerm)

    nonisolated func sizeChanged(
        source _: LocalProcessTerminalView,
        newCols _: Int,
        newRows _: Int
    ) {}

    nonisolated func setTerminalTitle(source _: LocalProcessTerminalView, title: String) {
        Task { @MainActor in self.onTitleChanged?(title) }
    }

    nonisolated func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {}
    nonisolated func processTerminated(source _: TerminalView, exitCode _: Int32?) {}
}
