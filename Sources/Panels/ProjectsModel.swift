import Foundation
import WorkspaceModel

/// Logica pura della pagina Projects: il catalogo di tutti i progetti, aperti e chiusi, diviso per
/// gruppo come la sidebar. Separata dalla vista per i test.
public enum ProjectsModel {
    public enum Filter: CaseIterable, Sendable {
        case all
        case open
        case closed

        public var title: String {
            switch self {
            case .all: "All"
            case .open: "Open"
            case .closed: "Closed"
            }
        }

        func admits(_ workspace: Workspace) -> Bool {
            switch self {
            case .all: true
            case .open: !workspace.closed
            case .closed: workspace.closed
            }
        }
    }

    /// Una sezione del catalogo: un gruppo coi suoi progetti, o quelli senza gruppo (`group` nil).
    public struct Section: Identifiable {
        public let group: WorkspaceGroup?
        public let projects: [Workspace]

        public var id: UUID? {
            group?.id
        }
    }

    /// Sezioni nell'ordine dei gruppi, poi i progetti senza gruppo. Dentro una sezione gli aperti
    /// vengono prima, poi il più recente: il catalogo serve a ritrovare, e quello su cui hai
    /// lavorato da poco è il candidato più probabile. Una sezione vuota dopo il filtro sparisce.
    public static func sections(
        workspaces: [Workspace],
        groups: [WorkspaceGroup],
        query: String = "",
        filter: Filter = .all
    ) -> [Section] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = workspaces.filter { workspace in
            filter.admits(workspace) && (needle.isEmpty || matches(workspace, needle))
        }
        let known = Set(groups.map(\.id))
        let grouped = groups.map { group in
            Section(group: group, projects: sorted(visible.filter { $0.groupID == group.id }))
        }
        let loose = Section(
            group: nil,
            projects: sorted(visible.filter { $0.groupID.map { !known.contains($0) } ?? true })
        )
        return (grouped + [loose]).filter { !$0.projects.isEmpty }
    }

    /// Aperti prima, poi il più recente; a pari merito il nome, così l'ordine non balla.
    static func sorted(_ projects: [Workspace]) -> [Workspace] {
        projects.sorted { lhs, rhs in
            if lhs.closed != rhs.closed { return !lhs.closed }
            return byRecency(lhs, rhs)
        }
    }

    /// Il più recente prima; chi non ha mai registrato attività va in fondo, in ordine di nome.
    static func byRecency(_ lhs: Workspace, _ rhs: Workspace) -> Bool {
        switch (lhs.lastActiveAt, rhs.lastActiveAt) {
        case let (left?, right?) where left != right: left > right
        case (.some, nil): true
        case (nil, .some): false
        default: lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// La ricerca guarda nome e cartella: "zeno" trova il progetto anche se l'hai chiamato altro.
    static func matches(_ workspace: Workspace, _ needle: String) -> Bool {
        workspace.name.lowercased().contains(needle)
            || (workspace.rootPath?.lowercased().contains(needle) ?? false)
    }

    /// Le sessioni agente di un progetto: quelle con uno stato vivo o un resume da proporre.
    public static func sessions(of workspace: Workspace) -> [WorkspaceModel.Tab] {
        workspace.orderedTabs.filter(SessionTriage.isSession)
    }
}
