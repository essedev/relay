import AgentRuntime
import AppKit
import Core

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
        // (`swift run`, id assente) non si applica: lo copre il guard sul path qui sotto.
        if activateRunningInstanceIfPresent() { return }

        // Guard basato sul path: il guard bundle non copre un lancio senza bundle id (`swift run`)
        // sullo stesso `~/.relay`, che unlinkerebbe il socket dell'istanza viva orfanandone il
        // receiver (badge congelati). Se un receiver vivo possiede già il nostro socket, un'altra
        // istanza sta usando questa runtime dir: esco. Le istanze dev legittime usano
        // `RELAY_SOCKET`/`RELAY_LAYOUT` diversi (path diverso -> nessun match, partono normali).
        if AgentEventClient.isReceiverReachable() {
            RelayLog.logger("app").notice(
                "another Relay instance owns the runtime socket; exiting"
            )
            return
        }

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
