import AppKit
import Core
import TerminalEngine
import TerminalHostUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let log = RelayLog.logger("app")
    private let engine: TerminalEngine = SwiftTermEngine()
    private var window: NSWindow!
    private var host: TerminalHostView?

    func applicationDidFinishLaunching(_: Notification) {
        log.info("relay launched")

        let frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Relay"

        let surface = engine.makeSurface(cwd: nil, shell: nil)
        let host = TerminalHostView(surface: surface)
        window.contentView = host
        self.host = host

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        host.start()
        window.makeFirstResponder(host.focusView)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
