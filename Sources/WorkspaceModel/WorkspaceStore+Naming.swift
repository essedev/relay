import Foundation

// Nomina dei workspace: applicazione di un nome generato dalla nomina automatica e reset
// dell'eleggibilità ("Regenerate name"). Estratto da `WorkspaceStore` per tenere il file principale
// entro il budget di dimensione (vedi CONVENTIONS). Agisce sui `Workspace` osservabili dello store;
// la policy dei trigger e la rete vivono nel composition root (`NamingController`).

public extension WorkspaceStore {
    /// Applica un nome prodotto dalla nomina automatica, marcando l'origine `.generated`. Guardia:
    /// agisce **solo** se il workspace esiste ancora ed è ancora `.default` (il chiamante è
    /// asincrono - la risposta di rete arriva dopo, e nel frattempo l'utente può aver rinominato a
    /// mano o il workspace essere sparito). Ritorna `true` se ha applicato il nome. Non tocca
    /// ordine
    /// né attenzione: nominare non è un'attività da segnalare.
    @discardableResult
    func applyGeneratedName(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let workspace = workspaces.first(where: { $0.id == id }),
              workspace.nameOrigin == .default else { return false }
        workspace.name = trimmed
        workspace.nameOrigin = .generated
        return true
    }

    /// Riporta un workspace a `.default` per farlo rinominare di nuovo (azione "Regenerate name"):
    /// lo rende eleggibile alla nomina automatica al prossimo segnale. No-op se non esiste. Non
    /// cambia il nome corrente finché la generazione non produce il nuovo.
    func markNameRegenerable(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        workspace.nameOrigin = .default
    }
}
