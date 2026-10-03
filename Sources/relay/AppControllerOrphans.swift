import Foundation
import TerminalEngine

/// Le sessioni pty oltre la vita dell'app. Chiudere una tab chiude la sua sessione
/// (`PtySessionTeardown`); uscire o crashare no, e un agente bloccato sopravvive all'hangup del
/// kernel per giorni. Qui c'è solo il cablaggio: cosa è nostro e come si chiude lo decide
/// `PtySessionReaper`, che ha i suoi test.
extension AppController {
    /// Al lancio, prima di ripristinare qualsiasi cosa: chiude le sessioni registrate da run il cui
    /// Relay non c'è più (uscita, crash, force quit). Un resume accanto al suo orfano scriverebbe
    /// due volte sullo stesso transcript. Blocca solo se ci sono orfani, al massimo un secondo e
    /// mezzo.
    func reapOrphanedSessions() {
        let start = Date()
        let outcome = PtySessionReaper.reapOrphans(
            in: sessionLedger.directory,
            currentRunID: sessionLedger.runID
        )
        guard outcome.sessions > 0 else { return }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        log.notice("orphaned sessions closed at launch in \(elapsed, privacy: .public) ms")
    }
}
