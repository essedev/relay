import Foundation
@testable import LayoutStore
import Testing
import WorkspaceModel

private func tempPath() -> String {
    (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("relay-layout-\(UUID().uuidString).json")
}

private func sampleSnapshot() -> LayoutSnapshot {
    let tab = TabSnapshot(
        id: UUID(),
        title: "shell",
        hasCustomTitle: true,
        currentDirectory: "/tmp"
    )
    let workspace = WorkspaceSnapshot(
        id: UUID(),
        name: "api",
        rootPath: "/proj",
        pinned: true,
        selectedTabID: tab.id,
        tabs: [tab]
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
