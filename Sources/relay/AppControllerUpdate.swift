import AppKit
import WorkspaceModel

/// Il riavvio che chiude l'aggiornamento lanciato dalla pill. Sta qui e non in `UpdateController`
/// perché deve sapere quali sessioni muoiono: riavviare un terminale ferma ogni processo nelle
/// shell, e un dev server non riparte da solo (una sessione agente sì, dalla barra di resume).
extension AppController {
    /// Chiede conferma se qualche progetto aperto ha un comando in foreground, poi riavvia.
    func requestRestartForUpdate() {
        let busy = store.workspaces
            .filter { !$0.closed }
            .flatMap(\.tabs)
            .filter { registry.foregroundProcess(for: $0.id) != nil }
        guard !busy.isEmpty else {
            relaunch()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restart Relay to finish updating?"
        alert.informativeText = (busy.count == 1
            ? "1 tab has a running process that will be stopped."
            : "\(busy.count) tabs have running processes that will be stopped.")
            + " Agent sessions can be resumed after the restart."
        let restart = alert.addButton(withTitle: "Restart")
        let cancel = alert.addButton(withTitle: "Cancel")
        restart.keyEquivalent = "" // Invio non deve fermare i processi per errore
        cancel.keyEquivalent = "\r"
        let onResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .alertFirstButtonReturn { self?.relaunch() }
        }
        if let target = window {
            alert.beginSheetModal(for: target, completionHandler: onResponse)
        } else {
            onResponse(alert.runModal())
        }
    }

    /// Una shell staccata aspetta che questo processo esca e riapre il bundle: la nuova istanza
    /// deve partire **dopo**, o la guardia single-instance la chiuderebbe, e il terminate passa
    /// dal flush del layout e dal salvataggio dei resume.
    private func relaunch() {
        let script = "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; "
            + "/usr/bin/open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", script, Bundle.main.bundlePath,
            String(ProcessInfo.processInfo.processIdentifier),
        ]
        do {
            try process.run()
        } catch {
            log.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
            return
        }
        NSApp.terminate(nil)
    }
}
