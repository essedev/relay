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

/// Aggregato workspace: il badge più severo e quante tab lo condividono. Il contatore compare
/// solo da 2 in su ("quanti Claude aspettano input" è la coda di lavoro, con 1 è rumore).
struct WorkspaceBadgeInfo: Equatable {
    let kind: BadgeKind
    let count: Int

    static func forWorkspace(_ workspace: Workspace) -> WorkspaceBadgeInfo {
        let kinds = workspace.tabs.map(BadgeKind.forTab)
        let top = kinds.max { $0.rawValue < $1.rawValue } ?? .none
        let count = top == .none ? 0 : kinds.count { $0 == top }
        return WorkspaceBadgeInfo(kind: top, count: count)
    }
}

/// Badge del workspace in sidebar: stato più severo + contatore quando ≥2 tab lo condividono.
struct WorkspaceBadge: View {
    let workspace: Workspace
    let colors: ChromeColors

    var body: some View {
        let info = WorkspaceBadgeInfo.forWorkspace(workspace)
        HStack(spacing: Theme.Spacing.xxs) {
            // Il contatore ("quante tab in questo stato") sta a sinistra del pallino di stato.
            if info.count >= 2 {
                Text("\(info.count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(colors.secondary)
            }
            AgentBadge(kind: info.kind, colors: colors)
        }
    }
}

/// Vista del badge di stato agente. Piccola, colori derivati dal tema (`ChromeColors`).
struct AgentBadge: View {
    let kind: BadgeKind
    let colors: ChromeColors

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
            PulsingDot(color: colors.needsInput) // richiede attenzione: pulsa
        case .error:
            dot(colors.error)
        case .completed:
            dot(colors.completed)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

/// Pallino che pulsa dolcemente, per segnalare che serve attenzione (needs_input).
private struct PulsingDot: View {
    let color: Color
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(dim ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
    }
}
