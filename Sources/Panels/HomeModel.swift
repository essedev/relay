import Foundation
import WorkspaceModel

/// Logica pura della pagina Home: cosa ti aspetta, cosa lavora da solo, cosa si può mettere via.
/// Separata dalla vista per i test. Guarda solo i progetti **aperti**: un chiuso non ha sessioni
/// vive, e l'hai messo via tu.
public enum HomeModel {
    /// Una sessione da mostrare: la coppia progetto/tab (riferimenti vivi, la riga osserva lo
    /// stato che cambia mentre la pagina è aperta).
    public struct Entry: Identifiable {
        public let workspace: Workspace
        public let tab: WorkspaceModel.Tab

        public var id: UUID {
            tab.id
        }
    }

    /// Da quanto un progetto aperto deve essere fermo per proporti di chiuderlo.
    public static let quietAfter: TimeInterval = 7 * 86400

    /// Le sessioni che ti aspettano: input, errore, completamento non visto. Ordine di triage
    /// (`SessionTriage.urgencyRank`), poi la più recente.
    public static func needsYou(_ workspaces: [Workspace]) -> [Entry] {
        entries(workspaces) { tab in
            tab.agentState == .needsInput || tab.agentState == .error || tab.attention == .unseen
        }
        .sorted { lhs, rhs in
            let lRank = SessionTriage.urgencyRank(lhs.tab)
            let rRank = SessionTriage.urgencyRank(rhs.tab)
            if lRank != rRank { return lRank > rRank }
            return (lhs.tab.lastEventAt ?? .distantPast) > (rhs.tab.lastEventAt ?? .distantPast)
        }
    }

    /// Le sessioni al lavoro da sole, nell'ordine della sidebar.
    public static func working(_ workspaces: [Workspace]) -> [Entry] {
        entries(workspaces) { $0.agentState == .running }
    }

    /// Progetti aperti fermi da più di `quietAfter`: candidati a essere chiusi. Mai uno con un
    /// agente vivo o in attesa, e mai uno di cui non sappiamo niente (`lastActiveAt` nil): meglio
    /// non proporre che proporre a caso.
    public static func quiet(_ workspaces: [Workspace], now: Date = Date()) -> [Workspace] {
        workspaces.filter { workspace in
            guard !workspace.closed, let last = workspace.lastActiveAt,
                  now.timeIntervalSince(last) > quietAfter else { return false }
            return !workspace.tabs.contains {
                $0.agentState == .running || $0.agentState == .needsInput
                    || $0.agentState == .error
            }
        }
    }

    /// I progetti chiusi più di recente, per riaprirli al volo.
    public static func recentlyClosed(_ workspaces: [Workspace], limit: Int = 8) -> [Workspace] {
        Array(workspaces.filter(\.closed).sorted(by: ProjectsModel.byRecency).prefix(limit))
    }

    /// Il titolo della pagina dice la situazione, non il nome del posto.
    public static func headline(needing count: Int) -> String {
        switch count {
        case 0: "Nothing needs you"
        case 1: "1 session needs you"
        default: "\(count) sessions need you"
        }
    }

    private static func entries(
        _ workspaces: [Workspace], where include: (WorkspaceModel.Tab) -> Bool
    ) -> [Entry] {
        workspaces.filter { !$0.closed }.flatMap { workspace in
            workspace.orderedTabs.filter(include).map { Entry(workspace: workspace, tab: $0) }
        }
    }
}
