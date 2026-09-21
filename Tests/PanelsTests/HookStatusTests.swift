@testable import Panels
import Testing

// Il blocco Settings > Agents diceva solo "Installed / Not installed". Su un drift (hook nostri
// ma incompleti) "non installato" è falso e manda a cercare nel posto sbagliato: gli hook ci sono
// e funzionano, ne manca qualcuno. Per Codex questo è l'unico posto dove il drift si vede, perché
// i suoi hook non vengono riparati da soli.

@Test func theDriftLabelNamesTheMissingEvents() {
    #expect(HookStatus.installed.label == "Installed")
    #expect(HookStatus.absent.label == "Not installed")
    #expect(HookStatus.outOfDate(missing: ["StopFailure"]).label
        == "Out of date: missing StopFailure")
    #expect(HookStatus.outOfDate(missing: ["PermissionRequest", "StopFailure"]).label
        == "Out of date: missing PermissionRequest, StopFailure")
}

/// Su un drift il bottone aggiorna: il setup è idempotente e rimette solo ciò che manca.
@Test func theActionFitsTheState() {
    #expect(HookStatus.installed.actionLabel == "Uninstall")
    #expect(HookStatus.absent.actionLabel == "Install")
    #expect(HookStatus.outOfDate(missing: ["StopFailure"]).actionLabel == "Update")
}
