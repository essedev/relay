import AppKit

/// Composition root. Se questo file cresce oltre il wiring, manca un modulo.
@main
struct Relay {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        app.setActivationPolicy(.regular)
        app.run()
    }
}
