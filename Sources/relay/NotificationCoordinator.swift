import AppKit
import Core
import UserNotifications
import WorkspaceModel

/// Notifiche macOS per gli eventi agente (needs_input / completato). Vive nel composition root:
/// unico punto che tocca `UNUserNotificationCenter`. Riceve richieste pure dallo store
/// (`onNotifiableTransition`), applica le preferenze utente e la soppressione runtime, poi
/// consegna.
///
/// Richiede un bundle id (Milestone 4): da bare executable `UNUserNotificationCenter.current()` non
/// esiste. Il chiamante lo istanzia solo quando l'app gira dal bundle.
@MainActor
final class NotificationCoordinator {
    private let settings: AppSettings
    private let center = UNUserNotificationCenter.current()
    private let log = RelayLog.logger("notifications")

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Chiede l'autorizzazione al boot. Se negata, `center.add` viene ignorato in silenzio.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                let message = error.localizedDescription
                self?.log.error("notification auth failed: \(message, privacy: .public)")
            }
        }
    }

    /// Filtra una transizione notificabile per preferenze e contesto, poi la consegna.
    func handle(_ request: AgentNotification) {
        guard settings.notificationsEnabled else { return }
        switch request.kind {
        case .needsInput:
            guard settings.notifyOnNeedsInput else { return }
            // Se la stai già guardando (tab in vista e Relay in primo piano) la notifica è rumore.
            if request.isVisible, NSApp.isActive { return }
        case .completed:
            guard settings.notifyOnCompleted else { return }
        }
        deliver(request)
    }

    private func deliver(_ request: AgentNotification) {
        let content = UNMutableNotificationContent()
        content.title = Self.title(for: request.kind)
        content.body = "\(request.workspaceName) / \(request.tabTitle)"
        if settings.notificationSound {
            content.sound = Self.sound(named: settings.notificationSoundName)
        }
        center.add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }

    private static func title(for kind: AgentNotificationKind) -> String {
        switch kind {
        case .needsInput: "Claude aspetta una risposta"
        case .completed: "Claude ha finito"
        }
    }

    /// "Default" = suono di notifica di sistema; gli altri sono i classici alert in
    /// `/System/Library/Sounds` (`.aiff`), risolti da `UNNotificationSound(named:)`.
    private static func sound(named name: String) -> UNNotificationSound {
        guard name != "Default" else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName("\(name).aiff"))
    }
}
