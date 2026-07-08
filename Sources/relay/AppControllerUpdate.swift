import AppKit
import WorkspaceModel

/// Play della pill di aggiornamento: esegue il comando brew dentro l'app, in una tab dedicata,
/// invece di lasciarlo copiare a mano. Extension per tenere il corpo di `AppController` sul solo
/// bootstrap. La pill resta comunque solo un facilitatore: brew resta l'updater (vedi la gotcha
/// "Check aggiornamenti" in CLAUDE.md), qui apriamo solo il terminale giusto e digitiamo il
/// comando.
extension AppController {
    /// Riusa (o crea) un workspace "Relay Update" e ci apre sempre una **tab fresca**, così una
    /// shell già a metà di un upgrade precedente non viene disturbata. `brew` sostituisce il bundle
    /// mentre l'app gira: safe su APFS (il processo vivo tiene l'inode vecchio), la nuova versione
    /// parte alla riapertura. Inietta col solito ritardo del resume, per dare tempo alla surface di
    /// realizzarsi e alla shell di arrivare al prompt.
    func runUpdateInTab() {
        let name = "Relay Update"
        let tab: WorkspaceModel.Tab
        if let existing = store.workspaces.first(where: { $0.name == name && !$0.archived }) {
            store.selectWorkspace(existing.id)
            tab = store.addTab(to: existing)
        } else {
            // `.user`: "Relay Update" è un nome intenzionale, la nomina automatica non lo rigenera.
            let workspace = store.createWorkspace(
                name: name, nameOrigin: .user, rootPath: NSHomeDirectory()
            )
            guard let created = workspace.selectedTab else { return }
            tab = created
        }
        let tabID = tab.id
        let command = UpdateController.upgradeCommand
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.splitVC.sendText(to: tabID, command + "\n")
        }
    }
}
