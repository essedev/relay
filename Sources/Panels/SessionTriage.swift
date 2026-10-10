import Foundation
import WorkspaceModel

/// Regole di triage delle sessioni agente, condivise da Home e Projects: cosa conta come sessione,
/// quanto reclama te, e l'età compatta di un evento. Pura e testata.
enum SessionTriage {
    /// È una sessione agente: ha uno stato vivo, un completamento (anche in sospeso a sessione
    /// finita) o un resume proponibile. Le shell nude restano fuori: sono rumore per il triage.
    static func isSession(_ tab: WorkspaceModel.Tab) -> Bool {
        tab.agentState != .unknown || tab.attention != .none || tab.resume != nil
    }

    /// Urgenza (desc). Diversa dalla severità dei badge: qui è triage, ciò che aspetta *te* (input,
    /// errore, completamenti) viene prima di ciò che lavora da solo.
    static func urgencyRank(_ tab: WorkspaceModel.Tab) -> Int {
        if tab.agentState == .needsInput { return 5 }
        if tab.agentState == .error { return 4 }
        if tab.attention == .unseen { return 3 }
        if tab.attention == .pending { return 2 }
        if tab.agentState == .running { return 1 }
        return 0 // idle / solo resume
    }

    /// Il momento che dà l'età a una sessione: per un marker (unseen/pending) da quando è in
    /// vigore, altrimenti l'ultimo evento. Un no-op (SessionEnd, idle->idle) che avanza
    /// `lastEventAt` per la monotonicità non ringiovanisce un sospeso.
    static func ageDate(for tab: WorkspaceModel.Tab) -> Date? {
        tab.attention == .none ? tab.lastEventAt : (tab.attentionSince ?? tab.lastEventAt)
    }

    /// Età compatta di un timestamp ("now", "45s", "3m", "2h", "5d"). `nil` senza timestamp.
    static func age(of date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<10: return "now"
        case ..<60: return "\(Int(seconds))s"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }
}
