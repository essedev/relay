import AppKit
import SwiftTerm

// Minimal AppKit host for a SwiftTerm LocalProcessTerminalView.
// Goal of the spike: prove SwiftTerm builds and runs a live local shell with the
// standard Swift toolchain (no zig, no third-party prebuilt binaries).

final class AppDelegate: NSObject, NSApplicationDelegate, LocalProcessTerminalViewDelegate {
    private var window: NSWindow!
    private var terminal: LocalProcessTerminalView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SwiftTerm Spike"

        terminal = LocalProcessTerminalView(frame: window.contentView!.bounds)
        terminal.autoresizingMask = [.width, .height]
        terminal.processDelegate = self
        window.contentView!.addSubview(terminal)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        terminal.startProcess(executable: shell, environment: env)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(terminal)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        window.title = title.isEmpty ? "SwiftTerm Spike" : title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
