import AppKit

/// Composition root. Se questo file cresce oltre il wiring, manca un modulo.
@main
struct Relay {
    @MainActor
    static func main() {
        // Single-instance: due Relay condividono `~/.relay` (layout + socket) e i loro autosave si
        // pesterebbero, corrompendo il layout. `LSMultipleInstancesProhibited` lo previene lato
        // LaunchServices; questo guard copre l'avvio diretto e la finestra di un upgrade (vecchio
        // processo ancora vivo mentre parte il nuovo): se un'altra istanza gira, la portiamo in
        // primo piano ed esco senza toccare nulla. Solo dal bundle (con bundle id); in dev
        // (`swift run`, id assente) non si applica.
        if activateRunningInstanceIfPresent() { return }

        let app = NSApplication.shared
        let controller = AppController()
        app.delegate = controller
        app.setActivationPolicy(.regular)
        app.run()
    }

    /// `true` se un'altra istanza dello stesso bundle è già in esecuzione (attivata qui): il
    /// chiamante deve uscire senza avviare l'app.
    @MainActor
    private static func activateRunningInstanceIfPresent() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != .current }
        guard let existing = others.first else { return false }
        existing.activate()
        return true
    }
}
