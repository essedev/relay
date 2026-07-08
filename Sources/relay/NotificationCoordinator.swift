import Core
import Foundation
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
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let settings: AppSettings
    private let center = UNUserNotificationCenter.current()
    private let log = RelayLog.logger("notifications")

    /// Chiavi del `userInfo` che legano la notifica alla tab da riportare in vista.
    private enum UserInfoKey {
        static let workspaceID = "relay.workspaceID"
        static let tabID = "relay.tabID"
    }

    /// Click sulla notifica: (workspaceID, tabID) della tab da attivare. Wired dal composition
    /// root.
    var onActivate: ((UUID, UUID) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        center.delegate = self
    }

    /// Presenta il banner anche con Relay in primo piano: notifichiamo solo per tab non "in vista"
    /// (altra tab o app in background), quindi il banner va mostrato comunque. Di default macOS
    /// sopprime le notifiche dell'app frontmost, ecco perché sembravano non arrivare.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)
            -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Click sulla notifica (azione di default): riporta in vista la tab che l'ha generata. Legge
    /// gli id dal `userInfo` e delega al composition root, che seleziona workspace+tab e attiva la
    /// finestra. Senza questo handler il click non faceva nulla (era la causa del "cliccare la
    /// notifica non apre la tab").
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        guard let wsRaw = info[UserInfoKey.workspaceID] as? String,
              let tabRaw = info[UserInfoKey.tabID] as? String,
              let workspaceID = UUID(uuidString: wsRaw),
              let tabID = UUID(uuidString: tabRaw) else { return }
        Task { @MainActor [weak self] in
            self?.onActivate?(workspaceID, tabID)
        }
    }

    /// Chiede l'autorizzazione al boot e logga l'esito + lo stato corrente (diagnostica: una
    /// firma ad-hoc che cambia a ogni reinstall può far decadere il permesso concesso prima).
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in
                if let error {
                    self?.log.error("auth failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    self?.log.notice("auth granted=\(granted, privacy: .public)")
                }
                self?.logStatus()
            }
        }
    }

    /// Logga lo stato di autorizzazione corrente (authorized/denied/notDetermined + alert setting).
    private func logStatus() {
        center.getNotificationSettings { [weak self] current in
            let status = current.authorizationStatus.rawValue
            let alert = current.alertSetting.rawValue
            Task { @MainActor in
                let line = "auth status=\(status) alert=\(alert)"
                self?.log.notice("\(line, privacy: .public)")
            }
        }
    }

    /// Filtra una transizione notificabile per preferenze e contesto, poi la consegna.
    func handle(_ request: AgentNotification) {
        guard settings.notificationsEnabled else { return }
        switch request.kind {
        case .needsInput:
            guard settings.notifyOnNeedsInput else { return }
            // `isVisible` include già "Relay in primo piano": se è vero la stai guardando, è
            // rumore.
            if request.isVisible { return }
        case .completed:
            guard settings.notifyOnCompleted else { return }
        }
        deliver(request)
    }

    private func deliver(_ request: AgentNotification) {
        let content = UNMutableNotificationContent()
        content.title = Self.title(for: request.kind)
        content.body = "\(request.workspaceName) / \(request.tabTitle)"
        content.userInfo = [
            UserInfoKey.workspaceID: request.workspaceID.uuidString,
            UserInfoKey.tabID: request.tabID.uuidString,
        ]
        if settings.notificationSound {
            content.sound = Self.sound(named: settings.notificationSoundName)
        }
        log.notice("deliver: \(content.title, privacy: .public)") // solo il tipo, non il contenuto
        center.add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.log.error("add failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func title(for kind: AgentNotificationKind) -> String {
        switch kind {
        case .needsInput: "Claude needs a reply"
        case .completed: "Claude finished"
        }
    }

    /// "Default" = suono di notifica di sistema; gli altri sono i classici alert in
    /// `/System/Library/Sounds` (`.aiff`), risolti da `UNNotificationSound(named:)`.
    private static func sound(named name: String) -> UNNotificationSound {
        guard name != "Default" else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName("\(name).aiff"))
    }
}
