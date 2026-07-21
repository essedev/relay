@testable import Core
import Testing

private let home = "/Users/dev"

// MARK: - command(fromArgv:)

@Test func commandFromArgvTakesBasenameAndArgs() {
    #expect(WorkspaceNaming
        .command(fromArgv: ["/opt/homebrew/bin/brew", "update"]) == "brew update")
}

@Test func commandFromArgvNilWhenBareShell() {
    #expect(WorkspaceNaming.command(fromArgv: ["/bin/zsh"]) == nil)
    #expect(WorkspaceNaming.command(fromArgv: ["-zsh"]) == nil)
}

@Test func commandFromArgvKeepsShellWithScript() {
    // Una shell con uno script è un comando reale, non il prompt interattivo.
    #expect(WorkspaceNaming.command(fromArgv: ["/bin/bash", "deploy.sh"]) == "bash deploy.sh")
}

@Test func commandFromArgvNilWhenEmpty() {
    #expect(WorkspaceNaming.command(fromArgv: nil) == nil)
    #expect(WorkspaceNaming.command(fromArgv: []) == nil)
}

@Test func commandFromArgvCapsLength() throws {
    let long = ["python", String(repeating: "x", count: 200)]
    let result = WorkspaceNaming.command(fromArgv: long)
    #expect(result != nil)
    #expect(try #require(result?.count) <= 80)
}

// MARK: - signals(from:workspaceRoot:)

@Test func signalsPreferTheTabWithAnActiveAgent() {
    let tabs = [
        TabNamingSignal(isVisible: true, directory: "/Users/dev"),
        TabNamingSignal(agent: "claude", directory: "/Users/dev/relay"),
    ]
    let result = WorkspaceNaming.signals(from: tabs)
    #expect(result.agent == "claude")
    // I segnali vengono tutti dalla stessa tab: la cwd è quella dell'agente, non della visibile.
    #expect(result.directory == "/Users/dev/relay")
}

@Test func signalsPreferACommandOverABareDirectory() {
    let tabs = [
        TabNamingSignal(isVisible: true, directory: "/Users/dev"),
        TabNamingSignal(command: "brew update", directory: "/Users/dev/tools"),
    ]
    let result = WorkspaceNaming.signals(from: tabs)
    #expect(result.command == "brew update")
    #expect(result.directory == "/Users/dev/tools")
}

@Test func signalsPreferTheVisibleTabAtEqualStrength() {
    let tabs = [
        TabNamingSignal(command: "vim", directory: "/Users/dev/a"),
        TabNamingSignal(isVisible: true, command: "vim", directory: "/Users/dev/b"),
    ]
    #expect(WorkspaceNaming.signals(from: tabs).directory == "/Users/dev/b")
}

@Test func signalsAreStableWhenNothingDistinguishesTheTabs() {
    let tabs = [
        TabNamingSignal(directory: "/Users/dev/first"),
        TabNamingSignal(directory: "/Users/dev/second"),
    ]
    #expect(WorkspaceNaming.signals(from: tabs).directory == "/Users/dev/first")
}

@Test func signalsFallBackToTheWorkspaceRootWithoutLiveTabs() {
    // Nessuna surface realizzata (restore dal layout, sfratto LRU): resta la cartella nota.
    let tabs = [TabNamingSignal(isVisible: true)]
    let result = WorkspaceNaming.signals(from: tabs, workspaceRoot: "/Users/dev/relay")
    #expect(result.directory == "/Users/dev/relay")
    #expect(result.command == nil)
}

@Test func signalsFallBackToTheWorkspaceRootWithoutTabs() {
    #expect(WorkspaceNaming.signals(from: [], workspaceRoot: "/Users/dev/relay")
        .directory == "/Users/dev/relay")
}

@Test func signalsAreEmptyWithoutAnySource() {
    #expect(WorkspaceNaming.signals(from: [TabNamingSignal()]) == WorkspaceNameSignals())
}

// MARK: - prompt(for:)

@Test func promptNilWhenNoSignal() {
    #expect(WorkspaceNaming.prompt(for: WorkspaceNameSignals(), homePath: home) == nil)
}

@Test func promptNilWhenOnlyHomeDirectory() {
    let signals = WorkspaceNameSignals(directory: home)
    #expect(WorkspaceNaming.prompt(for: signals, homePath: home) == nil)
}

@Test func promptNilWhenHomeWithTrailingSlash() {
    let signals = WorkspaceNameSignals(directory: home + "/")
    #expect(WorkspaceNaming.prompt(for: signals, homePath: home) == nil)
}

@Test func promptBuiltFromDirectory() throws {
    let signals = WorkspaceNameSignals(directory: "/Users/dev/Development/Yellow/yellow-hub-v2")
    let result = WorkspaceNaming.prompt(for: signals, homePath: home)
    #expect(result != nil)
    #expect(try #require(result?.user.contains("Directory: yellow-hub-v2")))
    #expect(try !#require(result?.user.contains("Command:")))
}

@Test func promptBuiltFromCommandEvenInHome() throws {
    let signals = WorkspaceNameSignals(directory: home, command: "brew update")
    let result = WorkspaceNaming.prompt(for: signals, homePath: home)
    #expect(result != nil)
    #expect(try #require(result?.user.contains("Command: brew update")))
    // La home non contribuisce la directory.
    #expect(try !#require(result?.user.contains("Directory:")))
}

@Test func promptIncludesAgentWhenPresent() throws {
    let signals = WorkspaceNameSignals(directory: "/Users/dev/relay", agent: "claude")
    let result = WorkspaceNaming.prompt(for: signals, homePath: home)
    #expect(try #require(result?.user.contains("Agent: claude")))
}

@Test func promptAsksForADifferentNameWhenAvoiding() throws {
    // Rigenerazione manuale: senza il vincolo, `temperature: 0` ridarebbe lo stesso nome.
    let signals = WorkspaceNameSignals(directory: "/Users/dev/relay")
    let result = WorkspaceNaming.prompt(for: signals, homePath: home, avoiding: "Relay")
    #expect(try #require(result?.user.contains("Already named \"Relay\"")))
}

@Test func promptIgnoresAnEmptyAvoidedName() throws {
    let signals = WorkspaceNameSignals(directory: "/Users/dev/relay")
    let result = WorkspaceNaming.prompt(for: signals, homePath: home, avoiding: "   ")
    #expect(try !#require(result?.user.contains("Already named")))
}

@Test func promptStaysNilWhenOnlyAvoidingIsKnown() {
    // "Dammene un altro" non è contesto: senza segnali non c'è niente da nominare.
    let result = WorkspaceNaming.prompt(
        for: WorkspaceNameSignals(), homePath: home, avoiding: "Relay"
    )
    #expect(result == nil)
}

// MARK: - sanitize

@Test func sanitizeTrimsQuotesAndWhitespace() {
    #expect(WorkspaceNaming.sanitize("  \"Yellow Hub\"  ") == "Yellow Hub")
}

@Test func sanitizeTakesFirstLine() {
    #expect(WorkspaceNaming.sanitize("Brew Update\nThis names the workspace.") == "Brew Update")
}

@Test func sanitizeStripsMarkdown() {
    #expect(WorkspaceNaming.sanitize("**Relay**") == "Relay")
    #expect(WorkspaceNaming.sanitize("`Yellow Hub`") == "Yellow Hub")
}

@Test func sanitizeCollapsesInnerWhitespace() {
    #expect(WorkspaceNaming.sanitize("Yellow    Hub") == "Yellow Hub")
}

@Test func sanitizeRejectsGeneric() {
    #expect(WorkspaceNaming.sanitize("Workspace") == nil)
    #expect(WorkspaceNaming.sanitize("untitled") == nil)
    #expect(WorkspaceNaming.sanitize("  Terminal  ") == nil)
}

@Test func sanitizeRejectsEmpty() {
    #expect(WorkspaceNaming.sanitize("") == nil)
    #expect(WorkspaceNaming.sanitize("\"\"") == nil)
    #expect(WorkspaceNaming.sanitize("   ") == nil)
}

@Test func sanitizeCapsLengthAtWordBoundary() throws {
    let raw = "Yellow Hub Backend Integration Service Layer"
    let result = WorkspaceNaming.sanitize(raw)
    #expect(result != nil)
    #expect(try #require(result?.count) <= WorkspaceNaming.maxNameLength)
    // Non taglia a metà parola: l'ultimo carattere non è dentro una parola spezzata.
    #expect(try !#require(result?.hasSuffix(" ")))
}
