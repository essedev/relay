# Relay - guida per l'agent

Terminale macOS nativo agent-aware. Leggi `docs/ARCHITECTURE.md` prima di toccare la struttura
e `docs/CONVENTIONS.md` prima di scrivere codice. Cosa manca e in che ordine: `docs/ROADMAP.md`.

Stato: V0 + **M1 (agent runtime + badge)** + giro UI/UX (temi, chrome, chiusura con conferma +
cascade, float per stato) + **M2 (persistence layout + rename inline)** + **resume assistito Claude**
+ **M3 (cap LRU + misure performance chiuse, `docs/research/PERF.md`)** + **M4 (bundle `.app` +
notifiche macOS con impostazioni e suono + icona + installer locale `make dmg`/`install-app`)** +
dodici temi curati e scelta font family + **giro terminale (find `Cmd+F`, clear `Cmd+K`,
jump-to-attention `Cmd+J`), drag finestra solo dalla title strip, ring di attenzione attorno al
terminale + mark-read su interazione (modello ispirato a cmux), scorciatoie rimappabili (recorder
in impostazioni)** + **dashboard di triage (`Cmd+D`) e attenzione a tre livelli (unseen -> pending
-> risolto, con dismiss e decadenza opzionale)**.
**Baseline delle milestone chiuso**, app
installabile in locale; prossimo giro a scelta (distribuzione firmata, split, multi-agente) - vedi
`docs/ROADMAP.md`. Pipeline hook -> badge -> resume validata a mano con Claude reale; le notifiche
girano solo dal bundle (`make run-app`).

## Comandi

- `make build` / `make test` / `make run` / `make check` (definition of done prima di un commit
  grosso e sempre prima di proporre un push).
- Lint: `brew install swiftlint swiftformat` (installati in locale).
- **Release**: `make release` (routine sotto). Versione = `./VERSION` (semver). Bumpa VERSION,
  `make check`, commit, poi `make release`: **è pubblicazione** (push tag + GitHub Release + tap
  brew), chiedi il via prima di lanciarla.
- **Simulatore agente**: `relay-cli simulate [coding|permission|burst] [--loops N] [--fast]`,
  da lanciare *dentro una tab di Relay*: recita una chat finta e manda eventi reali al socket
  (stesso client/wire degli hook). Per testare badge/aggregazioni senza sessioni Claude vere.
- **Demo mode**: `relay --demo [NxM]` (default 4x3): N workspace da M tab con sessioni simulate
  concorrenti su ogni tab, eventi via socket reale. Per vedere l'app "piena" e testare
  badge/contatori/aggregazioni a colpo d'occhio.

## Mappa moduli (dipendenze solo verso il basso)

- `Core` - primitivi condivisi (logging; `RelayTheme`/`RelayColor` = modello tema dato puro;
  `OSC7` = parsing cwd; `LatencyStats` = statistiche misure; `ShellEscape` = escaping path per il
  drop di file). Nessuna dipendenza. Il tema vive qui perché sia il terminale (`TerminalEngine`) sia
  la chrome (`Panels`) lo convertono nei rispettivi tipi.
- `AgentProtocol` - tipi evento/stato agente, puro. Niente I/O, niente AppKit.
- `AgentRuntime` - trasporto eventi agente: `AgentEventReceiver` (server Unix socket),
  `AgentEventClient` (client, usato dal CLI), `RelayRuntimePaths` (path socket + layout),
  `AgentSessionStore` (actor, snapshot per sessionId). Puro, niente AppKit né WorkspaceModel.
- `WorkspaceModel` - `WorkspaceStore`/`Workspace`/`Tab` (@Observable) + `AgentSeverity` +
  `AttentionLevel` (marker post-completamento a tre livelli: unseen/pending, vedi gotcha) +
  `AgentStateReducer` (incl. classificatore notifiche) + `AppSettings` (tema/font family/cursore/
  sidebar/notifiche/**keybindings**/decadenza sospesi, UserDefaults) + `WindowTitle` +
  `LayoutSnapshot` (Codable) + `AgentNotification` + `ShortcutAction`/`KeyCombo` (azioni
  rimappabili + combinazione pura). Puro, niente AppKit.
- `TerminalEngine` - astrazione `TerminalEngine`/`TerminalSurfaceHandle` + backend SwiftTerm.
  **Nessun tipo SwiftTerm deve trapelare fuori da qui** (espone solo `NSView`). `RelayTerminalView`
  (sottoclasse della view SwiftTerm) aggiunge il drop di file: inserisce i path escaped
  (`Core.ShellEscape`, testato) nel PTY, come Terminal.app. SwiftTerm non lo fa da solo.
- `TerminalHostUI` - `SurfaceRegistry` (Tab.id -> surface, lazy, cap LRU via `SurfaceEvictionPolicy`
  pura) + `WorkspaceAreaController` (AppKit, osserva lo store, scambia il terminale attivo) +
  `AttentionRingView` (bordo colorato di stato attorno al terminale). Path caldo.
- `Panels` - SwiftUI isolata: `Theme` (spacing/typography), `ThemeColors` (colori dal tema corrente),
  `SidebarView`, `TabBarView`, `ContextTitleBar`, `SidebarToggleButton`, `AgentBadge`/`WorkspaceBadge`,
  `ResumeBar`, `FindBar`/`FindModel` (ricerca terminale), `Dashboard` (`DashboardModel` puro +
  `DashboardView`: griglia di triage delle sessioni), `WindowDragArea` (drag finestra dalla title
  strip), `SettingsView` (+ `SettingsComponents`), `ShortcutsList` (recorder shortcut), `KeyEventBridge`
  (NSEvent -> `KeyCombo`, usato anche dal monitor), `MonospaceFonts`. I colori vengono dal tema
  (`AppSettings.theme`), non hardcoded.
- `HookInstaller` - `ClaudeHookInstaller`: setup/uninstall/status idempotenti su
  `~/.claude/settings.json`, marcati `RELAY_MANAGED_HOOK=1`, append (convivono con Otty), backup +
  scrittura atomica. Trasformazioni pure (`merge`/`remove`) separate dall'I/O per i test.
- `LayoutStore` - persistence del layout: `load()`/`save(snapshot)` di `LayoutSnapshot` su disco
  (JSON atomico, versionato, path iniettato). Dipende solo da `WorkspaceModel`, niente AppKit.
- `RelayApp` (`Sources/relay`) - composition root: `AppController`, `MainSplitViewController`,
  `RightPaneController`, `RootOverlayController` (overlay toggle + overlay full-window della
  dashboard), `MainMenuBuilder`, `AgentCoordinator` (unico punto che lega `AgentRuntime` a
  `WorkspaceModel`), `NotificationCoordinator` (unico punto che tocca `UNUserNotificationCenter`),
  `LayoutAutosave`, `PerfSampler` (misure `RELAY_PERF`), `ShortcutRuntime` (`perform(action)` +
  `KeyEventBridge`), `AppControllerDashboard` (apri/chiudi dashboard + decadenza sospesi),
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
- Swift 6 strict concurrency: store osservati `@MainActor`, runtime come actor.

## Gotcha noti

- libghostty non è ancora embeddabile stabile: engine v1 = SwiftTerm. Non reintrodurre zig o
  binari di fork senza una decisione esplicita (vedi ARCHITECTURE, sezione engine).
- `make bundle` assembla `.build/Relay.app` (release + `bundle/Info.plist` + `AppIcon.icns` + firma
  `SIGN_IDENTITY`, default `-` ad-hoc, bundle id `dev.relay.app`; versione iniettata da `./VERSION`
  via PlistBuddy); `make run-app` lo avvia, `make install-app` lo copia in `/Applications`,
  `make dmg` fa `.build/Relay-<version>.dmg` (installer **non firmato Developer ID**: primo avvio con
  "Apri comunque"). Serve per le notifiche: `UNUserNotificationCenter` richiede un bundle id, da bare
  executable (`swift run`) crasha; in sviluppo `make run` va bene (niente notifiche).
- **Distribuzione (brew tap)**: Relay è distribuito via `brew install --cask essedev/relay/relay`.
  Il tap è il repo pubblico `essedev/homebrew-relay` (cask `Casks/relay.rb`), il cask scarica il
  `.dmg` dalle Release di `essedev/relay`. La routine `scripts/release.sh` (via `make release`):
  check working tree pulito + branch main + account gh `essedev`; blocca se il tag `vX` esiste già
  (idempotente per versione); `make dmg` -> sha256 -> `git tag vX` + push -> `gh release create` con
  l'asset -> clona il tap, aggiorna `version`+`sha256` nel cask (l'URL li interpola) e pusha. Per
  rilasciare: bumpa `./VERSION`, commit, **poi** `make release`. Firma: ad-hoc cambia identità a
  ogni build (il collega rifà "Apri comunque" a ogni upgrade e le notifiche possono decadere); per
  un self-signed stabile crea un cert di code signing e passa `SIGN_IDENTITY="<nome cert>"`. Developer
  ID + notarizzazione non ancora in piedi (toglierebbe l'"Apri comunque").
- Icona: `bundle/make-icon.swift` (Core Graphics puro, headless) la disegna; `make icon` rigenera
  `bundle/AppIcon.icns` (committato). Cambi al disegno -> `make icon` poi `make bundle`.
- Notifiche: il trigger è puro (`AgentStateReducer.notification`), lo store emette via
  `onNotifiableTransition` e il `NotificationCoordinator` (solo se `Bundle.main.bundleIdentifier !=
  nil`) filtra per preferenze e consegna. `isVisible = tab selezionata && NSApp.isActive`: se Relay è
  in background notifica anche sulla tab selezionata. Il marker "completato" (`attention`, enum
  `AttentionLevel`) **non** si spegne al semplice ritorno in foreground né alla selezione della tab
  (altrimenti sparirebbe prima che tu lo veda; aprire una tab completata mostra il ring verde +
  flash): l'interazione col terminale in vista (tasto o click, via il monitor in
  `AppControllerNavigation`) **declassa** `unseen` -> `pending` ("in sospeso": visto ma mai
  ripreso), non spegne. Risolvono solo la ripresa vera (prompt -> running, nel reducer), il dismiss
  (card della dashboard) o la chiusura tab; opzionale la decadenza (`pendingDecayHours`, default
  mai). Un completamento sulla tab in vista nasce direttamente `pending`. Al ritorno in foreground
  un flash del ring richiama l'occhio, senza spegnere. Modello ispirato a cmux (vedi CYCLES),
  esteso col livello quieto. Il coordinatore è
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
- Shortcut rimappabili: **tutte** le azioni rimappabili passano dallo **stesso** local monitor
  (non da keyEquivalent di menu, che non gestisce ogni combo). Il monitor converte l'evento in
  `KeyCombo` (`KeyEventBridge`) e cerca l'azione in `settings.keybindings`, poi `perform(action)`
  (`ShortcutRuntime`). I menu mostrano la combo **nel titolo** con `keyEquivalent` vuoto (niente
  doppio trigger); il menu si ricostruisce al cambio binding (`observeKeybindings`). Fissi (con
  keyEquivalent vero): Copy/Paste/Select All (responder SwiftTerm), Quit, Settings, e i select
  1..9. Il recorder in impostazioni alza `settings.isCapturingShortcut`: il monitor si fa da parte
  così l'evento arriva al recorder invece di eseguire l'azione. Default e conflitti in `AppSettings`.
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
- Drag finestra: **non** `isMovableByWindowBackground` (trascinerebbe anche il terminale). Le due
  strip in alto (`ContextTitleBar` nel right pane, `trafficLightsStrip` nella sidebar) usano
  `WindowDragArea` (NSView pura con `performDrag` + doppio click = zoom secondo la preferenza
  macOS). NSView pura, non un gesture SwiftUI: `mouseDownCanMoveWindow` non si propaga in modo
  affidabile sotto hosting SwiftUI.
- Find/Clear/Jump: `Cmd+F` (find bar flottante sul terminale, motore search di SwiftTerm),
  `Cmd+K` (clear = `ESC[3J` + Ctrl+L al pty), `Cmd+J` (`WorkspaceStore.focusNextAttention`, ciclico
  sull'ordine visivo). Sono keyEquivalent veri del menu (non l'event monitor): funzionano col
  terminale in focus. Search/clear passano dal protocollo `TerminalSurfaceHandle` (niente tipi
  SwiftTerm fuori dall'engine).
- Ring di attenzione (`AttentionRingView`): bordo colorato attorno al terminale della tab in vista
  che ne segnala lo stato (verde = completato non visto, statico + flash; giallo/rosso pulsante =
  aspetta input/errore). Il ring risponde solo a `unseen`: un sospeso (`pending`) non accende il
  bordo (segnale quieto: badge ad anello vuoto + dashboard), altrimenti useresti la shell con un
  ring verde permanente. Colori dai colori ANSI del tema, coerenti coi badge. Overlay con `hitTest`
  nil (non intercetta eventi); i terminali si inseriscono `positioned: .below` così resta in cima.
  L'observer del ring (`observeRing`) è **separato** da `render()` e **non** scrive `attention`:
  altrimenti un completamento sulla tab in vista si spegnerebbe da solo (loop col reset della
  visita). Il declassamento (mark-read) lo fa solo l'interazione col terminale (monitor key/mouse).
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
  mancante/corrotto/versione ignota. Bump `LayoutSnapshot.currentVersion` **solo per cambi
  breaking**: la load scarta le versioni diverse (= butta il layout dell'utente); un campo nuovo
  opzionale (es. `pendingSince`) è additivo e non bumpa. Il sospeso persiste come `pendingSince`
  nel `TabSnapshot` (anche `unseen` degrada a pending al riavvio: il segnale forte sarebbe stantio).
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
- Dashboard (`Cmd+D`, azione rimappabile `toggleDashboard`): overlay full-window
  (`RootOverlayController.presentFullOverlay`, wiring in `AppControllerDashboard`). Griglia flat
  delle sessioni agente per urgenza, card con età e dismiss, filtro e navigazione da tastiera.
  Logica pura in `Panels/DashboardModel` (testata); solo dati del model, funziona anche per tab
  sfrattate dal cap LRU (niente preview del terminale: richiederebbe surface vive). **Mentre è
  aperta il monitor si fa da parte**: i tasti vanno al filtro (niente nav 1..9, niente mark-read),
  resta attivo solo il toggle per chiuderla; Esc lo gestisce la vista (`onExitCommand`). La
  decadenza dei sospesi si applica a boot/foreground/apertura dashboard (niente timer).
- Non ancora fatto: split, distribuzione firmata Developer ID, generalizzazione multi-agente
  (Codex/opencode).
