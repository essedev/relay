import Foundation
import WorkspaceModel

/// Wiring della nomina automatica dei workspace, estratto dal corpo di `AppController` per tenerlo
/// sul solo bootstrap (come `AppControllerUpdate`/`Settings`). Il `NamingController` osserva
/// l'eleggibilità e chiama la rete; qui lo si costruisce, si aggancia alle surface (argv in
/// foreground) e si espongono le azioni di configurazione e "Regenerate name".
extension AppController {
    /// Costruisce e avvia il controller (il chiamante lo salta in demo mode). Inerte senza API key
    /// (il controller osserva l'eleggibilità e non fa partire nessun timer). Legge dallo split
    /// l'argv in foreground (segnale "comando in corso") e la cwd viva (segnale "directory": la
    /// shell reale via `CurrentDirectory.resolve`, non l'OSC 7 che zsh in Relay non emette).
    func setupWorkspaceNaming() {
        let controller = NamingController(
            store: store,
            settings: settings,
            credentials: namingCredentials,
            foregroundCommandLine: { [weak self] tabID in
                self?.splitVC?.foregroundCommandLine(for: tabID) ?? nil
            },
            currentDirectory: { [weak self] tabID in
                self?.splitVC?.currentDirectory(for: tabID) ?? nil
            }
        )
        controller.start()
        namingController = controller
    }

    /// Ri-valuta la nomina automatica dopo un cambio di configurazione dalle impostazioni (toggle o
    /// API key salvata): la presenza della chiave non è osservabile, va notificata a mano.
    func reconfigureWorkspaceNaming() {
        namingController?.reconfigure()
    }

    /// "Regenerate name" dal menu contestuale del workspace: lo rende di nuovo eleggibile.
    func regenerateWorkspaceName(_ id: UUID) {
        namingController?.regenerate(id)
    }
}
