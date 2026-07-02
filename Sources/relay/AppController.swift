import AppKit
import Core

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let log = RelayLog.logger("app")
    private var window: NSWindow!

    func applicationDidFinishLaunching(_: Notification) {
        log.info("relay skeleton launched")

        let frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Relay"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
