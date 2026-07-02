import AppKit
import Core
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
    var onDirectoryChanged: ((String) -> Void)?

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
        hideScroller()
        apply(theme: .relayDark) // default; la registry riapplica il tema corrente
    }

    /// SwiftTerm monta un NSScroller sempre visibile sul bordo destro: una track fissa fuori dal
    /// design (lo scroll da trackpad non passa dallo scroller e resta pieno). Non c'è API pubblica
    /// per nasconderlo, quindi lo si spegne come subview; se sparisce da SwiftTerm, questo è no-op.
    private func hideScroller() {
        for case let scroller as NSScroller in terminal.subviews {
            scroller.isHidden = true
        }
    }

    /// Applica il tema al terminale. I tipi SwiftTerm/NSColor restano confinati qui.
    func apply(theme: RelayTheme) {
        terminal.installColors(theme.ansi.map(Self.swiftTermColor))
        terminal.nativeBackgroundColor = Self.nsColor(theme.background)
        terminal.nativeForegroundColor = Self.nsColor(theme.foreground)
        terminal.caretColor = Self.nsColor(theme.cursor)
        terminal.selectedTextBackgroundColor = Self.nsColor(theme.selection)
        // Blink del caret: SwiftTerm parte con `.blinkBlock`. `setCursorStyle` notifica la view e
        // (dis)attiva l'animazione. Un'app interna può comunque richiederlo via DECSCUSR.
        terminal.getTerminal().setCursorStyle(theme.cursorBlink ? .blinkBlock : .steadyBlock)
        if let fontName = theme.fontName, let font = NSFont(name: fontName, size: theme.fontSize) {
            terminal.font = font
        } else {
            terminal.font = NSFont.monospacedSystemFont(ofSize: theme.fontSize, weight: .regular)
        }
    }

    private static func swiftTermColor(_ color: RelayColor) -> SwiftTerm.Color {
        // RelayColor è 8 bit per canale; SwiftTerm.Color è 16 bit (255 -> 65535, fattore 257).
        SwiftTerm.Color(
            red: UInt16(color.red) * 257,
            green: UInt16(color.green) * 257,
            blue: UInt16(color.blue) * 257
        )
    }

    private static func nsColor(_ color: RelayColor) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: 1
        )
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

    nonisolated func hostCurrentDirectoryUpdate(source _: TerminalView, directory: String?) {
        guard let directory, let path = OSC7.path(from: directory) else { return }
        Task { @MainActor in self.onDirectoryChanged?(path) }
    }

    nonisolated func processTerminated(source _: TerminalView, exitCode _: Int32?) {}
}
