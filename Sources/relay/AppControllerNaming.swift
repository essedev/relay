import AppKit
import Foundation
import WorkspaceModel

/// Wiring della nomina automatica dei workspace, estratto dal corpo di `AppController` per tenerlo
/// sul solo bootstrap (come `AppControllerUpdate`/`Settings`). Il `NamingController` osserva
/// l'eleggibilità e chiama la rete; qui lo si costruisce, si aggancia alle surface (argv in
/// foreground, cwd viva) e si presenta l'esito negativo dell'azione manuale.
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
            },
            onFailure: { [weak self] workspaceID, failure in
                self?.presentNamingFailure(failure, for: workspaceID)
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

    /// "Regenerate name" dal menu contestuale della sidebar e dal menu Workspace: nomina subito col
    /// contesto corrente, chiedendo un nome diverso da quello attuale. Passa dal controller, non
    /// dallo store: `markNameRegenerable` da solo rimette il workspace in coda al poll passivo, che
    /// su un workspace fermo resta muto (era il "Regenerate name" che non faceva niente).
    func regenerateWorkspaceName(_ id: UUID) {
        namingController?.regenerate(id)
    }

    /// L'azione manuale non ha prodotto un nome: dillo, con la via d'uscita. Sheet sulla finestra
    /// del workspace bersaglio (come le conferme di chiusura): il menu contestuale della sidebar si
    /// apre anche su una finestra di sfondo senza attivarla.
    private func presentNamingFailure(_ failure: NamingFailure, for workspaceID: UUID) {
        guard let workspace = store.workspaces.first(where: { $0.id == workspaceID })
        else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = namingFailureTitle(failure, workspaceName: workspace.name)
        alert.informativeText = namingFailureInfo(failure)
        alert.addButton(withTitle: "OK")
        // La configurazione è l'unico esito con un rimedio a un click: le altre due sono cose da
        // fare nel terminale, non in un pannello.
        if failure == .notConfigured { alert.addButton(withTitle: "Open Settings…") }
        let target = windowControllers[workspace.windowID]?.window ?? window
        guard let target else { return }
        alert.beginSheetModal(for: target) { [weak self] response in
            guard failure == .notConfigured, response == .alertSecondButtonReturn else { return }
            self?.openSettings(nil)
        }
    }

    private func namingFailureTitle(_ failure: NamingFailure, workspaceName: String) -> String {
        switch failure {
        case .notConfigured:
            "Workspace naming isn\u{2019}t set up"
        case .noContext:
            "Not enough context to name \u{201C}\(workspaceName)\u{201D}"
        case .requestFailed:
            "Couldn\u{2019}t generate a name for \u{201C}\(workspaceName)\u{201D}"
        }
    }

    private func namingFailureInfo(_ failure: NamingFailure) -> String {
        switch failure {
        case .notConfigured:
            """
            Relay names workspaces with a model you configure. Add an API key in \
            Settings > Agents to turn it on.
            """
        case .noContext:
            """
            A name comes from the workspace folder, a command running in one of its tabs, \
            or an active agent session. Open a project folder or start something, then try again.
            """
        case .requestFailed:
            """
            The naming request didn\u{2019}t come back with a usable name. Check the base URL, \
            model and API key in Settings > Agents.
            """
        }
    }
}
