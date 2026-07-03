import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// MARK: - Cicli tab/workspace e jump indietro

@Test func selectAdjacentTabCycles() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "A")
    let second = store.addTab(to: ws)
    store.selectTab(ws.tabs[0].id, in: ws)

    store.selectAdjacentTab(forward: true)
    #expect(ws.selectedTabID == second.id)
    store.selectAdjacentTab(forward: true) // wrap alla prima
    #expect(ws.selectedTabID == ws.tabs[0].id)
    store.selectAdjacentTab(forward: false) // indietro -> ultima
    #expect(ws.selectedTabID == second.id)
}

@Test func selectAdjacentWorkspaceCycles() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "A")
    let b = store.createWorkspace(name: "B")
    store.selectWorkspace(a.id)

    store.selectAdjacentWorkspace(forward: true)
    #expect(store.selectedWorkspaceID == b.id)
    store.selectAdjacentWorkspace(forward: true) // wrap
    #expect(store.selectedWorkspaceID == a.id)
}

@Test func focusPrevAttentionWraps() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "A")
    let b = store.createWorkspace(name: "B")
    a.tabs[0].attention = .unseen
    b.tabs[0].attention = .unseen
    store.selectWorkspace(a.id)

    // Da A (prima con attenzione), indietro fa wrap all'ultima = B.
    #expect(store.focusPrevAttention())
    #expect(store.selectedWorkspaceID == b.id)
}

// MARK: - KeyCombo

@Test func keyComboDisplay() {
    #expect(KeyCombo(key: "t", modifiers: [.command]).display == "⌘T")
    #expect(KeyCombo(key: "j", modifiers: [.command, .shift]).display == "⇧⌘J")
    #expect(KeyCombo(key: "tab", modifiers: [.control]).display == "⌃⇥")
    #expect(KeyCombo(key: "=", modifiers: [.command]).display == "⌘+")
}

@Test func keyComboCodableRoundTrip() throws {
    let combo = KeyCombo(key: "down", modifiers: [.command, .option])
    let data = try JSONEncoder().encode(combo)
    let back = try JSONDecoder().decode(KeyCombo.self, from: data)
    #expect(back == combo)
}

// MARK: - Persistenza e conflitti (AppSettings è @MainActor)

@MainActor @Test func keybindingDefaultOverridePersist() throws {
    let defaults = try #require(UserDefaults(suiteName: "relay-test-\(UUID().uuidString)"))
    let settings = AppSettings(defaults: defaults)
    #expect(settings.binding(for: .newTab) == KeyCombo(key: "t", modifiers: [.command]))

    let combo = KeyCombo(key: "y", modifiers: [.command, .shift])
    settings.setBinding(combo, for: .newTab)
    #expect(settings.binding(for: .newTab) == combo)

    // Ricaricato dallo stesso store persiste la scelta.
    #expect(AppSettings(defaults: defaults).binding(for: .newTab) == combo)
}

@MainActor @Test func keybindingConflictAndReset() throws {
    let defaults = try #require(UserDefaults(suiteName: "relay-test-\(UUID().uuidString)"))
    let settings = AppSettings(defaults: defaults)
    let newTabCombo = settings.binding(for: .newTab)
    #expect(settings.conflict(for: newTabCombo, excluding: .find) == .newTab)
    #expect(settings.conflict(for: newTabCombo, excluding: .newTab) == nil)

    settings.setBinding(KeyCombo(key: "z", modifiers: [.command]), for: .newTab)
    settings.resetBinding(for: .newTab)
    #expect(settings.binding(for: .newTab) == ShortcutAction.newTab.defaultCombo)
}
