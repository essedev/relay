import Core
import Foundation
import LayoutStore
import Observation
import WorkspaceModel

/// Autosave del layout: osserva lo store e salva (debounced) a ogni cambio persistente, con flush
/// sincrono alla chiusura. Estratto da `AppController` perché è una responsabilità a sé (il
/// composition root resta wiring). Istanziato solo in modalità normale: la demo non deve toccare il
/// file reale, quindi non lo crea.
@MainActor
final class LayoutAutosave {
    private let store: WorkspaceStore
    private let layoutStore: LayoutStore
    private let log = RelayLog.logger("layout")
    private var saveTask: Task<Void, Never>?
    /// Ultimo snapshot scritto: salta le scritture no-op (vedi `save`).
    private var lastSaved: LayoutSnapshot?

    init(store: WorkspaceStore, layoutStore: LayoutStore) {
        self.store = store
        self.layoutStore = layoutStore
    }

    /// Avvia l'osservazione. Da chiamare dopo il restore/seed iniziale.
    func start() {
        observe()
    }

    /// Flush sincrono finale: alla chiusura il debounce potrebbe non essere ancora scaduto.
    func flush() {
        saveTask?.cancel()
        save()
    }

    /// Legge `snapshot()` dentro il tracking, così l'osservazione si risveglia quando cambia un
    /// campo salvato. Nota: uno snapshot legge anche `tab.attention`/`attentionSince`, che gli
    /// eventi agente riscrivono (a volte con lo stesso valore): il de-dup in `save` scarta le
    /// scritture no-op che ne derivano. Si ri-arma a ogni cambio.
    private func observe() {
        withObservationTracking {
            _ = store.snapshot()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleSave()
                self?.observe()
            }
        }
    }

    /// Debounce: accorpa raffiche di cambi in un'unica scrittura ~500ms dopo l'ultimo.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        let snapshot = store.snapshot()
        // Scrittura no-op: un evento agente riscrive attention/lastEventAt sulla tab (a volte con
        // lo
        // stesso valore) risvegliando l'osservazione, ma lo snapshot persistito è identico. Salta,
        // così gli eventi degli hook non toccano il disco; i cambi reali (pendingSince, resume,
        // rename, ordine) restano invariati.
        guard snapshot != lastSaved else { return }
        do {
            try layoutStore.save(snapshot)
            lastSaved = snapshot
        } catch {
            log.error("layout save failed: \(error)")
        }
    }
}
