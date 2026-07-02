import AgentProtocol
@testable import AgentRuntime
import Foundation
import Testing

/// Colletta thread-safe degli eventi ricevuti dal receiver.
private actor ReceivedBox {
    private var events: [AgentStateEvent] = []
    func add(_ event: AgentStateEvent) {
        events.append(event)
    }

    func count() -> Int {
        events.count
    }

    func all() -> [AgentStateEvent] {
        events
    }
}

private func uniqueSocketPath() -> String {
    "\(NSTemporaryDirectory())relay-\(UInt64.random(in: 0 ..< 1_000_000_000)).sock"
}

private func waitUntil(
    _ condition: @Sendable () async -> Bool,
    attempts: Int = 200
) async -> Bool {
    for _ in 0 ..< attempts {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

private func sampleEvent(sessionId: String, state: AgentState) -> AgentStateEvent {
    AgentStateEvent(
        agent: "claude",
        sessionId: sessionId,
        paneId: "tab-\(sessionId)",
        state: state,
        source: .hook,
        confidence: 1,
        // Secondi interi: la strategia ISO 8601 ha precisione al secondo, così il round-trip è
        // esatto.
        timestamp: Date(timeIntervalSince1970: 1000)
    )
}

@Test func receiverReceivesEventFromClient() async throws {
    let path = uniqueSocketPath()
    let box = ReceivedBox()
    let receiver = AgentEventReceiver(path: path) { event in
        Task { await box.add(event) }
    }
    try receiver.start()
    defer { receiver.stop() }

    let event = sampleEvent(sessionId: "s1", state: .needsInput)
    try AgentEventClient.send(event, to: path)

    let delivered = await waitUntil { await box.count() >= 1 }
    #expect(delivered)
    let all = await box.all()
    #expect(all.first == event)
}

@Test func receiverHandlesMultipleConnections() async throws {
    let path = uniqueSocketPath()
    let box = ReceivedBox()
    let receiver = AgentEventReceiver(path: path) { event in
        Task { await box.add(event) }
    }
    try receiver.start()
    defer { receiver.stop() }

    try AgentEventClient.send(sampleEvent(sessionId: "a", state: .running), to: path)
    try AgentEventClient.send(sampleEvent(sessionId: "b", state: .idle), to: path)

    let delivered = await waitUntil { await box.count() >= 2 }
    #expect(delivered)
    let ids = await Set(box.all().map(\.sessionId))
    #expect(ids == ["a", "b"])
}

@Test func clientThrowsWhenNoReceiver() {
    let path = uniqueSocketPath()
    #expect(throws: UnixSocketError.self) {
        try AgentEventClient.send(sampleEvent(sessionId: "x", state: .idle), to: path)
    }
}
