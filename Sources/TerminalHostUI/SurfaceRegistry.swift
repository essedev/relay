import Core
import Foundation
import TerminalEngine

/// Mappa `Tab.id` -> surface viva. Le surface nascono lazy (alla prima visita della tab) e
/// vengono distrutte quando la tab non esiste più (reconcile via `retain`). Il PTY di una tab non
/// visibile resta vivo: l'agente in background continua a lavorare.
///
/// Tiene anche il tema corrente: lo applica alle nuove surface e lo propaga a tutte quelle vive
/// quando cambia (`applyTheme`).
@MainActor
public final class SurfaceRegistry {
    private let engine: TerminalEngine
    private var surfaces: [UUID: TerminalSurfaceHandle] = [:]
    private var theme: RelayTheme = .relayDark

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
        surface.apply(theme: theme)
        surfaces[tabID] = surface
        return surface
    }

    /// Aggiorna il tema e lo propaga a tutte le surface vive. No-op se invariato.
    public func applyTheme(_ newTheme: RelayTheme) {
        guard newTheme != theme else { return }
        theme = newTheme
        for surface in surfaces.values {
            surface.apply(theme: newTheme)
        }
    }

    /// Tiene vive solo le surface delle tab ancora esistenti; fa teardown delle altre.
    public func retain(_ aliveTabIDs: Set<UUID>) {
        for (id, surface) in surfaces where !aliveTabIDs.contains(id) {
            surface.teardown()
            surfaces.removeValue(forKey: id)
        }
    }
}
