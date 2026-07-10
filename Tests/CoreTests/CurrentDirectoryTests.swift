@testable import Core
import Testing

// Precedenza delle fonti della cwd di una tab. L'ordine è il punto: si era già invertito una volta
// (l'ultimo OSC 7 noto davanti alla shell viva), rendendo `Cmd+T` cieco ai `cd` delle shell senza
// integrazione OSC 7 - cioè zsh di default in Relay.

@Test func liveShellWinsOverLastKnownDirectory() {
    let resolved = CurrentDirectory.resolve(
        live: "/Users/doppia/dev/relay/Sources",
        lastKnown: "/Users/doppia/dev/relay",
        workspaceRoot: "/Users/doppia/dev"
    )

    #expect(resolved == "/Users/doppia/dev/relay/Sources")
}

@Test func lastKnownDirectoryServesUnrealizedTabs() {
    // Nessuna shell viva (tab mai aperta o sfrattata dal cap LRU): vale l'ultimo OSC 7 noto.
    let resolved = CurrentDirectory.resolve(
        live: nil,
        lastKnown: "/Users/doppia/dev/relay",
        workspaceRoot: "/Users/doppia/dev"
    )

    #expect(resolved == "/Users/doppia/dev/relay")
}

@Test func workspaceRootIsTheLastResort() {
    let resolved = CurrentDirectory.resolve(
        live: nil,
        lastKnown: nil,
        workspaceRoot: "/Users/doppia/dev"
    )

    #expect(resolved == "/Users/doppia/dev")
}

@Test func noKnownDirectoryResolvesToNil() {
    #expect(CurrentDirectory.resolve(live: nil, lastKnown: nil, workspaceRoot: nil) == nil)
}
