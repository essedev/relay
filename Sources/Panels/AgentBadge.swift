import AgentProtocol
import SwiftUI
import WorkspaceModel

/// Tipo di badge da mostrare. Distingue lo *stato* (running = sta lavorando, sempre visibile) dal
/// marker *attention* (novità non vista: needs_input, error, completed) che si spegne alla visita.
/// Il `rawValue` è anche l'ordine di severità per l'aggregazione a livello workspace.
enum BadgeKind: Int {
    case none = 0
    case completed = 1
    case running = 2
    case error = 3
    case needsInput = 4

    /// Badge di una singola tab. `running`/`needs_input`/`error` sono *stati*: il badge resta
    /// finché
    /// lo stato cambia (needs_input si spegne quando rispondi a Claude, non alla visita). Solo il
    /// marker "completato" (idle dopo running) è transitorio e dipende da `attention`.
    static func forTab(_ tab: WorkspaceModel.Tab) -> BadgeKind {
        switch tab.agentState {
        case .running: .running
        case .needsInput: .needsInput
        case .error: .error
        case .idle: tab.attention ? .completed : .none
        case .unknown: .none
        }
    }

    /// Badge aggregato di un workspace: il più severo tra le sue tab.
    static func forWorkspace(_ workspace: Workspace) -> BadgeKind {
        workspace.tabs.map(forTab).max { $0.rawValue < $1.rawValue } ?? .none
    }
}

/// Vista del badge di stato agente. Piccola, attinge i colori dal `Theme`.
struct AgentBadge: View {
    let kind: BadgeKind

    var body: some View {
        switch kind {
        case .none:
            EmptyView()
        case .running:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
        case .needsInput:
            dot(Theme.Colors.agentNeedsInput)
        case .error:
            dot(Theme.Colors.agentError)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(Theme.Colors.agentCompleted)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}
