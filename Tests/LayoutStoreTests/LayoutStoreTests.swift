import Foundation
@testable import LayoutStore
import Testing
import WorkspaceModel

private func tempPath() -> String {
    (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("relay-layout-\(UUID().uuidString).json")
}

private func sampleSnapshot(name: String = "api") -> LayoutSnapshot {
    let tab = TabSnapshot(
        id: UUID(),
        title: "shell",
        hasCustomTitle: true,
        currentDirectory: "/tmp"
    )
    let workspace = WorkspaceSnapshot(
        id: UUID(),
        name: name,
        rootPath: "/proj",
        pinned: true,
        selectedTabID: tab.id,
        tabs: [tab]
    )
    return LayoutSnapshot(selectedWorkspaceID: workspace.id, workspaces: [workspace])
}

/// Snapshot degradato: un workspace senza tab. A runtime non può esistere (il cascade chiude un
/// workspace quando perde l'ultima tab); su disco è il sintomo che ha fatto sparire le tab.
private func workspaceWithNoTabs() -> LayoutSnapshot {
    let workspace = WorkspaceSnapshot(
        id: UUID(), name: "empty", rootPath: nil, pinned: false, selectedTabID: nil, tabs: []
    )
    return LayoutSnapshot(selectedWorkspaceID: workspace.id, workspaces: [workspace])
}

@Test func saveThenLoadRoundTrips() throws {
    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let store = LayoutStore(path: path)
    let snapshot = sampleSnapshot()

    try store.save(snapshot)

    #expect(store.load() == snapshot)
}

@Test func loadMissingFileReturnsNil() {
    #expect(LayoutStore(path: tempPath()).load() == nil)
}

@Test func loadCorruptReturnsNil() throws {
    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    try "{ not json".write(toFile: path, atomically: true, encoding: .utf8)

    #expect(LayoutStore(path: path).load() == nil)
}

@Test func loadUnsupportedVersionReturnsNil() throws {
    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    var snapshot = sampleSnapshot()
    snapshot.version = 999
    try LayoutStore(path: path).save(snapshot)

    #expect(LayoutStore(path: path).load() == nil)
}

@Test func saveCreatesMissingDirectory() throws {
    let dir = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("relay-\(UUID().uuidString)")
    let path = (dir as NSString).appendingPathComponent("nested/layout.json")
    defer { try? FileManager.default.removeItem(atPath: dir) }

    try LayoutStore(path: path).save(sampleSnapshot())

    #expect(FileManager.default.fileExists(atPath: path))
}

// MARK: - Robustezza (guardia anti-degrado, backup, recovery)

@Test func saveRejectsWorkspaceWithoutTabs() {
    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    #expect(throws: LayoutStoreError.degenerateSnapshot) {
        try LayoutStore(path: path).save(workspaceWithNoTabs())
    }
    // Niente file scritto: uno snapshot degradato non tocca il disco.
    #expect(!FileManager.default.fileExists(atPath: path))
}

@Test func saveRejectsEmptyWorkspaces() {
    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let empty = LayoutSnapshot(selectedWorkspaceID: nil, workspaces: [])
    #expect(throws: LayoutStoreError.degenerateSnapshot) {
        try LayoutStore(path: path).save(empty)
    }
}

@Test func degenerateSaveDoesNotClobberGoodLayout() throws {
    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let store = LayoutStore(path: path)
    let good = sampleSnapshot(name: "good")
    try store.save(good)

    // Un save degradato successivo fallisce e lascia intatto il layout buono.
    #expect(throws: LayoutStoreError.degenerateSnapshot) {
        try store.save(workspaceWithNoTabs())
    }
    #expect(store.load() == good)
}

@Test func saveBacksUpPreviousGoodLayout() throws {
    let path = tempPath()
    let backup = path + ".bak"
    defer {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: backup)
    }
    let store = LayoutStore(path: path)
    try store.save(sampleSnapshot(name: "v1"))
    try store.save(sampleSnapshot(name: "v2"))

    // Il primario è v2, il backup conserva v1.
    #expect(FileManager.default.fileExists(atPath: backup))
    let backedUp = try JSONDecoder()
        .decode(LayoutSnapshot.self, from: #require(FileManager.default.contents(atPath: backup)))
    #expect(backedUp.workspaces.first?.name == "v1")
}

@Test func loadRecoversFromBackupWhenPrimaryCorrupt() throws {
    let path = tempPath()
    let backup = path + ".bak"
    defer {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: backup)
    }
    let store = LayoutStore(path: path)
    try store.save(sampleSnapshot(name: "v1")) // primario v1
    try store.save(sampleSnapshot(name: "v2")) // primario v2, backup v1

    // Il primario si corrompe (scrittura interrotta, race): la load ricade sul backup.
    try "{ corrotto".write(toFile: path, atomically: true, encoding: .utf8)
    #expect(store.load()?.workspaces.first?.name == "v1")
}

@Test func loadRecoversFromBackupWhenPrimaryDegraded() throws {
    let path = tempPath()
    let backup = path + ".bak"
    defer {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: backup)
    }
    let store = LayoutStore(path: path)
    try store.save(sampleSnapshot(name: "v1"))
    try store.save(sampleSnapshot(name: "v2"))

    // Il primario viene sostituito da uno snapshot degradato (workspace senza tab), scritto
    // aggirando la guardia (simula la corruzione osservata). La load lo scarta e usa il backup.
    let degraded = try JSONEncoder().encode(workspaceWithNoTabs())
    try degraded.write(to: URL(fileURLWithPath: path))
    #expect(store.load()?.workspaces.first?.name == "v1")
}

/// Regressione: se il primario è corrotto (corruzione esterna, downgrade), il save successivo NON
/// deve ruotare quella corruzione sopra il `.bak` buono - altrimenti si perde l'ultimo layout
/// valido.
@Test func corruptPrimaryIsNotRotatedIntoBackup() throws {
    let path = tempPath()
    let backup = path + ".bak"
    defer {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: backup)
    }
    let store = LayoutStore(path: path)
    try store.save(sampleSnapshot(name: "v1"))
    try store.save(sampleSnapshot(name: "v2")) // backup = v1

    // Il primario si corrompe fuori dal nostro controllo, poi arriva un nuovo save: la corruzione
    // non deve essere ruotata sopra il backup (che tiene l'ultima generazione buona, v1).
    try "{ corrotto".write(toFile: path, atomically: true, encoding: .utf8)
    try store.save(sampleSnapshot(name: "v3"))

    // Cancellato il primario, la load recupera dal backup un layout valido, non la corruzione.
    try FileManager.default.removeItem(atPath: path)
    #expect(store.load()?.workspaces.first?.name == "v1")
}

@Test func isValidForPersistenceRejectsDegenerateShapes() {
    #expect(LayoutStore.isValidForPersistence(sampleSnapshot()))
    #expect(!LayoutStore.isValidForPersistence(workspaceWithNoTabs()))
    #expect(!LayoutStore.isValidForPersistence(
        LayoutSnapshot(selectedWorkspaceID: nil, workspaces: [])
    ))
}

/// Regressione: un layout su disco come quello reale (workspace multipli, tab con e senza
/// `resume`, titoli con caratteri non-ASCII) deve restaurare **le tab e i binding di resume**.
/// Riproduce la forma esatta del `~/.relay/layout.json` osservato quando la 0.2.3 mostrava i
/// workspace senza tab: il restore è sano, quindi quel guasto è runtime (persistenza), non decode.
@Test @MainActor func restoresTabsAndResumeFromRealLayout() throws {
    let json = """
    {
      "version": 1,
      "selectedWorkspaceID": "0AA31CDB-7967-4262-8EAA-1FC721BE88B2",
      "workspaces": [
        { "id": "AA997D5F-C00E-44F6-B978-6A6EFF866CF2", "name": "Misc", "pinned": false,
          "rootPath": "/Users/doppia", "selectedTabID": "F325EFBD-D829-49A9-ABFB-053FAEA50DFF",
          "tabs": [
            { "id": "F325EFBD-D829-49A9-ABFB-053FAEA50DFF", "title": "a", "hasCustomTitle": false },
            { "id": "07133DC3-559F-4D42-98B0-A3893E9F4D75", "title": "b", "hasCustomTitle": false }
          ] },
        { "id": "0AA31CDB-7967-4262-8EAA-1FC721BE88B2", "name": "Relay", "pinned": false,
          "rootPath": "/Users/doppia", "selectedTabID": "094403C7-3ABD-47DA-99E5-7C05D14C3EEB",
          "tabs": [
            { "id": "094403C7-3ABD-47DA-99E5-7C05D14C3EEB", "title": "⠂ Verificare bug",
              "hasCustomTitle": false,
              "resume": { "agent": "claude", "label": "⠐ Verificare bug",
                          "sessionId": "2bf36d53-b398-416f-9c05-1ae2c7964525" } }
          ] }
      ]
    }
    """
    let path = tempPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    try Data(json.utf8).write(to: URL(fileURLWithPath: path))

    let snapshot = try #require(LayoutStore(path: path).load())
    let store = WorkspaceStore()
    store.restore(from: snapshot)

    #expect(store.workspaces.count == 2)
    #expect(store.workspaces.map(\.tabs.count) == [2, 1]) // le tab ci sono
    let relay = try #require(store.workspaces.first { $0.name == "Relay" })
    let tab = try #require(relay.tabs.first)
    #expect(tab.resume?.sessionId == "2bf36d53-b398-416f-9c05-1ae2c7964525")
    #expect(tab.pendingResume) // agentState .unknown + resume != nil -> ResumeBar al focus
}
