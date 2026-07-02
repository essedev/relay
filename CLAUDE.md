# Relay - guida per l'agent

Terminale macOS nativo agent-aware. Leggi `docs/ARCHITECTURE.md` prima di toccare la struttura
e `docs/CONVENTIONS.md` prima di scrivere codice.

## Comandi

- `make build` / `make test` / `make run` / `make check` (definition of done prima di un commit
  grosso e sempre prima di proporre un push).
- Lint: serve `brew install swiftlint swiftformat` (non ancora installati in locale).

## Mappa moduli (dipendenze solo verso il basso)

- `Core` - primitivi (logging). Nessuna dipendenza.
- `AgentProtocol` - tipi evento/stato agente, puro. Niente I/O, niente AppKit.
- `AgentRuntime` - store/receiver stato agente (actor).
- `WorkspaceModel` - `WorkspaceStore`/`Workspace`/`Tab` (@Observable) + `AgentSeverity`. Puro,
  niente AppKit. V0: una tab = un terminale (split futuro).
- `TerminalEngine` - astrazione `TerminalEngine`/`TerminalSurfaceHandle` + backend SwiftTerm.
  **Nessun tipo SwiftTerm deve trapelare fuori da qui** (espone solo `NSView`).
- `TerminalHostUI` - `SurfaceRegistry` (Tab.id -> surface, lazy) + `WorkspaceAreaController`
  (AppKit, osserva lo store, scambia il terminale attivo). Path caldo.
- `Panels` - SwiftUI isolata: `Theme` (design tokens), `SidebarView`, `TabBarView`.
- `HookInstaller` - hook Claude in ~/.claude/settings.json.
- `RelayApp` (`Sources/relay`) - composition root: `AppController`, `MainSplitViewController`,
  `RightPaneController`, menu/shortcut. Se cresce oltre il wiring, manca un modulo.
- `CLI` (`Sources/relay-cli`) - eseguibile `relay`.

## Regole che non si violano

- AppKit sul path caldo (terminale, input); SwiftUI solo nei pannelli isolati.
- Lazy + budget: niente priming, niente risorse pesanti prima del bisogno (vedi principi in
  ARCHITECTURE). Cap scrollback.
- Mai `print` per logging (usa `RelayLog`); nel CLI il print è output utente, ok.
- Mai committare `.env*`, segreti, file di auth. Mai hardcodare valori estetici nei pannelli:
  usa il design system (principio UI 6 in ARCHITECTURE).
- Swift 6 strict concurrency: store osservati `@MainActor`, runtime come actor.

## Gotcha noti

- libghostty non è ancora embeddabile stabile: engine v1 = SwiftTerm. Non reintrodurre zig o
  binari di fork senza una decisione esplicita (vedi ARCHITECTURE, sezione engine).
- L'app è un eseguibile SwiftPM per ora; il bundling `.app` (Info.plist, entitlements, firma per
  notifiche) arriva quando serve.
- `Tab` è ambiguo: SwiftUI ha un suo `Tab`. Nei file che importano SwiftUI + WorkspaceModel usa
  `WorkspaceModel.Tab`.
- Bridge Observation -> AppKit: `WorkspaceAreaController.observe()` usa `withObservationTracking`
  e si ri-arma; leggi le proprietà osservate dentro `render()` o non verranno tracciate.
- Shortcut numerici (Cmd/Option + 1..9): gestiti da un `NSEvent` local monitor in
  `AppController`, non da keyEquivalent di menu. Motivo: i menu con solo Option non matchano (il
  carattere è trasformato, es. Option+1 = "¡"). Le voci del menu "Go" sono solo cliccabili.
- Non ancora fatto: cap LRU sulle surface vive, split, agent runtime/badge, persistence.
