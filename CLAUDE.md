# Relay - guida per l'agent

Terminale macOS nativo agent-aware. Leggi `docs/ARCHITECTURE.md` prima di toccare la struttura
e `docs/CONVENTIONS.md` prima di scrivere codice. Cosa manca e in che ordine: `docs/ROADMAP.md`.

Stato: V0 + **Milestone 1 (agent runtime + badge) fatta**: receiver socket, hook installer + CLI,
stato agente su `Tab`, badge in tab bar e sidebar. **Prossimo: Milestone 2 (persistence + rename)** -
vedi `docs/ROADMAP.md`. Resta da verificare a mano il badge con una sessione Claude reale
(`relay-cli hooks setup`, apri l'app, avvia `claude`).

## Comandi

- `make build` / `make test` / `make run` / `make check` (definition of done prima di un commit
  grosso e sempre prima di proporre un push).
- Lint: serve `brew install swiftlint swiftformat` (non ancora installati in locale).

## Mappa moduli (dipendenze solo verso il basso)

- `Core` - primitivi condivisi (logging; `RelayTheme`/`RelayColor` = modello tema, dato puro).
  Nessuna dipendenza. Il tema vive qui perché sia il terminale (`TerminalEngine`) sia la chrome
  (`Panels`) lo convertono nei rispettivi tipi (SwiftTerm/NSColor, SwiftUI Color).
- `AgentProtocol` - tipi evento/stato agente, puro. Niente I/O, niente AppKit.
- `AgentRuntime` - trasporto eventi agente: `AgentEventReceiver` (server Unix socket),
  `AgentEventClient` (client, usato dal CLI), `RelayRuntimePaths` (path socket), `AgentSessionStore`
  (actor, snapshot per sessionId). Puro, niente AppKit né WorkspaceModel.
- `WorkspaceModel` - `WorkspaceStore`/`Workspace`/`Tab` (@Observable) + `AgentSeverity` +
  `AgentStateReducer` + `AppSettings` (tema/font, persistito in UserDefaults). Puro, niente AppKit.
  V0: una tab = un terminale (split futuro).
- `TerminalEngine` - astrazione `TerminalEngine`/`TerminalSurfaceHandle` + backend SwiftTerm.
  **Nessun tipo SwiftTerm deve trapelare fuori da qui** (espone solo `NSView`).
- `TerminalHostUI` - `SurfaceRegistry` (Tab.id -> surface, lazy) + `WorkspaceAreaController`
  (AppKit, osserva lo store, scambia il terminale attivo). Path caldo.
- `Panels` - SwiftUI isolata: `Theme` (spacing/typography), `ThemeColors` (colori derivati dal tema
  corrente), `SidebarView`, `TabBarView`, `AgentBadge`, `SettingsView`. I colori vengono dal tema
  (`AppSettings.theme`), non hardcoded.
- `HookInstaller` - `ClaudeHookInstaller`: setup/uninstall/status idempotenti su
  `~/.claude/settings.json`, marcati `RELAY_MANAGED_HOOK=1`, append (convivono con Otty), backup +
  scrittura atomica. Trasformazioni pure (`merge`/`remove`) separate dall'I/O per i test.
- `RelayApp` (`Sources/relay`) - composition root: `AppController`, `MainSplitViewController`,
  `RightPaneController`, menu/shortcut, e `AgentCoordinator` (unico punto che lega `AgentRuntime` a
  `WorkspaceModel`: receiver -> `store.applyAgentState`). Se cresce oltre il wiring, manca un modulo.
- `CLI` (`Sources/relay-cli`) - eseguibile `relay-cli`: `hooks setup|uninstall|status` e
  `claude-hook <state>` (invocato dagli hook: legge stdin + `RELAY_TAB_ID`, emette al socket).

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
- Agent binding: `RELAY_TAB_ID` (= `Tab.id`) è iniettato nell'env della surface e torna dall'hook
  come `paneId`. Il socket è `~/.relay/relay.sock` (override `RELAY_SOCKET`); un socket stantio è
  gestito da `unlink` prima del `bind`, quindi non blocca il riavvio.
- **Mai lanciare `relay-cli hooks setup` a mano senza `RELAY_CLAUDE_SETTINGS`**: `NSHomeDirectory()`
  ignora `$HOME` su macOS e scriverebbe il vero `~/.claude`. Per test/manuale usa
  `RELAY_CLAUDE_SETTINGS=/tmp/....json`. I test unit passano già un `settingsPath` esplicito.
- `swift build --target X` può ricompilare un modulo senza rilinkare l'eseguibile: per testare un
  binario aggiornato usa `swift build` completo (o `make build`).
- Non ancora fatto: cap LRU sulle surface vive, split, persistence/rename, bundle `.app`, dashboard.
