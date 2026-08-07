import Foundation
@testable import WorkspaceModel

/// Fixture condivisa dei test di `applyAgentState`: uno store con due workspace, il primo (A)
/// selezionato quindi "visibile", il secondo (B) nascosto. Usata da `AgentApplyTests` e
/// `AgentEventGuardTests` (split per il budget di dimensione file, stessa base).
struct AgentFixture {
    let store: WorkspaceStore
    let visibleTab: Tab
    let hiddenTab: Tab
}

@MainActor
func makeAgentFixture() -> AgentFixture {
    let store = WorkspaceStore()
    let visible = store.createWorkspace(name: "A")
    let hidden = store.createWorkspace(name: "B")
    // L'ultima creata resta selezionata: rendo esplicito che "A" è la visibile.
    store.selectWorkspace(visible.id)
    return AgentFixture(store: store, visibleTab: visible.tabs[0], hiddenTab: hidden.tabs[0])
}

/// `UserDefaults` usa e getta per un test, **rimosso alla fine**.
///
/// `UserDefaults(suiteName:)` non è una struttura in memoria: crea un plist vero in
/// `~/Library/Preferences`, che resta lì per sempre se nessuno lo cancella. Con un nome casuale
/// per test, ogni `swift test` ne lasciava dietro una manciata: se ne erano accumulati 3254.
///
/// La closure è l'unico modo per avere un punto di pulizia: il `defer` scatta anche se il test
/// fallisce a metà.
///
/// Servono tutt'e tre i passi. `removePersistentDomain` cancella i **valori** ma lascia un plist
/// vuoto (42 byte) che cfprefsd riscrive; `removeSuite` scollega la suite dal processo, così il
/// daemon non la rigenera; solo allora il file si può togliere. Che sparisca davvero lo verifica
/// `testDefaultsLeaveNoFileBehind`: se una versione di macOS cambia il path, quel test fallisce
/// invece di lasciar tornare la discarica in silenzio.
func withTestDefaults<T>(_ body: (UserDefaults) throws -> T) rethrows -> T {
    try withNamedTestDefaults { defaults, _ in try body(defaults) }
}

/// Come `withTestDefaults`, ma espone anche il nome della suite: serve al test di igiene, che deve
/// guardare il file su disco. Ai test normali il nome non interessa.
func withNamedTestDefaults<T>(_ body: (UserDefaults, String) throws -> T) rethrows -> T {
    let name = "relay-test-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
        // Non può fallire con un nome valido; se succede, meglio fermarsi che sporcare le
        // preferenze vere scrivendo su `.standard`.
        fatalError("UserDefaults(suiteName:) non disponibile")
    }
    defaults.removePersistentDomain(forName: name)
    defer {
        defaults.removePersistentDomain(forName: name)
        UserDefaults.standard.removeSuite(named: name)
        try? FileManager.default.removeItem(at: testDefaultsFile(name))
    }
    return try body(defaults, name)
}

/// Il plist di una suite non sandboxed: `~/Library/Preferences/<suite>.plist`.
func testDefaultsFile(_ suiteName: String) -> URL {
    URL(fileURLWithPath: NSHomeDirectory())
        .appending(path: "Library/Preferences/\(suiteName).plist")
}
