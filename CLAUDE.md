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
-> risolto, con dismiss e decadenza opzionale)** + **riordino libero di workspace e tab via drag &
drop (`DragGesture` + `.offset`, linea di inserimento, vedi `Panels/Reorderable`)**.
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
  `AgentWireCoding` (codifica JSON date ISO 8601 con ms). Puro, niente AppKit né WorkspaceModel.
- `WorkspaceModel` - `WorkspaceStore`/`Workspace`/`Tab` (@Observable) +
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
  `DashboardView`: griglia di triage delle sessioni), `Reorderable` (riordino drag & drop di
  workspace e tab: `DragGesture` + `.offset` + linea di inserimento), `WindowDragArea` (drag
  finestra dalla title strip), `SettingsView` (+ `SettingsComponents`), `ShortcutsList` (recorder
  shortcut), `KeyEventBridge`
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
- `make bundle` assembla `.build/Relay.app` (release + `relay` **e `relay-cli`** in `Contents/MacOS`,
  entrambi firmati - il nested prima dell'outer - + `bundle/Info.plist` + `AppIcon.icns` + firma
  `SIGN_IDENTITY`, default `-` ad-hoc, bundle id `dev.relay.app`; versione iniettata da `./VERSION`
  via PlistBuddy). `relay-cli` nel bundle serve agli utenti brew: Impostazioni > Agents ha un'azione
  che installa gli hook usando il cli accanto all'eseguibile (`makeHookControls`), così non serve
  trovarlo nel PATH. `make run-app` lo avvia, `make install-app` lo copia in `/Applications`,
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
  ripreso), non spegne. Risolve solo un'azione **attiva** sulla conversazione - la ripresa vera
  (prompt -> running) o una ri-presa attiva (`/clear`, `/resume`: SessionStart `source` clear/resume
  -> `resetsAttention`, letto dal CLI, spegne il sospeso mantenendo `state` idle) - più il dismiss
  (card della dashboard), la chiusura tab e la decadenza (`pendingDecayHours`, default **12h**: il
  sospeso è il segnale quieto e già visto, tenerlo per sempre è banner blindness; `unseen` invece
  non scade mai da solo). Il clock del marker è `Tab.attentionSince` (timbrato alla nascita e al
  declassamento), **distinto** da `lastEventAt` (che avanza a ogni evento per la monotonicità): il
  decay e l'età del sospeso misurano da `attentionSince`, così un no-op (SessionEnd, idle->idle) non
  li falsifica, e al restore il clock riparte dal boot (un completamento vecchio mai visto non viene
  spazzato al primo avvio). Un completamento sulla tab in vista nasce direttamente `pending`. Al
  ritorno in foreground un flash del ring richiama l'occhio, senza spegnere. Modello ispirato a cmux
  (vedi CYCLES),
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
  come `paneId`. Il socket è `~/.relay/relay.sock` (override `RELAY_SOCKET`); un socket stantio
  (owner morto) è rimosso da `unlink` prima del `bind`, quindi non blocca il riavvio. **No-stomp**:
  prima di `unlink`+`bind` il receiver fa una `connect` di prova (`UnixSocket.isListening`); se un
  owner **vivo** risponde non lo tocca (`addressInUse`), così una seconda istanza non ruba il
  socket alla prima. **Self-heal**: il receiver osserva la runtime dir (vnode `DispatchSource`, non
  un timer) e **ri-binda** se il socket file sparisce sotto di lui; senza, un socket cancellato da
  fuori orfanava il receiver e **congelava tutti i badge** sull'ultimo stato ricevuto (la causa dei
  badge idle/loading bloccati). Ri-binda solo se il file è davvero assente (se esiste, un'altra
  istanza ne ha uno vivo: no ping-pong).
- Ordine degli eventi agente: ogni hook è un processo effimero con la sua connessione e il
  receiver drena in parallelo (un client bloccato non ferma gli altri), quindi il trasporto NON
  garantisce l'ordine. Lo ristabiliscono il pump FIFO in `AgentCoordinator` (AsyncStream, un solo
  consumer - mai `Task {}` per evento, non preservano l'ordine di enqueue) e la guardia di
  monotonicità sui timestamp nello store (`applyAgentState` scarta gli eventi più vecchi
  dell'ultimo applicato per tab). Il wire codifica le date ISO 8601 **con millisecondi**
  (decode tollerante col vecchio formato a secondi interi); un'app vecchia però non decodifica gli
  eventi di un CLI nuovo: dopo un cambio al wire ricompila/reinstalla entrambi.
- Mapping hook -> stato in due metà, entrambe in `HookInstaller`: statico per evento
  (`ClaudeHookInstaller.specs`, finisce nei comandi di settings.json) e dipendente dal payload
  (`ClaudeHookStateMapper`, applicato dal CLI): il `PreToolUse` di un tool che apre un prompt
  bloccante (`AskUserQuestion`, `ExitPlanMode`) diventa `needs_input` - quei tool non passano da
  `PermissionRequest` né producono `Stop` finché non rispondi; senza correzione la tab resterebbe
  `running` per sempre con la domanda aperta.
- Shift+Invio / kitty keyboard: la surface inietta `KITTY_WINDOW_ID=1` nell'env
  (`SwiftTermEngine.start`), che dichiara il supporto al kitty keyboard protocol (SwiftTerm lo
  implementa: query + encoding). Claude Code attiva il protocollo solo per terminali noti; **non**
  settare `TERM_PROGRAM` (lo prioritizza e maschererebbe il segnale, claude-code#27868). Cosi
  Shift+Invio/Ctrl+Invio arrivano distinti all'app, senza intercettare l'input nel path caldo.
- Scroll fluido: SwiftTerm quantizza lo scroll (`event.deltaY` -> salti di 1/3/10/20+ righe,
  delta precisi del trackpad ignorati). `RelayTerminalView.handleSmoothScroll` converte
  `scrollingDeltaY` in righe (1:1 col gesto, momentum incluso) accumulando il residuo sub-riga
  (`PreciseScrollAccumulator`, puro e testato). Le righe diventano scroll dello scrollback oppure,
  con mouse reporting attivo (es. Claude Code), eventi rotella SGR verso l'app (`sendWheelReports`,
  un evento per riga di gesto). **Non si può fare override di `scrollWheel`**: in SwiftTerm è
  `public override`, non `open` - l'evento arriva via `SmoothScrollInterceptor` (local monitor
  `.scrollWheel` + hitTest, stesso pattern del monitor tastiera). Unico passthrough a SwiftTerm:
  alternate buffer senza reporting (less/vim senza mouse, frecce sintetiche - logica interna, non
  replicarla). Granularità resta la riga intera (il renderer disegna a offset di riga, `yDisp`
  Int): smoothness sub-riga richiederebbe un fork dell'engine.
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
  sull'ordine visivo). Sono **azioni rimappabili** (`ShortcutAction.find/findNext/findPrevious/
  clear/nextAttention`), quindi passano dallo **stesso local monitor** delle altre, non da
  keyEquivalent di menu; il monitor consuma l'evento anche col terminale in focus. Search/clear
  passano dal protocollo `TerminalSurfaceHandle` (niente tipi SwiftTerm fuori dall'engine).
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
- Sidebar width: `AppSettings.sidebarWidth` (UserDefaults, default 250, clamp 200-340), non nel
  `LayoutSnapshot`. `MainSplitViewController` la applica alla prima passata di layout (una volta) e
  la salva sul resize (`splitViewDidResizeSubviews`, solo quando espansa).
- Lista workspace: `ScrollView` + `LazyVStack` custom, **non** `List`. La `List` disegna un highlight
  full-size di sistema sotto la riga bersaglio del menu contestuale (fuori dal tema flat). Con la
  VStack gestiamo noi selezione/hover/menu; il riordino è drag & drop (vedi gotcha "Riordino drag
  & drop" sotto), non `onMove`. La sidebar itera `store.orderedWorkspaces` (derivato: pinned, poi
  con attenzione, poi resto) - **display-only**, non toccare `store.workspaces` per ordinare:
  quello è l'ordine canonico su cui agiscono drag e persistence. Rename inline del workspace dal
  menu contestuale (`WorkspaceStore.renameWorkspace`).
- Riordino drag & drop (sidebar e tab bar): meccanismo in `Panels/Reorderable` (`reorderableRow` +
  `reorderableContainer` + `ReorderInsertionLine`). **Non** `onDrag`/`onDrop` di sistema (generano
  una preview con snap-back al rilascio): la riga *vera* si solleva con un `DragGesture` + `.offset`
  (semitrasparente, zIndex alto) seguendo il puntatore, una linea segnala l'inserimento, e al
  rilascio lo scambio parte in `withAnimation` mentre l'offset torna a zero (nessun salto). I frame
  di layout li raccoglie un `PreferenceKey` in un coordinate space nominato (l'`.offset` è un
  trasform di rendering, non altera il frame di layout, quindi i frame restano stabili durante il
  gesto). Store puro e posizionale: `WorkspaceStore.moveWorkspace(_:before:)` e
  `moveTab(_:before:in:)` (inserisce prima del target, `nil` = in fondo). **Sidebar**: la linea è
  vincolata al segmento di float del workspace trascinato (`segmentIndex(for:)`:
  pinned/attenzione/resto), perché il float non lascia attraversare i segmenti - così l'indicatore
  non promette una posizione che il float poi annulla. **Tab bar**: nessun segmento, ordine unico,
  linea libera. Su macOS lo `ScrollView` non fa drag-scroll, quindi il `DragGesture` non confligge
  con lo scroll; l'identità del trascinato vive in `@State` (niente pasteboard, niente drop
  incrociati).
- Chiusura tab/workspace: passa da `AppController.requestCloseTab/requestCloseWorkspace` (Cmd+W e le
  x dei pannelli), che chiedono conferma via `NSAlert` sheet se nel pty gira un comando in foreground
  (`TerminalSurfaceHandle.foregroundProcessName()` = `tcgetpgrp` vs `shellPid` + safe-list shell; solo
  foreground, i job in background non contano). Chiudere l'ultima tab chiude il workspace (cascade in
  `WorkspaceStore.closeTab`). Il messaggio (`closeInfo`) nomina Claude per **ogni** stato di
  sessione viva (running/needsInput/idle/error: il proc_name del binario claude è la versione,
  es. "2.1.200", inutilizzabile); solo `.unknown` mostra il nome grezzo del processo. Non usare
  `tab.resume` come criterio: persiste oltre il riavvio e dopo un restore nel pty può girare
  tutt'altro.
- Persistence layout: `~/.relay/layout.json` (override `RELAY_LAYOUT`; path **iniettato** in
  `LayoutStore`, i test usano una dir temporanea, mai `~/.relay`). Salvataggio via `LayoutAutosave`
  (debounced ~500ms + flush on `applicationWillTerminate`), che osserva `store.snapshot()`: dipende
  solo dai campi persistiti, quindi gli eventi agente non scatenano scritture. **Demo mode non
  persiste** (non istanzia l'autosave). Restore al boot ricade sul seed default se file
  mancante/corrotto/versione ignota. Bump `LayoutSnapshot.currentVersion` **solo per cambi
  breaking**: la load scarta le versioni diverse (= butta il layout dell'utente); un campo nuovo
  opzionale (es. `pendingSince`) è additivo e non bumpa. Il sospeso persiste come `pendingSince`
  nel `TabSnapshot` (anche `unseen` degrada a pending al riavvio: il segnale forte sarebbe stantio).
- Robustezza layout (dato utente non ricreabile): `LayoutStore.save` **rifiuta** uno snapshot
  degradato (`degenerateSnapshot`: 0 workspace o un workspace senza tab - a runtime impossibile,
  quindi sintomo di una race) invece di scrivere sopra il buono, tiene un backup `layout.json.bak`
  del primario prima di sovrascrivere, e `load` ricade sul `.bak` se il primario è
  mancante/corrotto/degradato. Non allentare la guardia: è ciò che ha fixato le tab sparite dopo un
  upgrade. La validità è pura (`isValidForPersistence`, testata).
- Single-instance: **due Relay condividono `~/.relay`** (layout + socket) e i loro autosave si
  pesterebbero -> layout corrotto. `LSMultipleInstancesProhibited=true` (bundle/Info.plist) lo
  previene lato LaunchServices; `Relay.main` ha anche un guard runtime (se un'altra istanza dello
  stesso bundle id gira, la attiva ed esce). Quel guard vale solo dal bundle; un lancio senza
  bundle id (`swift run`) lo salta, e sullo stesso `~/.relay` unlinkerebbe il socket dell'app viva
  (badge congelati). Perciò `Relay.main` ha un **secondo guard basato sul path**: se un receiver
  vivo possiede già il nostro socket (`AgentEventClient.isReceiverReachable`) esco. Istanze dev
  legittime usano `RELAY_SOCKET`/`RELAY_LAYOUT` diversi: path diverso, nessun match, partono
  normali. Non elimina la race di due lanci simultanei (per quella servirebbe un lockfile): copre
  il caso reale del lancio dev mentre un'istanza è già viva.
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
