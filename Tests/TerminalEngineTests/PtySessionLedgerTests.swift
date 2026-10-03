import Darwin
import Foundation
@testable import TerminalEngine
import Testing

// Il registro è ciò che sopravvive a Relay: se un file non si legge, gli orfani della sua run non
// li ritrova più nessuno. Per questo il decode è tollerante e la scrittura si prova su disco vero
// (dir temporanea, mai `~/.relay`).

private func temporaryLedgerDirectory() -> String {
    (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("relay-sessions-\(UInt64.random(in: 0 ..< 1_000_000_000))")
}

private func decode(_ json: String) throws -> PtySessionLedgerFile {
    try JSONDecoder().decode(PtySessionLedgerFile.self, from: Data(json.utf8))
}

// MARK: - Decode tollerante

@Test func ledgerFileRoundTrips() throws {
    let file = PtySessionLedgerFile(
        runId: "run-a",
        owner: ProcessIdentity(pid: 42, startedAt: 1000),
        sessions: [PtySessionRecord(shellPid: 100, shellStartedAt: 2000, tabId: "tab-1")]
    )
    let decoded = try JSONDecoder().decode(
        PtySessionLedgerFile.self, from: JSONEncoder().encode(file)
    )
    #expect(decoded == file)
}

@Test func malformedSessionEntriesAreSkippedNotFatal() throws {
    let file = try decode("""
    {"version": 1, "runId": "run-a", "owner": {"pid": 42, "startedAt": 1000},
     "sessions": [
       {"shellPid": 100, "shellStartedAt": 2000, "tabId": "tab-1"},
       {"shellPid": "not a pid"},
       {"shellPid": 101, "shellStartedAt": 2001}
     ]}
    """)
    #expect(file.sessions.map(\.shellPid) == [100, 101])
    #expect(file.sessions[1].tabId == nil)
}

@Test func aBrokenMemberListDoesNotCostTheSession() throws {
    // `members` è additivo: senza (file di prima) o illeggibile, la voce resta con la sola prova
    // del leader.
    let file = try decode("""
    {"runId": "run-a", "owner": {"pid": 42, "startedAt": 1000},
     "sessions": [
       {"shellPid": 100, "shellStartedAt": 2000, "members": [{"pid": 7, "startedAt": 3000}]},
       {"shellPid": 101, "shellStartedAt": 2001, "members": "garbage"},
       {"shellPid": 102, "shellStartedAt": 2002}
     ]}
    """)
    #expect(file.sessions.map(\.shellPid) == [100, 101, 102])
    #expect(file.sessions[0].members == [ProcessIdentity(pid: 7, startedAt: 3000)])
    #expect(file.sessions[1].members.isEmpty)
    #expect(file.sessions[2].members.isEmpty)
}

@Test func missingSessionsAndVersionDecodeAsEmptyCurrent() throws {
    let file = try decode(#"{"runId": "run-a", "owner": {"pid": 42, "startedAt": 1000}}"#)
    #expect(file.sessions.isEmpty)
    #expect(file.version == PtySessionLedgerFile.currentVersion)
}

@Test func unknownFieldsFromANewerVersionAreIgnored() throws {
    let file = try decode("""
    {"version": 9, "runId": "run-a", "owner": {"pid": 42, "startedAt": 1000, "name": "relay"},
     "host": "x", "sessions": [{"shellPid": 100, "shellStartedAt": 2000, "pgid": 7}]}
    """)
    #expect(file.version == 9)
    #expect(file.sessions.map(\.shellPid) == [100])
}

@Test func aFileWithoutOwnerIsUnusable() {
    // Senza l'identità del Relay che le possedeva non si può dire se le sessioni sono orfane.
    #expect(throws: (any Error).self) {
        try decode(#"{"runId": "run-a", "sessions": []}"#)
    }
}

// MARK: - Scrittura

@MainActor
@Test func recordWritesTheRunFileAndForgetRemovesIt() throws {
    let directory = temporaryLedgerDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let owner = try #require(ProcessIdentity.current)
    let ledger = PtySessionLedger(directory: directory, runID: "run-a", owner: owner)

    // Un processo vivo qualsiasi fa da shell: il registro ne legge solo pid e avvio.
    ledger.record(shellPid: getpid(), tabID: "tab-1")
    let data = try Data(contentsOf: URL(fileURLWithPath: ledger.path))
    let file = try JSONDecoder().decode(PtySessionLedgerFile.self, from: data)
    #expect(file.runId == "run-a")
    #expect(file.owner == owner)
    let expected = PtySessionRecord(
        shellPid: getpid(), shellStartedAt: owner.startedAt, tabId: "tab-1"
    )
    #expect(file.sessions == [expected])

    ledger.forget(shellPid: getpid())
    #expect(ledger.records.isEmpty)
    // Un file vuoto non ha niente da dire al prossimo lancio.
    #expect(!FileManager.default.fileExists(atPath: ledger.path))
}

@MainActor
@Test func aShellThatIsAlreadyGoneLeavesNoRecord() {
    let directory = temporaryLedgerDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let ledger = PtySessionLedger(directory: directory, runID: "run-a")

    ledger.record(shellPid: 0, tabID: nil)
    ledger.record(shellPid: 1, tabID: nil) // launchd: mai una voce, mai un bersaglio
    #expect(ledger.records.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: directory))
}

// MARK: - Lettura delle altre run

@Test func otherRunsSkipsTheCurrentOneAndDropsUnreadableFiles() throws {
    let directory = temporaryLedgerDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let previous = PtySessionLedgerFile(
        runId: "run-old", owner: ProcessIdentity(pid: 42, startedAt: 1), sessions: []
    )
    try JSONEncoder().encode(previous)
        .write(to: URL(fileURLWithPath: "\(directory)/run-old.json"))
    try JSONEncoder().encode(previous)
        .write(to: URL(fileURLWithPath: "\(directory)/run-now.json"))
    try Data("{ not json".utf8).write(to: URL(fileURLWithPath: "\(directory)/broken.json"))
    try Data("note".utf8).write(to: URL(fileURLWithPath: "\(directory)/README"))

    let stored = PtySessionLedger.otherRuns(in: directory, excluding: "run-now")

    #expect(stored.map(\.file.runId) == ["run-old"])
    #expect(!FileManager.default.fileExists(atPath: "\(directory)/broken.json"))
    #expect(FileManager.default.fileExists(atPath: "\(directory)/run-now.json"))
    #expect(FileManager.default.fileExists(atPath: "\(directory)/README")) // non è nostro
}

@Test func aMissingDirectoryMeansNoPreviousRuns() {
    #expect(PtySessionLedger.otherRuns(in: temporaryLedgerDirectory(), excluding: "x").isEmpty)
}
