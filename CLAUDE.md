# Relay - guida per l'agent

Terminale macOS nativo agent-aware. Leggi `docs/ARCHITECTURE.md` prima di toccare la struttura
e `docs/CONVENTIONS.md` prima di scrivere codice. Cosa manca e in che ordine: `docs/ROADMAP.md`;
la storia delle decisioni sta in `docs/research/CYCLES.md`.

Stato: baseline delle milestone chiuso (agent runtime + badge, persistence del layout, cap LRU,
bundle `.app` con notifiche, split panes e multi-window), app installabile da brew. Il prossimo
giro è a scelta fra distribuzione firmata e multi-agente, vedi `docs/ROADMAP.md`. La pipeline
hook -> badge -> resume è validata a mano con Claude reale; notifiche e check aggiornamenti
girano **solo dal bundle** (`make run-app`), non da `swift run`.

**Questo file resta corto**: è caricato in contesto a ogni sessione. I dettagli di una feature
vivono in `docs/features/*.md` (indice sotto), la storia in `docs/research/CYCLES.md`. Se stai
per aggiungere qui più di tre righe su una feature, il posto giusto è il suo file.

## Comandi

- `make build` / `make test` / `make run` / `make check` (definition of done prima di un commit
  grosso e sempre prima di proporre un push).
- Lint: `make tools` scarica le versioni **pinnate** di SwiftFormat/SwiftLint in `.build/tools`
  (binari dai release GitHub, versioni nel Makefile). `make lint`/`format`/`check` le usano; CI
  e locale girano la stessa versione, così un upgrade upstream non rompe il lint su codice
  invariato. Non usare la `brew install` (prende sempre l'ultima) per il giro di qualità.
- **Release**: `make release`. Versione = `./VERSION` (semver). Bumpa VERSION, `make check`,
  commit, poi `make release`: **è pubblicazione** (push tag + GitHub Release + tap brew), chiedi
  il via prima di lanciarla. Routine e firma in `docs/features/distribution.md`.
- **Simulatore agente**: `relay-cli simulate [coding|permission|burst] [--loops N] [--fast]`,
  da lanciare *dentro una tab di Relay*: recita una chat finta e manda eventi reali al socket
  (stesso client/wire degli hook). Per testare badge/aggregazioni senza sessioni Claude vere.
- **Demo mode**: `relay --demo [NxM]` (default 4x3): N workspace da M tab con sessioni simulate
  concorrenti su ogni tab, eventi via socket reale. Per vedere l'app "piena" e testare
  badge/contatori/aggregazioni a colpo d'occhio.

## Mappa moduli (dipendenze solo verso il basso)

- `Core` - primitivi puri, nessuna dipendenza: logging (`RelayLog`), modello tema
  (`RelayTheme`/`RelayColor`, qui perché lo convertono sia il terminale sia la chrome), `OSC7`,
  `ShellEscape`, `CurrentDirectory`, `KeyboardTextInput`, `TerminalSearchMatcher`,
  `SemanticVersion`/`ReleaseCheck`, `WorkspaceNaming`/`NamingTriggerPolicy`, `LatencyStats`.
- `AgentProtocol` - tipi evento/stato agente. Niente I/O, niente AppKit.
- `AgentRuntime` - trasporto eventi: `AgentEventReceiver` (server Unix socket), `AgentEventClient`
  (usato dal CLI), `RelayRuntimePaths`, `AgentWireCoding`. Niente AppKit né WorkspaceModel.
- `WorkspaceModel` - lo stato: `WorkspaceStore`/`Workspace`/`Tab`/`RelayWindow` (@Observable),
  `SplitNode`/`SplitPane` (albero di split, foglie = pane con le loro tab), `WorkspaceGroup`,
  `AttentionLevel`, `AgentStateReducer`, `AppSettings` (UserDefaults), `LayoutSnapshot`,
  `ShortcutAction`/`KeyCombo`, `NameOrigin`. Le operazioni stanno nelle extension per area
  (`+Split`, `+Windows`, `+Persistence`, `+Groups`, `+Navigation`, `+Ordering`). Puro, niente
  AppKit.
- `TerminalEngine` - astrazione `TerminalEngine`/`TerminalSurfaceHandle` + backend SwiftTerm e
  `RelayTerminalView`. **Nessun tipo SwiftTerm deve trapelare fuori da qui** (espone solo
  `NSView`). Ospita `NSColor(relay:)`: è il modulo AppKit più basso che TerminalHostUI e il
  composition root importano entrambi, così la conversione non è triplicata.
- `TerminalHostUI` - path caldo: `SurfaceRegistry` (Tab.id -> surface, lazy, cap LRU; **una sola
  per l'app**, condivisa dalle finestre), `WorkspaceAreaController` (osserva lo store e riconcilia
  l'albero di pane in `NSSplitView` annidate, vedi `+PaneTree`), `PaneView`, `AttentionRingView`.
- `Panels` - SwiftUI isolata: design system (`Theme`/`ThemeColors`, i valori estetici vengono da
  qui), `SidebarView` e i suoi pezzi (`SidebarLayout`/`SidebarDrop`/`SidebarReorder`, `GroupRow`),
  `PaneTabBar`, `ContextTitleBar`, badge, `ResumeBar`, `FindBar`, `Dashboard`, `SettingsView`,
  `AboutView`, `Onboarding`, `RuntimeStatsView`, primitive condivise
  (`StatusDot`/`CommandChip`/`CloseButton`), `KeyEventBridge`.
- `HookInstaller` - `ClaudeHookInstaller`: setup/uninstall/status idempotenti su
  `~/.claude/settings.json`, marcati `RELAY_MANAGED_HOOK=1`, append (convivono con Otty), backup +
  scrittura atomica. Trasformazioni pure (`merge`/`remove`) separate dall'I/O per i test.
- `LayoutStore` - `load()`/`save(snapshot)` del `LayoutSnapshot` su disco (JSON atomico,
  versionato, path iniettato). Niente AppKit.
- `RelayApp` (`Sources/relay`) - composition root e **unico posto che tocca il mondo esterno**:
  `AppController` (+ le sue extension per area), `RelayWindowController`, `MainSplitViewController`,
  `RightPaneController`, `RootOverlayController`/`FullOverlayPresenter`, `MainMenuBuilder`,
  `AgentCoordinator` (lega `AgentRuntime` a `WorkspaceModel`), `NotificationCoordinator`
  (`UNUserNotificationCenter`), `UpdateController` (rete/clipboard degli aggiornamenti),
  `NamingController` + `ChatCompletionClient` + `NamingCredentialStore` (rete e segreto della
  nomina), `LayoutAutosave`, `ShortcutRuntime`, `PerfSampler`/`RuntimeStatsSampler`,
  `DemoMode`/`DemoSeeder`. Se cresce oltre il wiring, manca un modulo.
- `CLI` (`Sources/relay-cli`) - eseguibile `relay-cli`: `hooks setup|uninstall|status`,
  `claude-hook <state>` (invocato dagli hook: stdin + `RELAY_TAB_ID` -> socket) e `simulate`.

## Regole che non si violano

- AppKit sul path caldo (terminale, input); SwiftUI solo nei pannelli isolati.
- Lazy + budget: niente priming, niente risorse pesanti prima del bisogno (vedi principi in
  ARCHITECTURE). Cap scrollback.
- Mai `print` per logging (usa `RelayLog`); nel CLI il print è output utente, ok.
- Mai committare `.env*`, segreti, file di auth. Mai hardcodare valori estetici nei pannelli:
  usa il design system (principio UI 6 in ARCHITECTURE).
- Swift 6 strict concurrency, come è fatto davvero: la UI e il path caldo sono `@MainActor`
  (`SurfaceRegistry`, `WorkspaceAreaController`, `AppSettings`, le view); `WorkspaceStore` è
  `@Observable` **non isolato**, mutato solo dal main thread per convenzione (isolarlo è una
  decisione aperta, non darlo per fatto). Il runtime **non** è un actor: `AgentEventReceiver` è una
  classe `@unchecked Sendable` con tutto lo stato del socket su una `DispatchQueue` seriale, e
  l'ordine di consegna lo ristabiliscono il pump FIFO del coordinatore e la guardia di
  monotonicità. Non introdurre `actor` nuovi senza una decisione esplicita: il confine oggi è
  "main thread + queue seriale".

## Dettagli per area (leggi il file prima di toccare l'area)

Ogni file raccoglie invarianti e trappole già pagate: violarle rompe cose che i test non coprono.

- `docs/features/attention.md` - attenzione a tre livelli (unseen -> pending -> risolto), quando
  nasce, cosa la declassa e cosa la spegne; notifiche macOS; ring; dashboard di triage (`Cmd+D`).
  **Invariante**: posizione in sidebar e segnale di attenzione sono scollegati.
- `docs/features/agent-runtime.md` - binding `RELAY_TAB_ID`/`RELAY_RUN_ID`, socket e self-heal,
  ordine degli eventi (pump FIFO + monotonicità + `eventFloor` + fence di run), mapping hook ->
  stato, resume di Claude. **Invariante**: un evento fuori run o anteriore al boot si scarta.
- `docs/features/terminal.md` - integrazioni e limiti di SwiftTerm: kitty keyboard, cwd senza
  OSC 7, selezione durante lo streaming, scroll fluido, ricerca `Cmd+F`, cap LRU delle surface.
- `docs/features/sidebar.md` - lista dei workspace, dove nasce una cosa nuova, archivio, drag &
  drop (righe e slot), chiusura con conferma, "Move to New Workspace".
- `docs/features/workspace-groups.md` - card di gruppo: l'appartenenza vive sul workspace, il
  gruppo porta solo l'aspetto; un gruppo senza membri non esiste.
- `docs/features/split-panes.md` - modello cmux v2: i pane ospitano le tab, "visibile" vs
  "focused", reconcile dell'albero e ratio dei divider.
- `docs/features/windows.md` - chrome full-size, `makePanelWindow` per le finestre di servizio,
  overlay full-window, ciclo di vita di una `NSWindow`, multi-window.
- `docs/features/keyboard.md` - il local monitor come unico trigger delle azioni rimappabili,
  shortcut numerici, testo composto con `Option`.
- `docs/features/workspace-naming.md` - nomina automatica via LLM: trigger, contesto, single-flight,
  `NameOrigin`, API key su file 0600.
- `docs/features/distribution.md` - `make bundle`/`dmg`, tap brew e routine di release, firma,
  icona, check aggiornamenti, CI deterministica.
- `docs/features/persistence.md` - `~/.relay/layout.json`, autosave, guardia anti-degrado,
  single-instance.

## Gotcha trasversali

- libghostty non è ancora embeddabile stabile: engine v1 = SwiftTerm. Non reintrodurre zig o
  binari di fork senza una decisione esplicita (vedi ARCHITECTURE, sezione engine).
- Misure di performance: `RELAY_PERF=1` accende `PerfSampler` (RSS + surface vive + latenza input,
  categoria log `perf`, livello `.notice`); `RELAY_PERF_CYCLE=1` cicla il focus; `RELAY_SURFACE_CAP=N`
  override del cap LRU. Vedi `docs/research/PERF.md` per numeri e metodo. Spento a regime.
- Runtime Stats: voce `View > Runtime Stats…`, pannello read-only con RSS, CPU del processo,
  workspace/tab e surface vive/cap. `RuntimeStatsSampler` campiona solo finché il pannello è aperto
  (~2s), poi invalida il timer in `windowWillClose`: non trasformarlo in polling permanente. Resta
  separato da `PerfSampler`, che è dev tooling (`RELAY_PERF`) e misura anche la latenza input.
- `Tab` è ambiguo: SwiftUI ha un suo `Tab`. Nei file che importano SwiftUI + WorkspaceModel usa
  `WorkspaceModel.Tab`.
- Bridge Observation -> AppKit: `WorkspaceAreaController.observe()` usa `withObservationTracking`
  e si ri-arma; leggi le proprietà osservate dentro `render()` o non verranno tracciate.
- **Mai lanciare `relay-cli hooks setup` a mano senza `RELAY_CLAUDE_SETTINGS`**: `NSHomeDirectory()`
  ignora `$HOME` su macOS e scriverebbe il vero `~/.claude`. Per test/manuale usa
  `RELAY_CLAUDE_SETTINGS=/tmp/....json`. I test unit passano già un `settingsPath` esplicito.
- `swift build --target X` può ricompilare un modulo senza rilinkare l'eseguibile: per testare un
  binario aggiornato usa `swift build` completo (o `make build`).
