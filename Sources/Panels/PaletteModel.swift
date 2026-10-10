import Foundation
import WorkspaceModel

/// Logica pura della palette "Go to project" (`⌘P`): quali progetti mostrare per una query e in
/// che ordine. Gli aperti prima (ci torni più spesso), poi i chiusi; dentro ciascun gruppo vince la
/// corrispondenza migliore, poi il più recente.
public enum PaletteModel {
    /// Quanti risultati mostrare: oltre, si affina la query.
    public static let limit = 14

    /// I progetti che corrispondono, nell'ordine in cui la palette li elenca.
    public static func results(_ workspaces: [Workspace], query: String) -> [Workspace] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let scored = workspaces.compactMap { workspace in
            score(workspace, needle).map { (workspace, $0) }
        }
        let ordered = scored.sorted { lhs, rhs in
            if lhs.0.closed != rhs.0.closed { return !lhs.0.closed }
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return ProjectsModel.byRecency(lhs.0, rhs.0)
        }
        return Array(ordered.prefix(limit).map(\.0))
    }

    /// Quanto un progetto corrisponde: `nil` = per niente. Inizio del nome > parola del nome >
    /// dentro il nome > dentro la cartella > lettere del nome nell'ordine ("yad" -> "Yellow AI
    /// Adoption"). Query vuota: tutti, a pari merito.
    static func score(_ workspace: Workspace, _ needle: String) -> Int? {
        guard !needle.isEmpty else { return 0 }
        let name = workspace.name.lowercased()
        if name.hasPrefix(needle) { return 5 }
        if name.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 4 }
        if name.contains(needle) { return 3 }
        if workspace.rootPath?.lowercased().contains(needle) == true { return 2 }
        return isSubsequence(needle, of: name) ? 1 : nil
    }

    static func isSubsequence(_ needle: String, of text: String) -> Bool {
        var rest = needle[...]
        for character in text where character == rest.first {
            rest = rest.dropFirst()
            if rest.isEmpty { return true }
        }
        return rest.isEmpty
    }
}
