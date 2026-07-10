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
    /// Ordine di accesso per la LRU: primo = più recente. Aggiornato a ogni `surface(for:)`.
    private var recency: [UUID] = []
    private var lastTouchedAt: [UUID: Date] = [:]
    private var theme: RelayTheme = .relayDark
    private static let recentUseGraceInterval: TimeInterval = 30 * 60

    public init(engine: TerminalEngine) {
        self.engine = engine
    }

    /// Numero di surface attualmente vive (PTY + emulatore in memoria). Guida le misure di memoria
    /// (M3) e la taratura del cap LRU.
    public var liveSurfaceCount: Int {
        surfaces.count
    }

    /// Ritorna la surface della tab, creandola alla prima chiamata. Ogni chiamata segna la tab come
    /// la più recente (per la LRU).
    public func surface(
        for tabID: UUID,
        cwd: String?,
        onTitle: @escaping (String) -> Void,
        onDirectory: @escaping (String) -> Void
    ) -> TerminalSurfaceHandle {
        touch(tabID)
        if let existing = surfaces[tabID] { return existing }
        // RELAY_TAB_ID lega la sessione al pane: lo ereditano shell -> agent -> hook, che lo
        // rimanda nell'evento, così il coordinatore sa quale tab aggiornare (nessun parsing
        // output). RELAY_RUN_ID lega la sessione a *questa* run dell'app: lo store scarta gli
        // eventi di run diverse (sessioni orfane sopravvissute a un riavvio).
        let surface = engine.makeSurface(
            cwd: cwd,
            shell: nil,
            env: [
                "RELAY_TAB_ID": tabID.uuidString,
                "RELAY_RUN_ID": RelayRunID.current,
            ]
        )
        surface.onTitleChanged = onTitle
        surface.onDirectoryChanged = onDirectory
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

    /// Nome del comando in foreground nella surface della tab, o `nil` se la shell è al prompt o
    /// la tab non è ancora stata realizzata (nessuna surface -> nessun processo). Guida la
    /// conferma di chiusura.
    public func foregroundProcess(for tabID: UUID) -> String? {
        surfaces[tabID]?.foregroundProcessName()
    }

    /// Argv del comando in foreground nella surface della tab, o `nil` (prompt / tab non
    /// realizzata). Guida la nomina automatica del workspace (poll di "cosa stai facendo").
    public func foregroundCommandLine(for tabID: UUID) -> [String]? {
        surfaces[tabID]?.foregroundCommandLine()
    }

    /// Working directory della shell nella surface della tab, o `nil` se la tab non è realizzata.
    /// Usata come fallback all'OSC 7 quando si crea una nuova tab.
    public func currentDirectory(for tabID: UUID) -> String? {
        surfaces[tabID]?.currentDirectory()
    }

    /// Scrive testo nello stdin della surface della tab (resume dell'agente). No-op se la tab non è
    /// realizzata.
    public func sendText(to tabID: UUID, _ text: String) {
        surfaces[tabID]?.sendText(text)
    }

    /// Pulisce il terminale della tab (Cmd+K). No-op se la tab non è realizzata.
    public func clear(_ tabID: UUID) {
        surfaces[tabID]?.clear()
    }

    /// Cerca nel buffer della tab e ritorna posizione/totale per il contatore. `(0, 0)` se la tab
    /// non è realizzata.
    public func search(_ tabID: UUID, term: String, forward: Bool) -> (current: Int, total: Int) {
        surfaces[tabID]?.search(term, forward: forward) ?? (0, 0)
    }

    /// Termina la ricerca nella tab (pulisce selezione e stato). No-op se non realizzata.
    public func endSearch(_ tabID: UUID) {
        surfaces[tabID]?.endSearch()
    }

    /// Tiene vive solo le surface delle tab ancora esistenti; fa teardown delle altre.
    public func retain(_ aliveTabIDs: Set<UUID>) {
        for (id, surface) in surfaces where !aliveTabIDs.contains(id) {
            evict(id, surface)
        }
    }

    /// Applies the LRU soft cap. Idle surfaces can be evicted only when they are outside the
    /// protected set and outside the recent-use grace window. If every candidate is still useful,
    /// the registry temporarily stays above the cap.
    public func enforceLRU(
        cap: Int,
        keep: UUID?,
        protectedTabIDs: Set<UUID> = [],
        now: Date = Date()
    ) {
        guard cap > 0, surfaces.count > cap else { return }
        let toEvict = SurfaceEvictionPolicy.evictions(
            recency: recency,
            keep: keep,
            cap: cap,
            isProtected: { protectedTabIDs.contains($0) || self.wasUsedRecently($0, now: now) },
            isEvictable: { self.surfaces[$0]?.hasRunningChildren() == false }
        )
        for id in toEvict {
            guard let surface = surfaces[id] else { continue }
            evict(id, surface)
        }
    }

    /// Marks the tab as most recent in the LRU order.
    private func touch(_ tabID: UUID, now: Date = Date()) {
        recency.removeAll { $0 == tabID }
        recency.insert(tabID, at: 0)
        lastTouchedAt[tabID] = now
    }

    private func wasUsedRecently(_ tabID: UUID, now: Date) -> Bool {
        guard let lastTouched = lastTouchedAt[tabID] else { return false }
        return now.timeIntervalSince(lastTouched) < Self.recentUseGraceInterval
    }

    /// Tears down a surface and removes all eviction metadata for it.
    private func evict(_ tabID: UUID, _ surface: TerminalSurfaceHandle) {
        surface.teardown()
        surfaces.removeValue(forKey: tabID)
        recency.removeAll { $0 == tabID }
        lastTouchedAt.removeValue(forKey: tabID)
    }
}
