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

// MARK: - Validazione del recorder

@Test func strongModifierIsRequired() {
    // Un tasto nudo o con solo shift è digitazione, non una scorciatoia.
    #expect(!KeyCombo(key: "a", modifiers: []).hasStrongModifier)
    #expect(!KeyCombo(key: "a", modifiers: [.shift]).hasStrongModifier)
    #expect(KeyCombo(key: "a", modifiers: [.command]).hasStrongModifier)
    #expect(KeyCombo(key: "c", modifiers: [.control]).hasStrongModifier)
    #expect(KeyCombo(key: "a", modifiers: [.option]).hasStrongModifier)
}

@Test func recorderRejectsUnbindableCombos() {
    // Control-char del terminale.
    #expect(KeyCombo(key: "c", modifiers: [.control]).recordingRejection == .terminal)
    #expect(KeyCombo(key: "d", modifiers: [.control]).recordingRejection == .terminal)
    // Comandi di sistema.
    #expect(KeyCombo(key: "q", modifiers: [.command]).recordingRejection == .system)
    #expect(KeyCombo(key: "v", modifiers: [.command]).recordingRejection == .system)
    // Select-by-number fissi (⌘/⌥ 1..9): l'azione legata qui non scatterebbe mai.
    #expect(KeyCombo(key: "1", modifiers: [.command]).recordingRejection == .fixedSelect)
    #expect(KeyCombo(key: "9", modifiers: [.option]).recordingRejection == .fixedSelect)
}

@Test func recorderAcceptsValidCombos() {
    // Combo legittime (anche se con control o su cifre non-1..9 con modificatori diversi).
    #expect(KeyCombo(key: "t", modifiers: [.command]).recordingRejection == nil)
    #expect(KeyCombo(key: "c", modifiers: [.command, .shift]).recordingRejection == nil)
    #expect(KeyCombo(key: "1", modifiers: [.command, .shift]).recordingRejection == nil)
    #expect(KeyCombo(key: "0", modifiers: [.command]).recordingRejection == nil) // ⌘0 non è 1..9
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

@MainActor @Test func persistsOnlyRemappedBindings() throws {
    let defaults = try #require(UserDefaults(suiteName: "relay-test-\(UUID().uuidString)"))
    let settings = AppSettings(defaults: defaults)

    settings.setBinding(KeyCombo(key: "y", modifiers: [.command]), for: .newTab)

    // Solo l'azione rimappata finisce su disco: le altre restano al default (che una versione
    // futura può cambiare, ereditato via loadKeybindings).
    let data = try #require(defaults.data(forKey: "relay.shortcuts.bindings"))
    let saved = try JSONDecoder().decode([String: KeyCombo].self, from: data)
    #expect(saved == ["newTab": KeyCombo(key: "y", modifiers: [.command])])
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

@Test func defaultCombosAreUnique() {
    // Due azioni con la stessa combo di default: una non scatterebbe mai (il monitor prende la
    // prima che trova). Vale la pena scoprirlo qui e non usando l'app.
    var seen: [KeyCombo: ShortcutAction] = [:]
    for action in ShortcutAction.allCases {
        let combo = action.defaultCombo
        #expect(seen[combo] == nil, "\(action) collide con \(seen[combo]?.rawValue ?? "")")
        seen[combo] = action
    }
}

@Test func paneActionsDefaultToTheirCombos() {
    #expect(ShortcutAction.splitRight.defaultCombo == KeyCombo(key: "\\", modifiers: [.command]))
    #expect(
        ShortcutAction.splitDown.defaultCombo == KeyCombo(key: "\\", modifiers: [.command, .shift])
    )
    // `Cmd+W` chiude la tab e uccide la sessione: smontare un pane deve costare un tasto diverso.
    #expect(ShortcutAction.closePane.defaultCombo != ShortcutAction.closeTab.defaultCombo)
    #expect(ShortcutAction.splitRight.group == .pane)
}

@Test func everyActionBelongsToAGroupThatTheSettingsListRenders() {
    // `ShortcutsList` itera `ShortcutGroup.allCases` e filtra per gruppo: un'azione il cui gruppo
    // non è fra i casi non comparirebbe mai in Impostazioni > Shortcuts, senza che nulla fallisca.
    let groups = Set(ShortcutGroup.allCases)
    for action in ShortcutAction.allCases {
        #expect(groups.contains(action.group), "\(action.rawValue) ha un gruppo non renderizzato")
    }
    // E ogni gruppo dichiarato ha almeno un'azione: una sezione vuota nel pannello è un residuo.
    for group in ShortcutGroup.allCases {
        #expect(
            ShortcutAction.allCases.contains { $0.group == group },
            "il gruppo \(group.rawValue) non ha azioni"
        )
    }
}

@Test func everyActionHasANonEmptyLabel() {
    for action in ShortcutAction.allCases {
        #expect(!action.label.isEmpty)
    }
}
