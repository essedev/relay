import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// L'ultimo filtro prima del banner macOS. Viveva nel composition root, che non ha un test target:
// preferenze, soppressione della tab in vista e titolo per agente non erano coperti da niente.

private let allOn = NotificationPolicy.Preferences(
    enabled: true,
    onNeedsInput: true,
    onCompleted: true,
    onError: true
)

private func request(
    _ kind: AgentNotificationKind,
    agent: String = "claude",
    isVisible: Bool = false
) -> AgentNotification {
    AgentNotification(
        kind: kind,
        agent: agent,
        tabID: UUID(),
        workspaceID: UUID(),
        tabTitle: "tab",
        workspaceName: "ws",
        isVisible: isVisible
    )
}

@Test func deliversTheThreeKindsWhenEverythingIsOn() {
    #expect(NotificationPolicy.shouldDeliver(request(.needsInput), given: allOn))
    #expect(NotificationPolicy.shouldDeliver(request(.completed), given: allOn))
    #expect(NotificationPolicy.shouldDeliver(request(.error), given: allOn))
}

/// L'interruttore generale spegne tutto, a prescindere dai toggle per tipo.
@Test func theGlobalToggleWins() {
    let off = NotificationPolicy.Preferences(
        enabled: false,
        onNeedsInput: true,
        onCompleted: true,
        onError: true
    )
    #expect(!NotificationPolicy.shouldDeliver(request(.needsInput), given: off))
    #expect(!NotificationPolicy.shouldDeliver(request(.completed), given: off))
    #expect(!NotificationPolicy.shouldDeliver(request(.error), given: off))
}

/// Ogni toggle per tipo spegne **solo** il suo.
@Test func eachKindHasItsOwnToggle() {
    let noErrors = NotificationPolicy.Preferences(
        enabled: true,
        onNeedsInput: true,
        onCompleted: true,
        onError: false
    )
    #expect(!NotificationPolicy.shouldDeliver(request(.error), given: noErrors))
    #expect(NotificationPolicy.shouldDeliver(request(.needsInput), given: noErrors))

    let noCompleted = NotificationPolicy.Preferences(
        enabled: true,
        onNeedsInput: true,
        onCompleted: false,
        onError: true
    )
    #expect(!NotificationPolicy.shouldDeliver(request(.completed), given: noCompleted))
    #expect(NotificationPolicy.shouldDeliver(request(.error), given: noCompleted))
}

/// `isVisible` include già "Relay in primo piano": se la stai guardando, needs_input ed errore li
/// leggi nel terminale prima che suoni qualcosa. Il completamento non arriva nemmeno qui con
/// `isVisible` vero (il reducer non lo emette), ma la regola resta la stessa per tutti e tre.
@Test func nothingIsDeliveredForATabYouAreLookingAt() {
    #expect(!NotificationPolicy.shouldDeliver(request(.needsInput, isVisible: true), given: allOn))
    #expect(!NotificationPolicy.shouldDeliver(request(.error, isVisible: true), given: allOn))
    #expect(!NotificationPolicy.shouldDeliver(request(.completed, isVisible: true), given: allOn))
}

@Test func theTitleNamesTheAgent() {
    #expect(NotificationPolicy.title(for: .needsInput, agent: "claude") == "Claude needs a reply")
    #expect(NotificationPolicy.title(for: .completed, agent: "Codex") == "Codex finished")
    #expect(NotificationPolicy.title(for: .error, agent: "codex") == "Codex stopped on an error")
    // Hook che non manda l'agente: meglio un generico che una riga monca.
    #expect(NotificationPolicy.title(for: .completed, agent: "") == "Agent finished")
    // Agente sconosciuto: si usa il suo nome così com'è.
    #expect(NotificationPolicy.title(for: .completed, agent: "aider") == "aider finished")
}

/// I toggle veri di `AppSettings` arrivano alla policy: se questa mappatura si rompe, i toggle in
/// Settings non hanno più effetto e nessun altro test se ne accorge.
@MainActor @Test func settingsMapOntoThePolicyPreferences() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        #expect(settings.notificationPreferences == allOn) // default: tutto acceso

        settings.setNotifyOnCompleted(false)
        settings.setNotificationsEnabled(false)
        #expect(settings.notificationPreferences == NotificationPolicy.Preferences(
            enabled: false,
            onNeedsInput: true,
            onCompleted: false,
            onError: true
        ))
    }
}
