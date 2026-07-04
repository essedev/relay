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

private func sampleEvent(
    sessionId: String,
    state: AgentState,
    // Frazioni binarie esatte (.0, .25, .75): il wire ha precisione al millisecondo e il
    // round-trip resta confrontabile con ==.
    timestamp: Date = Date(timeIntervalSince1970: 1000)
) -> AgentStateEvent {
    AgentStateEvent(
        agent: "claude",
        sessionId: sessionId,
        paneId: "tab-\(sessionId)",
        state: state,
        source: .hook,
        confidence: 1,
        timestamp: timestamp
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

// MARK: - Robustezza del socket (no-stomp, self-heal, probe del guard)

@Test func isReceiverReachableReflectsListener() throws {
    let path = uniqueSocketPath()
    #expect(!AgentEventClient.isReceiverReachable(at: path)) // assente
    let receiver = AgentEventReceiver(path: path) { _ in }
    try receiver.start()
    #expect(AgentEventClient.isReceiverReachable(at: path)) // owner vivo
    receiver.stop()
    #expect(!AgentEventClient.isReceiverReachable(at: path)) // fermato -> file rimosso
}

@Test func receiverRefusesToStompLiveSocket() async throws {
    let path = uniqueSocketPath()
    let boxA = ReceivedBox()
    let receiverA = AgentEventReceiver(path: path) { event in
        Task { await boxA.add(event) }
    }
    try receiverA.start()
    defer { receiverA.stop() }

    // Una seconda istanza sullo stesso path non deve rubare il socket: lo start rifiuta.
    let receiverB = AgentEventReceiver(path: path) { _ in }
    #expect(throws: UnixSocketError.addressInUse) { try receiverB.start() }

    // A resta vivo e continua a ricevere: il suo socket non è stato calpestato.
    try AgentEventClient.send(sampleEvent(sessionId: "a", state: .running), to: path)
    #expect(await waitUntil { await boxA.count() >= 1 })
}

@Test func receiverRebindsWhenSocketFileRemoved() async throws {
    // Dir dedicata: isola il watch del self-heal dal churn della temp dir condivisa.
    let dir = "\(NSTemporaryDirectory())relay-selfheal-\(UInt64.random(in: 0 ..< 1_000_000_000))"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    let path = "\(dir)/relay.sock"

    let box = ReceivedBox()
    let receiver = AgentEventReceiver(path: path) { event in
        Task { await box.add(event) }
    }
    try receiver.start()
    defer { receiver.stop() }

    try AgentEventClient.send(sampleEvent(sessionId: "before", state: .running), to: path)
    #expect(await waitUntil { await box.count() >= 1 })

    // Il socket file sparisce sotto il receiver (seconda istanza / pulizia esterna).
    unlink(path)
    // Self-heal: il watch della dir rileva la sparizione e ri-binda, ricreando il file.
    #expect(await waitUntil { FileManager.default.fileExists(atPath: path) })

    // Il receiver rigenerato riceve di nuovo.
    try AgentEventClient.send(sampleEvent(sessionId: "after", state: .idle), to: path)
    #expect(await waitUntil { await box.count() >= 2 })
    let ids = await Set(box.all().map(\.sessionId))
    #expect(ids == ["before", "after"])
}

// MARK: - Wire coding (ordine sub-secondo + retrocompatibilità)

@Test func wirePreservesSubSecondTimestampOrdering() throws {
    // Due eventi nello stesso secondo: senza frazioni sul filo i timestamp collasserebbero e la
    // guardia di monotonicità negli store non distinguerebbe più lo stantio dal fresco.
    let earlier = sampleEvent(
        sessionId: "s",
        state: .running,
        timestamp: Date(timeIntervalSince1970: 1000.25)
    )
    let later = sampleEvent(
        sessionId: "s",
        state: .idle,
        timestamp: Date(timeIntervalSince1970: 1000.75)
    )
    let encoder = AgentWireCoding.makeEncoder()
    let decoder = AgentWireCoding.makeDecoder()
    let decodedEarlier = try decoder.decode(AgentStateEvent.self, from: encoder.encode(earlier))
    let decodedLater = try decoder.decode(AgentStateEvent.self, from: encoder.encode(later))
    #expect(decodedEarlier.timestamp == earlier.timestamp)
    #expect(decodedEarlier.timestamp < decodedLater.timestamp)
}

@Test func decoderAcceptsLegacyWholeSecondTimestamps() throws {
    // Un CLI più vecchio manda ISO 8601 senza frazioni: deve restare decodificabile.
    let line = """
    {"agent":"claude","sessionId":"s","paneId":null,"state":"idle","source":"hook",\
    "confidence":1,"timestamp":"1970-01-01T00:16:40Z"}
    """
    let event = try AgentWireCoding.makeDecoder()
        .decode(AgentStateEvent.self, from: Data(line.utf8))
    #expect(event.timestamp == Date(timeIntervalSince1970: 1000))
}
