import Foundation
import TerminalEngine

/// Mappa `Tab.id` -> surface viva. Le surface nascono lazy (alla prima visita della tab) e
/// vengono distrutte quando la tab non esiste più (reconcile via `retain`). Il PTY di una tab non
/// visibile resta vivo: l'agente in background continua a lavorare.
@MainActor
public final class SurfaceRegistry {
    private let engine: TerminalEngine
    private var surfaces: [UUID: TerminalSurfaceHandle] = [:]

    public init(engine: TerminalEngine) {
        self.engine = engine
    }

    /// Ritorna la surface della tab, creandola alla prima chiamata.
    public func surface(
        for tabID: UUID,
        cwd: String?,
        onTitle: @escaping (String) -> Void
    ) -> TerminalSurfaceHandle {
        if let existing = surfaces[tabID] { return existing }
        // RELAY_TAB_ID lega la sessione al pane: lo ereditano shell -> agent -> hook, che lo
        // rimanda nell'evento, così il coordinatore sa quale tab aggiornare (nessun parsing
        // output).
        let surface = engine.makeSurface(
            cwd: cwd,
            shell: nil,
            env: ["RELAY_TAB_ID": tabID.uuidString]
        )
        surface.onTitleChanged = onTitle
        surfaces[tabID] = surface
        return surface
    }

    /// Tiene vive solo le surface delle tab ancora esistenti; fa teardown delle altre.
    public func retain(_ aliveTabIDs: Set<UUID>) {
        for (id, surface) in surfaces where !aliveTabIDs.contains(id) {
            surface.teardown()
            surfaces.removeValue(forKey: id)
        }
    }
}
