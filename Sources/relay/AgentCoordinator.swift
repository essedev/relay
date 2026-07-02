import AgentProtocol
import AgentRuntime
import Core
import Foundation
import WorkspaceModel

/// Ponte tra il runtime degli eventi agente e il model UI. Vive nel composition root: è l'unico
/// punto che conosce sia `AgentRuntime` sia `WorkspaceModel`, così `AgentRuntime` resta
/// indipendente
/// dal model (regola ROADMAP Milestone 1). Riceve gli eventi dal socket, li lega alla tab via
/// `paneId` (= `RELAY_TAB_ID`) e applica il reducer.
@MainActor
final class AgentCoordinator {
    private let store: WorkspaceStore
    private let sessionStore = AgentSessionStore()
    private var receiver: AgentEventReceiver?
    private let log = RelayLog.logger("agent-coordinator")

    init(store: WorkspaceStore) {
        self.store = store
    }

    func start() {
        do {
            try RelayRuntimePaths.ensureRuntimeDirectory()
            let receiver = AgentEventReceiver { [weak self] event in
                // Callback su thread di background: hop al MainActor per toccare il model.
                Task { @MainActor in self?.handle(event) }
            }
            let socketPath = RelayRuntimePaths.socketPath
            try receiver.start()
            self.receiver = receiver
            log.info("agent runtime listening on \(socketPath, privacy: .public)")
        } catch {
            log.error("agent coordinator failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        receiver?.stop()
        receiver = nil
    }

    // MARK: - Private

    private func handle(_ event: AgentStateEvent) {
        // Snapshot per sessionId: utile a resume/timeline (Milestone 2). Non guida il badge.
        Task { await sessionStore.apply(event) }

        // Binding via paneId (= RELAY_TAB_ID = Tab.id). La logica di transizione vive nello store.
        // Passo agent + sessionId: lo store cattura il binding di resume sulla tab.
        guard let paneId = event.paneId else { return }
        store.applyAgentState(
            paneId: paneId,
            agent: event.agent,
            sessionId: event.sessionId,
            state: event.state,
            at: event.timestamp
        )
    }
}
