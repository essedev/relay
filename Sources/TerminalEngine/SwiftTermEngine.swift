import AppKit
import Foundation
import SwiftTerm

/// Backend v1 basato su SwiftTerm. Tenuto dietro `TerminalEngine` così l'app non dipende da
/// SwiftTerm: nessun tipo SwiftTerm esce da questo modulo.
@MainActor
public final class SwiftTermEngine: TerminalEngine {
    public init() {}

    public func makeSurface(cwd: String?, shell: String?) -> TerminalSurfaceHandle {
        SwiftTermSurface(cwd: cwd, shell: shell)
    }
}

@MainActor
final class SwiftTermSurface: NSObject, TerminalSurfaceHandle, LocalProcessTerminalViewDelegate {
    let id = UUID()

    private let terminal: LocalProcessTerminalView
    private let cwd: String?
    private let shell: String
    private var started = false

    var view: NSView {
        terminal
    }

    init(cwd: String?, shell: String?) {
        self.cwd = cwd
        self.shell = shell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminal = LocalProcessTerminalView(frame: .zero)
        super.init()
        terminal.processDelegate = self
    }

    func start() {
        guard !started else { return }
        started = true
        // Nota: cwd per-processo va gestito senza cambiare la cwd globale quando avremo piu'
        // surface (Fase 2, multi-pane). Per ora la surface singola parte dalla cwd di default.
        let env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        terminal.startProcess(executable: shell, environment: env)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    /// Requisiti nonisolated del protocollo SwiftTerm. Stub per ora; quando li implementeremo
    /// (titolo, cwd, stato) faremo l'hop a MainActor con Task { @MainActor in ... }.
    nonisolated func sizeChanged(
        source _: LocalProcessTerminalView,
        newCols _: Int,
        newRows _: Int
    ) {}
    nonisolated func setTerminalTitle(source _: LocalProcessTerminalView, title _: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {}
    nonisolated func processTerminated(source _: TerminalView, exitCode _: Int32?) {}
}
