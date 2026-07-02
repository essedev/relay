import AgentProtocol
import AgentRuntime
import Foundation

/// Demo mode (`relay --demo [NxM]`): popola l'app con N workspace da M tab e simula sessioni
/// agente concorrenti su ogni tab. Gli eventi passano dal socket reale (`AgentEventClient` ->
/// receiver -> coordinator), come una sessione vera: nel model non esiste un percorso finto.
struct DemoConfig {
    let workspaces: Int
    let tabsPerWorkspace: Int

    /// Riconosce `--demo` con dimensione opzionale `NxM` (default 4x3).
    static func parse(from args: [String]) -> DemoConfig? {
        guard let index = args.firstIndex(of: "--demo") else { return nil }
        if index + 1 < args.count {
            let parts = args[index + 1].lowercased().split(separator: "x")
            if parts.count == 2, let n = Int(parts[0]), let m = Int(parts[1]), n > 0, m > 0 {
                return DemoConfig(workspaces: min(n, 9), tabsPerWorkspace: min(m, 9))
            }
        }
        return DemoConfig(workspaces: 4, tabsPerWorkspace: 3)
    }
}

/// Simula una sessione agente indipendente per ogni tab: cicli idle -> running -> (a volte)
/// needs_input -> ... con tempi casuali, così sidebar e tab bar vivono di stati diversi.
final class DemoDriver {
    private var tasks: [Task<Void, Never>] = []

    func start(tabIDs: [UUID]) {
        tasks = tabIDs.map { tabID in
            Task.detached(priority: .utility) { await Self.runSession(tabID: tabID) }
        }
    }

    func stop() {
        for task in tasks {
            task.cancel()
        }
        tasks = []
    }

    // MARK: - Sessione simulata (fuori dal MainActor: parla solo col socket)

    private static func runSession(tabID: UUID) async {
        let sessionId = "demo-\(tabID.uuidString.prefix(8))"
        var state = AgentState.idle
        // Partenza sfalsata, così le tab non cambiano stato in coro.
        try? await Task.sleep(for: .seconds(Double.random(in: 0.3 ... 4)))
        while !Task.isCancelled {
            let step = nextStep(after: state)
            send(step.state, sessionId: sessionId, tabID: tabID)
            state = step.state
            try? await Task.sleep(for: .seconds(step.delay))
        }
    }

    /// Macchina a stati con probabilità: la forma tipica di una sessione di coding agent.
    private static func nextStep(after state: AgentState) -> (state: AgentState, delay: Double) {
        switch state {
        case .idle, .unknown, .error:
            (.running, .random(in: 3 ... 9))
        case .running:
            // Nel 35% dei casi l'agente chiede un permesso, altrimenti completa.
            Double.random(in: 0 ... 1) < 0.35
                ? (.needsInput, .random(in: 4 ... 10))
                : (.idle, .random(in: 3 ... 10))
        case .needsInput:
            (.running, .random(in: 2 ... 6))
        }
    }

    private static func send(_ state: AgentState, sessionId: String, tabID: UUID) {
        let event = AgentStateEvent(
            agent: "claude",
            sessionId: sessionId,
            paneId: tabID.uuidString,
            state: state,
            source: .hook,
            confidence: 1,
            timestamp: Date()
        )
        try? AgentEventClient.send(event) // receiver assente = demo silenziosamente ferma
    }
}
