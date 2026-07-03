import AppKit
import Core
import Darwin
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

    private let terminal: RelayTerminalView
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
        terminal = RelayTerminalView(frame: .zero)
        super.init()
        terminal.processDelegate = self
        // Drop di file: inserisce i path (escaped) nell'input, come Terminal.app.
        terminal.onFilesDropped = { [weak self] urls in
            self?.sendText(ShellEscape.joined(urls.map(\.path)))
        }
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

    /// Scrive testo nello stdin del processo (resume dell'agente). `process.send` va al PTY, come
    /// digitare. No-op se non avviata.
    func sendText(_ text: String) {
        guard started, terminal.process.running else { return }
        terminal.process.send(data: ArraySlice(Array(text.utf8)))
    }

    /// Nome del comando in foreground del pty, `nil` se la shell è al prompt (safe da chiudere).
    /// Meccanica standard dei terminali: `tcgetpgrp` dà il foreground process group del pty; se
    /// coincide con il pid della shell la shell è al prompt, altrimenti gira un comando di cui
    /// risolviamo il nome (`proc_name`). Le shell interattive annidate (safe-list) contano come
    /// "al prompt": chiuderle non perde lavoro. Solo foreground: i job in background non contano.
    func foregroundProcessName() -> String? {
        guard started, terminal.process.running else { return nil }
        let fd = terminal.process.childfd
        guard fd >= 0 else { return nil }
        let foreground = tcgetpgrp(fd)
        guard foreground > 0, foreground != terminal.process.shellPid else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard proc_name(foreground, &buffer, UInt32(buffer.count)) > 0 else { return "process" }
        let name = buffer.withUnsafeBufferPointer { pointer -> String in
            guard let base = pointer.baseAddress else { return "" }
            return String(cString: base)
        }
        return name.isEmpty ? "process" : (Self.safeForegroundNames.contains(name) ? nil : name)
    }

    /// Shell che, se in foreground, non fanno scattare la conferma di chiusura (sono "al prompt").
    private static let safeForegroundNames: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "login",
    ]

    /// `true` se la shell ha almeno un processo figlio (comando foreground/background o agente).
    /// `proc_listchildpids` copre tutti i casi: una shell al prompt pulito non ha figli. Guida la
    /// LRU: mai sfrattare una surface con lavoro vivo.
    func hasRunningChildren() -> Bool {
        guard started, terminal.process.running else { return false }
        let pid = terminal.process.shellPid
        guard pid > 0 else { return false }
        let capacity = 64
        var buffer = [pid_t](repeating: 0, count: capacity)
        let bytes = proc_listchildpids(pid, &buffer, Int32(capacity * MemoryLayout<pid_t>.size))
        return bytes > 0
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
