@testable import Core
import Testing

// Nomi derivati **senza modello**: è la nomina di default (l'LLM entra solo se c'è una API key),
// quindi la qualità di queste stringhe è la qualità della feature per la maggior parte degli
// utenti.

private let home = "/Users/dev"

private func names(directory: String? = nil, command: String? = nil) -> [String] {
    WorkspaceNaming.localNames(
        for: WorkspaceNameSignals(directory: directory, command: command), homePath: home
    )
}

@Test func localNameTitleCasesTheFolder() {
    #expect(names(directory: "/Users/dev/Development/Projects/relay").first == "Relay")
    #expect(names(directory: "/Users/dev/Development/Yellow/yellow-hub").first == "Yellow Hub")
    #expect(names(directory: "/Users/dev/src/acme_web").first == "Acme Web")
}

@Test func localNameSplitsCamelCase() {
    #expect(names(directory: "/Users/dev/src/yellowHub").first == "Yellow Hub")
}

/// Stessa regola che il prompt chiede al modello: i suffissi di versione non fanno parte del nome.
@Test func localNameDropsVersionSuffixes() {
    #expect(names(directory: "/Users/dev/src/yellow-hub-v2").first == "Yellow Hub")
    #expect(names(directory: "/Users/dev/src/relay-2").first == "Relay")
}

/// Una parola che ha già maiuscole sue sa come si scrive: non si passa da `capitalized`.
@Test func localNameKeepsExistingCapitalization() {
    #expect(names(directory: "/Users/dev/src/API-gateway").first == "API Gateway")
}

@Test func localNameStopsAtThreeWords() {
    #expect(names(directory: "/Users/dev/src/one-two-three-four").first == "One Two Three")
}

@Test func localNameFromCommandDropsFlagsAndShellSubcommands() {
    #expect(names(command: "brew update").first == "Brew Update")
    #expect(names(command: "npm run dev").first == "Npm Dev")
    #expect(names(command: "cargo build --release").first == "Cargo Build")
    #expect(names(command: "uv run pytest").first == "Uv Pytest")
    #expect(names(command: "vim README.md").first == "Vim README")
}

/// La cartella identifica il progetto e non cambia sotto i piedi, il comando passa: primo l'uno,
/// poi l'altro. Il secondo candidato è quel che rende possibile un "Regenerate name" senza modello.
@Test func localNamesRankTheFolderFirstThenTheCommand() {
    #expect(names(directory: "/Users/dev/src/acme-web", command: "npm run dev")
        == ["Acme Web", "Npm Dev"])
}

/// La home non identifica niente: resta solo il comando (stessa regola di `prompt`).
@Test func localNamesIgnoreTheHomeDirectory() {
    #expect(names(directory: home, command: "brew update") == ["Brew Update"])
    #expect(names(directory: home).isEmpty)
}

@Test func localNamesAreEmptyWithoutSignals() {
    #expect(names().isEmpty)
}

/// Stessa porta d'uscita della risposta del modello: i generici non passano da nessuna delle due
/// strade.
@Test func localNamesRejectGenericFolders() {
    #expect(names(directory: "/Users/dev/src/project").isEmpty)
}

@Test func localNamesDoNotRepeatTheSameNameTwice() {
    #expect(names(directory: "/Users/dev/src/relay", command: "relay") == ["Relay"])
}
