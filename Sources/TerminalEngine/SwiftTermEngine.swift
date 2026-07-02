import AppKit
import Core
import Foundation
import SwiftTerm

/// Backend v1 basato su SwiftTerm. Tenuto dietro `TerminalEngine` così l'app non dipende da
/// SwiftTerm: nessun tipo SwiftTerm esce da questo modulo.
@MainActor
public final class SwiftTermEngine: TerminalEngine {
    private let theme: RelayTheme

    public init(theme: RelayTheme = .relayDark) {
        self.theme = theme
    }

    public func makeSurface(
        cwd: String?,
        shell: String?,
        env: [String: String]
    ) -> TerminalSurfaceHandle {
        SwiftTermSurface(cwd: cwd, shell: shell, env: env, theme: theme)
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

    init(cwd: String?, shell: String?, env: [String: String], theme: RelayTheme) {
        self.cwd = cwd
        self.shell = shell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        extraEnv = env
        terminal = LocalProcessTerminalView(frame: .zero)
        super.init()
        terminal.processDelegate = self
        apply(theme)
    }

    /// Applica il tema al terminale. I tipi SwiftTerm/NSColor restano confinati qui.
    private func apply(_ theme: RelayTheme) {
        terminal.installColors(theme.ansi.map(Self.swiftTermColor))
        terminal.nativeBackgroundColor = Self.nsColor(theme.background)
        terminal.nativeForegroundColor = Self.nsColor(theme.foreground)
        terminal.caretColor = Self.nsColor(theme.cursor)
        terminal.selectedTextBackgroundColor = Self.nsColor(theme.selection)
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

    nonisolated func hostCurrentDirectoryUpdate(source _: TerminalView, directory _: String?) {}
    nonisolated func processTerminated(source _: TerminalView, exitCode _: Int32?) {}
}
