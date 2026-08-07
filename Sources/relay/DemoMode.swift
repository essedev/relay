import AgentProtocol
import AgentRuntime
import Core
import Foundation
import WorkspaceModel

/// Seeding dello store per la demo: N workspace da M tab con titoli plausibili. Usa solo l'API
/// pubblica dello store. Ritorna gli id di tutte le tab create (per avviare le sessioni simulate).
@MainActor
enum DemoSeeder {
    private static let tabTitles = [
        "agent", "build", "server", "tests", "logs", "repl", "infra", "docs", "db",
    ]

    static func seed(_ config: DemoConfig, into store: WorkspaceStore) -> [UUID] {
        var allTabIDs: [UUID] = []
        for index in 1 ... config.workspaces {
            let workspace = store.createWorkspace(
                name: "Demo \(index)",
                nameOrigin: .user, // la demo non nomina: nomi fissi (il NamingController è assente)
                rootPath: NSHomeDirectory()
            )
            // createWorkspace aggiunge già una tab: rinominala e aggiungi le altre.
            store.renameTab(workspace.tabs[0].id, in: workspace, to: tabTitles[0])
            for tabIndex in 1 ..< config.tabsPerWorkspace {
                store.addTab(to: workspace, title: tabTitles[tabIndex % tabTitles.count])
            }
            if let first = workspace.tabs.first {
                store.selectTab(first.id, in: workspace)
            }
            allTabIDs.append(contentsOf: workspace.tabs.map(\.id))
        }
        seedGroup(into: store)
        seedPinAndArchive(into: store)
        seedSplit(into: store)
        store.selectWorkspace(store.workspaces[0].id)
        return allTabIDs
    }

    /// Una card di esempio attorno ai primi due workspace: la demo serve a vedere l'app "piena",
    /// e i gruppi sono parte di come si presenta la sidebar. Con meno di tre workspace si salta
    /// (una card che contiene tutto non mostra il confronto con le righe libere).
    private static func seedGroup(into store: WorkspaceStore) {
        guard store.workspaces.count >= 3 else { return }
        store.createGroup(name: "Demo Group", with: store.workspaces.prefix(2).map(\.id))
    }

    /// Una riga pinned in testa e una archiviata in fondo: come i gruppi, sono parte di come si
    /// presenta la sidebar piena, e senza di loro la demo mostra una lista tutta uguale. Servono
    /// almeno quattro workspace perché ne restino di "liberi" fra i due estremi.
    private static func seedPinAndArchive(into store: WorkspaceStore) {
        guard store.workspaces.count >= 4 else { return }
        store.togglePin(store.workspaces[2].id)
        store.setArchived(store.workspaces[store.workspaces.count - 1].id, true)
    }

    /// Uno split affiancato ("Split Right") sul primo workspace, più una tab: il modello
    /// "il pane ospita le tab" si vede solo se un pane ne ha più di una.
    private static func seedSplit(into store: WorkspaceStore) {
        guard let workspace = store.workspaces.first, workspace.tabs.count >= 2 else { return }
        guard let split = store.splitPane(axis: .horizontal, in: workspace) else { return }
        store.renameTab(split.id, in: workspace, to: "tests")
        store.addTab(to: workspace, title: "logs")
    }
}

/// Demo mode (`relay --demo [NxM]`): popola l'app con N workspace da M tab e simula sessioni
/// agente concorrenti su ogni tab. Gli eventi passano dal socket reale (`AgentEventClient` ->
/// receiver -> coordinator), come una sessione vera: nel model non esiste un percorso finto.
struct DemoConfig {
    let workspaces: Int
    let tabsPerWorkspace: Int
    /// Overlay da aprire subito dopo il seed (`--show dashboard|guide`): serve agli screenshot
    /// automatici (`scripts/screenshots.sh`), che non possono premere `Cmd+D` da soli.
    let overlay: DemoOverlay?

    /// Riconosce `--demo` con dimensione opzionale `NxM` (default 4x3) e `--show <overlay>`.
    static func parse(from args: [String]) -> DemoConfig? {
        guard let index = args.firstIndex(of: "--demo") else { return nil }
        let overlay = args.firstIndex(of: "--show")
            .flatMap { $0 + 1 < args.count ? DemoOverlay(rawValue: args[$0 + 1]) : nil }
        if index + 1 < args.count {
            let parts = args[index + 1].lowercased().split(separator: "x")
            if parts.count == 2, let n = Int(parts[0]), let m = Int(parts[1]), n > 0, m > 0 {
                return DemoConfig(
                    workspaces: min(n, 9), tabsPerWorkspace: min(m, 9), overlay: overlay
                )
            }
        }
        return DemoConfig(workspaces: 4, tabsPerWorkspace: 3, overlay: overlay)
    }
}

/// Gli overlay che la demo sa aprire da sola.
enum DemoOverlay: String {
    case dashboard
    case guide
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
            runId: RelayRunID.current, // il driver gira in-process: stessa run del fence
            state: state,
            source: .hook,
            confidence: 1,
            timestamp: Date()
        )
        try? AgentEventClient.send(event) // receiver assente = demo silenziosamente ferma
    }
}
