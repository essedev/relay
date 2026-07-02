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

    /// Legge `snapshot()` dentro il tracking: dipende solo dai campi salvati (nome, cwd, pin,
    /// ordine, selezione, tab), non dallo stato agente, quindi gli eventi degli hook non scatenano
    /// scritture. Si ri-arma a ogni cambio.
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
        do {
            try layoutStore.save(store.snapshot())
        } catch {
            log.error("layout save failed: \(error)")
        }
    }
}
