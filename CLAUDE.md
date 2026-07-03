# Relay - guida per l'agent

Terminale macOS nativo agent-aware. Leggi `docs/ARCHITECTURE.md` prima di toccare la struttura
e `docs/CONVENTIONS.md` prima di scrivere codice. Cosa manca e in che ordine: `docs/ROADMAP.md`.

Stato: V0 + **M1 (agent runtime + badge)** + giro UI/UX (temi, chrome, chiusura con conferma +
cascade, float per stato) + **M2 (persistence layout + rename inline)** + **resume assistito Claude**
+ **M3 (cap LRU + misure performance chiuse, `docs/research/PERF.md`)** + **M4 (bundle `.app` +
notifiche macOS con impostazioni e suono + icona + installer locale `make dmg`/`install-app`)** + sei
temi curati e scelta font family. **Baseline delle milestone chiuso**, app installabile in locale;
prossimo giro a scelta (distribuzione firmata, dashboard, split) - vedi `docs/ROADMAP.md`. Pipeline
hook -> badge -> resume validata a mano con Claude reale; le notifiche girano solo dal bundle
(`make run-app`).

## Comandi

- `make build` / `make test` / `make run` / `make check` (definition of done prima di un commit
  grosso e sempre prima di proporre un push).
- Lint: `brew install swiftlint swiftformat` (installati in locale).
- **Simulatore agente**: `relay-cli simulate [coding|permission|burst] [--loops N] [--fast]`,
  da lanciare *dentro una tab di Relay*: recita una chat finta e manda eventi reali al socket
  (stesso client/wire degli hook). Per testare badge/aggregazioni senza sessioni Claude vere.
- **Demo mode**: `relay --demo [NxM]` (default 4x3): N workspace da M tab con sessioni simulate
  concorrenti su ogni tab, eventi via socket reale. Per vedere l'app "piena" e testare
  badge/contatori/aggregazioni a colpo d'occhio.

## Mappa moduli (dipendenze solo verso il basso)

- `Core` - primitivi condivisi (logging; `RelayTheme`/`RelayColor` = modello tema dato puro;
  `OSC7` = parsing cwd). Nessuna dipendenza. Il tema vive qui perché sia il terminale
  (`TerminalEngine`) sia la chrome (`Panels`) lo convertono nei rispettivi tipi.
- `AgentProtocol` - tipi evento/stato agente, puro. Niente I/O, niente AppKit.
- `AgentRuntime` - trasporto eventi agente: `AgentEventReceiver` (server Unix socket),
  `AgentEventClient` (client, usato dal CLI), `RelayRuntimePaths` (path socket + layout),
  `AgentSessionStore` (actor, snapshot per sessionId). Puro, niente AppKit né WorkspaceModel.
- `WorkspaceModel` - `WorkspaceStore`/`Workspace`/`Tab` (@Observable) + `AgentSeverity` +
  `AgentStateReducer` (incl. classificatore notifiche) + `AppSettings` (tema/font family/cursore/
  sidebar/notifiche, UserDefaults) + `WindowTitle` + `LayoutSnapshot` (Codable) +
  `AgentNotification` (payload puro, emesso da `store.onNotifiableTransition`). Puro, niente AppKit.
- `TerminalEngine` - astrazione `TerminalEngine`/`TerminalSurfaceHandle` + backend SwiftTerm.
  **Nessun tipo SwiftTerm deve trapelare fuori da qui** (espone solo `NSView`).
- `TerminalHostUI` - `SurfaceRegistry` (Tab.id -> surface, lazy, cap LRU via `SurfaceEvictionPolicy`
  pura) + `WorkspaceAreaController` (AppKit, osserva lo store, scambia il terminale attivo). Path caldo.
- `Panels` - SwiftUI isolata: `Theme` (spacing/typography), `ThemeColors` (colori dal tema corrente),
  `SidebarView`, `TabBarView`, `ContextTitleBar`, `SidebarToggleButton`, `AgentBadge`/`WorkspaceBadge`,
  `ResumeBar`, `SettingsView` (+ `SettingsComponents`), `MonospaceFonts`. I colori vengono dal tema
  (`AppSettings.theme`), non hardcoded.
- `HookInstaller` - `ClaudeHookInstaller`: setup/uninstall/status idempotenti su
  `~/.claude/settings.json`, marcati `RELAY_MANAGED_HOOK=1`, append (convivono con Otty), backup +
  scrittura atomica. Trasformazioni pure (`merge`/`remove`) separate dall'I/O per i test.
- `LayoutStore` - persistence del layout: `load()`/`save(snapshot)` di `LayoutSnapshot` su disco
  (JSON atomico, versionato, path iniettato). Dipende solo da `WorkspaceModel`, niente AppKit.
- `RelayApp` (`Sources/relay`) - composition root: `AppController`, `MainSplitViewController`,
  `RightPaneController`, `RootOverlayController` (overlay toggle), `MainMenuBuilder`,
  `AgentCoordinator` (unico punto che lega `AgentRuntime` a `WorkspaceModel`),
  `NotificationCoordinator` (unico punto che tocca `UNUserNotificationCenter`), `LayoutAutosave`,
  `PerfSampler` (misure `RELAY_PERF`), `DemoMode`/`DemoSeeder`. Se cresce oltre il wiring, manca un modulo.
- `CLI` (`Sources/relay-cli`) - eseguibile `relay-cli`: `hooks setup|uninstall|status`,
  `claude-hook <state>` (invocato dagli hook: stdin + `RELAY_TAB_ID` -> socket) e `simulate`.

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
- `make bundle` assembla `.build/Relay.app` (release + `bundle/Info.plist` + `AppIcon.icns` + firma
  ad-hoc, bundle id `dev.relay.app`); `make run-app` lo avvia, `make install-app` lo copia in
  `/Applications`, `make dmg` fa `.build/Relay.dmg` (installer **locale, non firmato**: si apre con
  click-destro > Apri; per distribuirlo a terzi serve Developer ID + notarizzazione). Serve per le
  notifiche: `UNUserNotificationCenter` richiede un bundle id, da bare executable (`swift run`)
  crasha; in sviluppo `make run` va bene (niente notifiche).
- Icona: `bundle/make-icon.swift` (Core Graphics puro, headless) la disegna; `make icon` rigenera
  `bundle/AppIcon.icns` (committato). Cambi al disegno -> `make icon` poi `make bundle`.
- Notifiche: il trigger è puro (`AgentStateReducer.notification`), lo store emette via
  `onNotifiableTransition` e il `NotificationCoordinator` (solo se `Bundle.main.bundleIdentifier !=
  nil`) filtra per preferenze e consegna. `isVisible = tab selezionata && NSApp.isActive`: se Relay è
  in background notifica anche sulla tab selezionata; al ritorno in primo piano
  (`applicationDidBecomeActive`) la tab in vista viene visitata. Il coordinatore è
  `UNUserNotificationCenterDelegate` e forza `willPresent -> [.banner,.sound,.list]`: **senza, i
  banner sono soppressi quando Relay è frontmost**. Al primo avvio dal bundle macOS chiede il
  permesso una volta; una firma ad-hoc che cambia a ogni reinstall può farlo decadere (log
  `auth status` al boot: 2 = authorized).
- Misure di performance: `RELAY_PERF=1` accende `PerfSampler` (RSS + surface vive + latenza input,
  categoria log `perf`, livello `.notice`); `RELAY_PERF_CYCLE=1` cicla il focus; `RELAY_SURFACE_CAP=N`
  override del cap LRU. Vedi `docs/research/PERF.md` per numeri e metodo. Spento a regime.
- `Tab` è ambiguo: SwiftUI ha un suo `Tab`. Nei file che importano SwiftUI + WorkspaceModel usa
  `WorkspaceModel.Tab`.
- Bridge Observation -> AppKit: `WorkspaceAreaController.observe()` usa `withObservationTracking`
  e si ri-arma; leggi le proprietà osservate dentro `render()` o non verranno tracciate.
- Shortcut numerici (Cmd/Option + 1..9): gestiti da un `NSEvent` local monitor in
  `AppController`, non da keyEquivalent di menu. Motivo: i menu con solo Option non matchano (il
  carattere è trasformato, es. Option+1 = "¡"). Le voci del menu "Go" sono solo cliccabili
  (`AppControllerNavigation`). **Cmd+N segue l'ordine visivo della sidebar** (`orderedWorkspaces`),
  non quello canonico: Cmd+1 apre sempre la riga in cima anche col float dei completati.
- Agent binding: `RELAY_TAB_ID` (= `Tab.id`) è iniettato nell'env della surface e torna dall'hook
  come `paneId`. Il socket è `~/.relay/relay.sock` (override `RELAY_SOCKET`); un socket stantio è
  gestito da `unlink` prima del `bind`, quindi non blocca il riavvio.
- **Mai lanciare `relay-cli hooks setup` a mano senza `RELAY_CLAUDE_SETTINGS`**: `NSHomeDirectory()`
  ignora `$HOME` su macOS e scriverebbe il vero `~/.claude`. Per test/manuale usa
  `RELAY_CLAUDE_SETTINGS=/tmp/....json`. I test unit passano già un `settingsPath` esplicito.
- `swift build --target X` può ricompilare un modulo senza rilinkare l'eseguibile: per testare un
  binario aggiornato usa `swift build` completo (o `make build`).
- Chrome full-size content view: le `NSHostingView` della chrome (title strip, sidebar, overlay)
  devono avere `safeAreaRegions = []`, altrimenti SwiftUI applica la safe area della title bar e
  spinge il contenuto sotto i semafori. Il layout verticale lo gestiamo noi.
- Toggle sidebar: è un overlay a livello finestra (`RootOverlayController`), **non** un
  `NSTitlebarAccessoryViewController` - quello non viene renderizzato con `titleVisibility = .hidden`
  su macOS 26. L'overlay insegue il bordo della sidebar via `splitViewDidResizeSubviews`.
- Sidebar: `NSSplitViewItem(viewController:)` normale, non `sidebarWithViewController:` (macOS 26 lo
  stila come pannello glass flottante). Lo `NSScroller` interno di SwiftTerm è nascosto a mano.
- Lista workspace: `ScrollView` + `LazyVStack` custom, **non** `List`. La `List` disegna un highlight
  full-size di sistema sotto la riga bersaglio del menu contestuale (fuori dal tema flat). Con la
  VStack gestiamo noi selezione/hover/menu; il riordino è drag & drop (`draggable`/`dropDestination`
  -> `WorkspaceStore.moveWorkspace(_:onto:)`), non `onMove`. La sidebar itera
  `store.orderedWorkspaces` (derivato: pinned, poi con attenzione, poi resto) - **display-only**, non
  toccare `store.workspaces` per ordinare: quello è l'ordine canonico (drag + futura persistence).
  Rename inline del workspace dal menu contestuale (`WorkspaceStore.renameWorkspace`).
- Chiusura tab/workspace: passa da `AppController.requestCloseTab/requestCloseWorkspace` (Cmd+W e le
  x dei pannelli), che chiedono conferma via `NSAlert` sheet se nel pty gira un comando in foreground
  (`TerminalSurfaceHandle.foregroundProcessName()` = `tcgetpgrp` vs `shellPid` + safe-list shell; solo
  foreground, i job in background non contano). Chiudere l'ultima tab chiude il workspace (cascade in
  `WorkspaceStore.closeTab`).
- Persistence layout: `~/.relay/layout.json` (override `RELAY_LAYOUT`; path **iniettato** in
  `LayoutStore`, i test usano una dir temporanea, mai `~/.relay`). Salvataggio via `LayoutAutosave`
  (debounced ~500ms + flush on `applicationWillTerminate`), che osserva `store.snapshot()`: dipende
  solo dai campi persistiti, quindi gli eventi agente non scatenano scritture. **Demo mode non
  persiste** (non istanzia l'autosave). Restore al boot ricade sul seed default se file
  mancante/corrotto/versione ignota. Bump `LayoutSnapshot.currentVersion` se cambia lo schema.
- Cap LRU surface: `SurfaceRegistry.enforceLRU(cap:keep:)` sfratta le meno recenti **solo se idle**
  (`hasRunningChildren == false`: shell senza figli, copre foreground/background/agente), mai la
  visibile. Eviction = teardown SwiftTerm (scrollback perso, shell ricreata alla cwd al re-focus).
  Cap in `WorkspaceAreaController` (12, da tarare). Se cambi il criterio di eviction, tienilo
  conservativo: meglio sforare il cap che uccidere un processo.
- Resume Claude: `ResumeBinding` (agent/sessionId/label) catturato in `applyAgentState` (viva) e
  azzerato su `unknown`, persistito nel `TabSnapshot`. Al primo focus di una tab `pendingResume`
  (binding + `agentState==unknown`) `RightPaneController` overlaya `ResumeBar` sul terminale;
  `Resume` -> `surface.sendText("claude --resume <id>\n")`. Setting `autoResumeAgents` (default off)
  inietta da solo. **Il wiring della barra vive nel composition root (RelayApp), non in
  TerminalHostUI**: il path caldo non dipende da Panels. Il resume è **lazy** (al focus), mai in
  massa al boot.
- Non ancora fatto: split, bundle `.app`, dashboard; misure performance (per il cap LRU).
