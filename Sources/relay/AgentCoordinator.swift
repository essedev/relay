import AgentProtocol
import AgentRuntime
import AppKit
import Core
import Foundation
import WorkspaceModel

/// Ponte tra il runtime degli eventi agente e il model UI. Vive nel composition root: è l'unico
/// punto che conosce sia `AgentRuntime` sia `WorkspaceModel`, così `AgentRuntime` resta
/// indipendente
/// dal model (regola ROADMAP Milestone 1). Riceve gli eventi dal socket, li lega alla tab via
/// `paneId` (= `RELAY_TAB_ID`) e applica il reducer.
///
/// Ordine di applicazione: il receiver consegna da thread di background e un `Task {}` per evento
/// non preserva l'ordine di enqueue verso il MainActor; qui gli eventi passano da un
/// `AsyncStream` con un solo consumer (pump FIFO), che applica session store e model in sequenza.
/// Il riordino residuo del trasporto (drain concorrenti nel receiver) lo assorbe la guardia di
/// monotonicità sui timestamp negli store.
@MainActor
final class AgentCoordinator {
    private let store: WorkspaceStore
    private let sessionStore = AgentSessionStore()
    private var receiver: AgentEventReceiver?
    private var events: AsyncStream<AgentStateEvent>.Continuation?
    private var pump: Task<Void, Never>?
    private let log = RelayLog.logger("agent-coordinator")

    init(store: WorkspaceStore) {
        self.store = store
    }

    func start() {
        do {
            try RelayRuntimePaths.ensureRuntimeDirectory()
            let (stream, continuation) = AsyncStream.makeStream(of: AgentStateEvent.self)
            let receiver = AgentEventReceiver { continuation.yield($0) }
            let socketPath = RelayRuntimePaths.socketPath
            try receiver.start()
            events = continuation
            self.receiver = receiver
            // Pump FIFO: unico consumer, eredita il MainActor. Ogni evento è applicato per intero
            // (session store + model) prima del successivo.
            pump = Task { [weak self] in
                for await event in stream {
                    await self?.handle(event)
                }
            }
            log.info("agent runtime listening on \(socketPath, privacy: .public)")
        } catch {
            log.error("agent coordinator failed to start: \(error.localizedDescription)")
        }
    }

    func stop() {
        receiver?.stop()
        receiver = nil
        events?.finish()
        events = nil
        pump?.cancel()
        pump = nil
    }

    // MARK: - Private

    private func handle(_ event: AgentStateEvent) async {
        // Snapshot per sessionId: utile a resume/timeline (Milestone 2). Non guida il badge.
        // Nello stesso pump del model, così i due store vedono gli eventi nello stesso ordine.
        await sessionStore.apply(event)

        // Binding via paneId (= RELAY_TAB_ID = Tab.id). La logica di transizione vive nello store.
        // Passo agent + sessionId: lo store cattura il binding di resume sulla tab.
        guard let paneId = event.paneId else { return }
        // `NSApp.isActive`: se Relay è in background la tab non è "in vista" per l'utente, così il
        // completato resta segnalato e la notifica parte anche sulla tab selezionata.
        store.applyAgentState(
            paneId: paneId,
            agent: event.agent,
            sessionId: event.sessionId,
            state: event.state,
            at: event.timestamp,
            appActive: NSApp.isActive,
            resetsAttention: event.resetsAttention
        )
    }
}
