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
drop (`DragGesture` + `.offset`, linea di inserimento, resolver puro `SidebarDrop`, vedi
`Panels/Reorderable`)** + **mark-read filtrato alla sola interazione col terminale (`terminalOwns`)
+ override unread manuale dal menu contestuale (`toggleUnread`)** + **resume affidabile al riavvio
(soglia anti-stantio `eventFloor`)** + **ordine sidebar "lista chat" (un'attività non vista bumpa
il workspace in cima con un riordino reale e persistente; la ripresa non muove nulla)** + **archivio
dei workspace (sezione
collassabile in fondo alla sidebar, menu `Archive`/`Unarchive`; drag dentro/fuori ancora da fare)**
+ **pannello "About Relay" (menu Relay > About Relay, stile "About This Mac": icona + nome +
versione dal bundle) - vedi gotcha** + **onboarding "Welcome to Relay" (overlay al primo avvio,
riapribile da Help > Welcome to Relay: 5 pagine coi componenti veri al posto di screenshot,
pagina hook azionabile, stati di attenzione cliccabili con preview live, temi selezionabili
dal vivo) - vedi gotcha** + **nomina automatica dei workspace via LLM OpenAI-compatible
(`NameOrigin`/`Core.WorkspaceNaming`/`NamingController`, API key su file 0600) - vedi gotcha** +
**flash di completamento sulla tab in vista (nasce forte, declassa dopo ~4s) + notifiche
cliccabili (il click porta in vista la tab) + play dell'update in una tab dedicata - vedi
gotcha** + **sposta una tab in un nuovo workspace dal menu contestuale (surface viva preservata)
+ giro di pulizia del codice (componenti UI condivisi, dedup di helper, overlay full-window
unificato, conversione colore unica) + strumenti di lint pinnati per una CI deterministica +
**pannello Runtime Stats dal menu View (RSS, CPU, workspace/tab, surface vive; campiona solo da
aperto) - vedi gotcha** + **split panes e multi-window (finestre come partizione dei workspace su
un solo store) - vedi gotcha** + **split v2 sul modello cmux (i pane ospitano le tab: strip per
pane con action lane, click-to-focus, `docs/features/split-panes.md`) + selezione che sopravvive
all'output in streaming + menu bar HIG-conforme (Window/Help/Services, New Window `⇧⌘N`, menu Go
coi nomi reali, keyEquivalent nativi) - vedi gotcha**.
**Baseline delle milestone chiuso**, app installabile in locale; prossimo giro a scelta
(distribuzione firmata, multi-agente) - vedi `docs/ROADMAP.md`. Pipeline hook -> badge -> resume
validata a mano con Claude reale; le notifiche girano solo dal bundle (`make run-app`).

## Comandi

- `make build` / `make test` / `make run` / `make check` (definition of done prima di un commit
  grosso e sempre prima di proporre un push).
- Lint: `make tools` scarica le versioni **pinnate** di SwiftFormat/SwiftLint in `.build/tools`
  (binari dai release GitHub, versioni nel Makefile). `make lint`/`format`/`check` le usano; CI
  e locale girano la stessa versione, così un upgrade upstream non rompe il lint su codice
  invariato. Non usare la `brew install` (prende sempre l'ultima) per il giro di qualità.
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
  drop di file; `SemanticVersion` + `ReleaseCheck` = confronto versioni e parsing della GitHub
  Release per il check aggiornamenti, puro e testato; `WorkspaceNaming` = prompt/parse/sanitize
  della nomina automatica dei workspace + `NamingTriggerPolicy` = decisione pura su *quando*
  nominare (streak comando + stabilizzazione cwd), entrambi puri e testati). Nessuna dipendenza.
  Il tema vive qui
  perché sia il terminale (`TerminalEngine`) sia la chrome (`Panels`) lo convertono nei rispettivi
  tipi.
- `AgentProtocol` - tipi evento/stato agente, puro. Niente I/O, niente AppKit.
- `AgentRuntime` - trasporto eventi agente: `AgentEventReceiver` (server Unix socket),
  `AgentEventClient` (client, usato dal CLI), `RelayRuntimePaths` (path socket + layout),
  `AgentWireCoding` (codifica JSON date ISO 8601 con ms). Puro, niente AppKit né WorkspaceModel.
- `WorkspaceModel` - `WorkspaceStore`/`Workspace`/`Tab`/`RelayWindow` (@Observable) +
  `SplitNode`/`SplitPane` (albero di split puro, foglie = pane con le loro tab, modello cmux;
  operazioni in `WorkspaceStore+Split`, vedi gotcha split) +
  finestre (`WorkspaceStore+Windows`) + persistence (`WorkspaceStore+Persistence`) +
  `AttentionLevel` (marker post-completamento a tre livelli: unseen/pending, vedi gotcha) +
  `AgentStateReducer` (incl. classificatore notifiche) + `AppSettings` (tema/font family/cursore/
  sidebar/notifiche/**keybindings**/decadenza sospesi/vista dashboard, UserDefaults) + `WindowTitle` +
  `LayoutSnapshot` (Codable) + `AgentNotification` + `ShortcutAction`/`KeyCombo` (azioni
  rimappabili + combinazione pura) + `NameOrigin` (origine del nome workspace:
  `.default`/`.generated`/`.user`, guida la nomina automatica). Lookup e navigazione in
  `WorkspaceStore+Navigation` (`reveal(workspaceID:tabID:)` = seleziona workspace+tab e de-archivia;
  `tab(id:)` = tab per id fra tutti i workspace); `moveTabToNewWorkspace` estrae una tab in un nuovo
  workspace preservando la surface viva (vedi gotcha). Puro, niente AppKit.
- `TerminalEngine` - astrazione `TerminalEngine`/`TerminalSurfaceHandle` + backend SwiftTerm.
  **Nessun tipo SwiftTerm deve trapelare fuori da qui** (espone solo `NSView`). `NSColor(relay:)`
  (init da `RelayColor`) vive qui: è il modulo AppKit più basso che TerminalHostUI e il composition
  root importano entrambi (Core non può, niente AppKit), così la conversione non è triplicata.
  `RelayTerminalView`
  (sottoclasse della view SwiftTerm) aggiunge il drop di file: inserisce i path escaped
  (`Core.ShellEscape`, testato) nel PTY, come Terminal.app. SwiftTerm non lo fa da solo.
- `TerminalHostUI` - `SurfaceRegistry` (Tab.id -> surface, lazy, cap LRU via `SurfaceEvictionPolicy`
  pura; **una sola per l'app**, condivisa dalle finestre) + `WorkspaceAreaController` (AppKit,
  osserva lo store e riconcilia l'albero di pane in `NSSplitView` annidate, vedi `+PaneTree`) +
  `PaneView` (strip di tab iniettata + terminale scambiabile + ring + bordo di focus) +
  `AttentionRingView`. Path caldo.
- `Panels` - SwiftUI isolata: `Theme` (spacing/typography), `ThemeColors` (colori dal tema corrente),
  `SidebarView`, `PaneTabBar` (la strip di tab di un pane + action lane; `PaneTabBarActions` =
  closure verso il composition root), `ContextTitleBar`, `SidebarToggleButton`, `AgentBadge`/`WorkspaceBadge`,
  `ResumeBar`, `FindBar`/`FindModel` (ricerca terminale), `Dashboard`/`Dashboard+Board` (`DashboardModel`
  puro + `DashboardView`: triage delle sessioni in kanban per stato o griglia, con toggle),
  `Reorderable` (riordino drag & drop di
  workspace e tab: `DragGesture` + `.offset` + linea di inserimento), `WindowDragArea` (drag
  finestra dalla title strip), `SettingsView` (+ `SettingsComponents`), `AboutView` (pannello
  "About Relay" a tema), `Onboarding` (`OnboardingModel` puro + `OnboardingView` +
  `OnboardingPages`/`OnboardingAttention` + `RelayMarkView`, icona procedurale), `ShortcutsList`
  (recorder shortcut), `NamingControls` (closure per la API key della nomina automatica +
  `WorkspaceNamingBlock` nelle impostazioni), `RuntimeStatsView` (pannello read-only menu View per
  memoria/CPU/conteggi runtime), `StatusDot`/`CommandChip`/`CloseButton` (primitive UI condivise:
  pallino di stato pieno/anello, pill monospace per keycap e comandi, bottone di chiusura `xmark`),
  `KeyEventBridge`
  (NSEvent -> `KeyCombo`, usato anche dal monitor), `MonospaceFonts`. I colori e le misure vengono
  dal design system (`Theme`/`ThemeColors`), non hardcoded.
- `HookInstaller` - `ClaudeHookInstaller`: setup/uninstall/status idempotenti su
  `~/.claude/settings.json`, marcati `RELAY_MANAGED_HOOK=1`, append (convivono con Otty), backup +
  scrittura atomica. Trasformazioni pure (`merge`/`remove`) separate dall'I/O per i test.
- `LayoutStore` - persistence del layout: `load()`/`save(snapshot)` di `LayoutSnapshot` su disco
  (JSON atomico, versionato, path iniettato). Dipende solo da `WorkspaceModel`, niente AppKit.
- `RelayApp` (`Sources/relay`) - composition root: `AppController`, `MainSplitViewController`,
  `RightPaneController`, `RootOverlayController` (overlay toggle + overlay full-window della
  dashboard), `MainMenuBuilder`, `AgentCoordinator` (unico punto che lega `AgentRuntime` a
  `WorkspaceModel`), `NotificationCoordinator` (unico punto che tocca `UNUserNotificationCenter`),
  `UpdateController` (unico punto che tocca rete/clipboard per il check aggiornamenti),
  `RelayWindowController` (una `NSWindow` col suo split e i suoi overlay, legata a `RelayWindow` per
  id; `AppControllerWindows` le crea e le chiude),
  `NamingController` (unico punto che tocca la rete per la nomina automatica dei workspace) +
  `NamingCredentialStore` (API key su file 0600 in `~/.relay`), `LayoutAutosave`, `PerfSampler`
  (misure `RELAY_PERF`), `RuntimeStatsSampler` (campionamento utente on-demand per il pannello
  Runtime Stats), `ShortcutRuntime` (`perform(action)` + `KeyEventBridge`),
  `AppControllerDashboard` (apri/chiudi dashboard + decadenza sospesi), `FullOverlayPresenter`
  (host unico degli overlay full-window dashboard/onboarding: mutua esclusione per costruzione),
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
  flash): l'interazione col terminale in vista **declassa** `unseen` -> `pending` ("in sospeso":
  visto ma mai ripreso), non spegne. **Posizione e segnale sono scollegati** (modello "lista chat"):
  la posizione in sidebar è un ordine **reale e persistente**, non un float derivato. A muoverla è
  solo un **bump** (`WorkspaceStore.bumpWorkspaceToTop`, da `applyAgentState`), che porta il
  workspace in cima ai non-pinned quando un'attività arriva **non vista** - completamento o entrata
  in `needs_input` con `!isVisible` (simmetrico al segnale forte e alla notifica: un completamento
  sulla tab **in vista** **non** bumpa, così la riga non salta sotto le mani). La
  ripresa (`running`) non muove niente: la riga su cui lavori resta ferma, la scavalca solo un altro
  bump o il tuo drag. Il segnale (`attention`: ring/badge) vive a parte: declassamento (mark-read),
  dismiss e decadenza lo spengono ma **non** fanno scendere la riga (scende solo col drag).
  "Interazione col terminale" è filtrata (`owningPane`,
  `WorkspaceAreaController`, via il monitor in `AppControllerNavigation`): un tasto col terminale
  in focus o un click **dentro la sua view**, non un click di navigazione nella chrome (cambio tab
  nella strip, cambio workspace nella sidebar) né un tasto in un campo di rename - quelli non
  consumano il marker. Risolve solo un'azione **attiva** sulla conversazione - la ripresa vera
  (prompt -> running) o una ri-presa attiva (`/clear`, `/resume`: SessionStart `source` clear/resume
  -> `resetsAttention`, letto dal CLI, spegne il sospeso mantenendo `state` idle) - più il dismiss
  (card della dashboard), la chiusura tab e la decadenza (`pendingDecayHours`, default **12h**: il
  sospeso è il segnale quieto e già visto, tenerlo per sempre è banner blindness; `unseen` invece
  non scade mai da solo). Override manuale dal **menu contestuale** (sidebar sulla tab selezionata
  del workspace, strip per-tab) e dal menu Workspace: `store.toggleUnread` è chiavato su `unseen`,
  non su "attenzione
  accesa". Solo `unseen` è "unread": lì il menu mostra **"Mark as Read"** e spegne a `none`. Un
  `pending` è **già visto** (segnale quieto), quindi non lo si "legge": come da `none` il menu mostra
  **"Mark as Unread"** -> `Tab.markUnread` che lo ri-alza a `unseen` (riusa il segnale forte
  esistente: float, ring, badge; niente notifica, che nasce solo da eventi reali). Il pending si
  spegne altrove (resume, dismiss, decadenza), non da questo toggle. Al riavvio degrada a pending
  come ogni `unseen`. Il clock del marker è `Tab.attentionSince` (timbrato alla nascita e al
  declassamento), **distinto** da `lastEventAt` (che avanza a ogni evento per la monotonicità): il
  decay e l'età del sospeso misurano da `attentionSince`, così un no-op (SessionEnd, idle->idle) non
  li falsifica, e al restore il clock riparte dal boot (un completamento vecchio mai visto non viene
  spazzato al primo avvio). Un completamento sulla tab **in vista** nasce comunque col segnale
  forte (`unseen`: ring verde + flash + badge pieno) e dopo un breve **flash** (~4s) il composition
  root lo declassa a `pending` (mark-read differito: `store.onVisibleCompletion` ->
  `AppController.scheduleCompletionFlashDecay` -> `store.markSeen(id)`; no-op se nel frattempo
  interagisci/riprendi/dismetti). Prima nasceva già `pending`, niente flash. Il reducer non guarda
  più la visibilità (`reduce` senza `isVisible`): il completamento nasce sempre `unseen`, il
  declassamento in vista è un effetto del composition root. Al ritorno in foreground un flash del
  ring richiama l'occhio, senza spegnere. Modello ispirato a cmux
  (vedi CYCLES),
  esteso col livello quieto. Il coordinatore è
  `UNUserNotificationCenterDelegate` e forza `willPresent -> [.banner,.sound,.list]`: **senza, i
  banner sono soppressi quando Relay è frontmost**. Al primo avvio dal bundle macOS chiede il
  permesso una volta; una firma ad-hoc che cambia a ogni reinstall può farlo decadere (log
  `auth status` al boot: 2 = authorized). **Click sulla notifica**: riporta in vista la tab che
  l'ha generata. `AgentNotification` porta `tabID`/`workspaceID`, che il coordinatore mette nel
  `userInfo` del contenuto; alla ricezione (`didReceive response`, azione di default) legge gli id
  e delega a `AppController.activateTab` (seleziona workspace+tab, de-archivia se serve, porta la
  finestra in primo piano). Senza l'handler il click non faceva nulla.
- Check aggiornamenti (canale brew): `UpdateController` (RelayApp) al lancio confronta la versione
  installata (`CFBundleShortVersionString`) con l'ultima GitHub Release
  (`/repos/essedev/relay/releases/latest`), e se più recente accende una pill transitoria in fondo
  alla sidebar, **sopra la sezione Archive** (l'ancora Archive resta fissa, la pill si inserisce nel
  flusso sopra di lei). La logica è pura in `Core` (`SemanticVersion` compara, `ReleaseCheck` parsa
  e decide se l'update è azionabile rispettando lo skip), testata; rete/clipboard/apertura URL
  stanno nel controller. **Non scarica**: la pill offre solo il comando `brew update && brew upgrade
  --cask relay` da copiare, le release notes e "Skip this version" (persistito in
  `skippedUpdateVersion`, si ripropone solo a una versione ancora più nuova). Nessun conflitto con
  brew, che resta l'updater. Oltre a "copia", la pill ha un **play** che esegue il comando in una
  tab dedicata "Relay Update" (`AppController.runUpdateInTab`, iniettato via
  `makeSidebarConfig(onRunUpdate:)`): sempre una tab fresca, il testo va nel pty col solito ritardo
  del resume; `brew` sostituisce il bundle mentre l'app gira (safe su APFS, riparte alla
  riapertura). Come le notifiche gira **solo dal bundle** (`swift run` non ha
  `CFBundleShortVersionString`: `makeSidebarConfig()` -> `nil`, niente pill, check no-op). Preferenza
  in Settings > Updates (default on) + voce menu "Check for Updates…" (check manuale, dà sempre un
  feedback, anche "yoùre up to date").
- Nomina automatica workspace (LLM OpenAI-compatible): un workspace nato come placeholder o da
  cartella (`NameOrigin.default`) viene rinominato al primo segnale utile da quello che ci fai. La
  logica pura sta in `Core.WorkspaceNaming` (costruzione prompt dai segnali cwd/comando/agente,
  parsing, sanitizzazione: strip virgolette/markdown, cap ~28 char al confine di parola, reject dei
  generici; testata) e in `Core.NamingTriggerPolicy` (la state-machine pura che decide *quando* il
  segnale è abbastanza forte: streak del comando + stabilizzazione cwd, con soglie; testata). Il
  `NamingController` (RelayApp, **unico punto che tocca la rete** per questa
  feature) osserva l'eleggibilità (`settings.workspaceNamingEnabled` + esiste un `.default` +
  `credentials.hasKey()`) e, quando serve, fa girare un **poll** (timer ~3s) sui workspace
  `.default`. Il contesto si raccoglie su **tutte le tab** del workspace, non sulla selezionata: la
  tab in vista è spesso una shell ferma mentre l'agente gira in quella accanto, ed è il workspace
  che si nomina. `Core.WorkspaceNaming.signals` (puro, testato) sceglie **una** tab - la più
  informativa (agente > comando > cwd, a parità vince quella a schermo) - e ne prende i segnali
  **interi**: mescolare il comando di una tab con la cwd di un'altra descriverebbe un'attività che
  non esiste. Se la tab scelta non ha cwd (mai realizzata: restore, sfratto LRU) si ricade sul
  `rootPath` del workspace. Tre trigger, dal più forte: agente attivo (`running`/`needs_input`) ->
  subito; comando in foreground stabile per 2 tick (argv via `TerminalSurfaceHandle
  .foregroundCommandLine`, letta con `KERN_PROCARGS2`) -> es. "Homebrew Update"; cwd stabile fuori
  dalla home per ~10s -> es. "Yellow Hub". **La cwd è quella della shell viva**
  (`WorkspaceAreaController.currentDirectory`, precedenza `Core.CurrentDirectory` = viva -> OSC 7 ->
  root, iniettata nel controller), **non** `tab.currentDirectory`: quello è il solo OSC 7, che zsh
  in Relay non emette (vedi gotcha OSC 7), quindi il segnale cwd sarebbe sempre nil e la nomina da
  directory non scatterebbe (era la causa del "Regenerate name" muto su un workspace fermo).
  **Single-flight per workspace**, max 2 tentativi **distanziati da un cooldown di 60s** poi si
  arrende in silenzio (senza il cooldown la policy, che ha già deciso "nomina", ridecideva a ogni
  tick: un blip di rete bruciava i due tentativi in sei secondi e spegneva la nomina per sempre).
  La nomina **automatica** resta silenziosa (mai un alert per un nome che non hai chiesto); quella
  **manuale** no, vedi sotto. Il poll gira **solo** finché c'è un `.default`
  (osservazione su `nameOrigin`): quando tutti sono nominati il timer si ferma. Alla risposta,
  `store.applyGeneratedName` applica **solo** se il workspace è ancora `.default` (l'utente può aver
  rinominato nel frattempo: `renameWorkspace` marca `.user`, intoccabile). `NameOrigin`: `.default`
  (eleggibile) -> `.generated` (one-shot) / `.user` (a mano). Snapshot **additivo** (assente ->
  `.user`: i nomi pre-feature sono conosciuti dall'utente, non rigenerare). **"Regenerate name"**
  (menu contestuale della sidebar **e** menu Workspace) passa da
  `AppController.regenerateWorkspaceName` -> `NamingController.regenerate`: torna `.default`, azzera
  abbandono/tentativi/cooldown, nomina **subito** col contesto corrente (salta le soglie della
  policy) e chiede un nome **diverso** da quello attuale (`prompt(avoiding:)`, solo se l'attuale
  l'ha generato il modello: `temperature` è 0, quindi a contesto invariato ridarebbe lo stesso
  identico nome e sembrerebbe non aver fatto niente). **Non cablarlo su `store.markNameRegenerable`
  da solo**: quello rimette solo il workspace in coda al poll passivo, che su un workspace fermo
  resta muto - era il bug del "Regenerate name che non fa niente" (`regenerate` era codice morto,
  mai chiamato da nessuna delle due voci). A differenza del poll, l'azione manuale **non tace mai**:
  ogni ramo che non produce un nome torna un `NamingFailure` (`notConfigured`/`noContext`/
  `requestFailed`) che il composition root mostra come sheet (`presentNamingFailure`, con "Open
  Settings…" sul primo). La
  API key è un segreto: **file 0600** `~/.relay/naming-credentials.json` (`NamingCredentialStore`),
  **non** UserDefaults; base URL + model in `AppSettings`. Config in Settings > Agents > Workspace
  naming. Gira anche da `swift run` (non è bundle-gated come notifiche/update), ma è inerte senza
  chiave. Mai in demo mode (nomi fissi).
- **Modelli di reasoning nella nomina** (`ChatCompletionClient`, il client HTTP estratto dal
  `NamingController`): il tetto `max_tokens` deve coprire anche il *pensiero*, non solo il nome.
  Con 16 token un modello di reasoning (es. `deepseek/deepseek-v4-flash` su OpenRouter) torna
  `finish_reason: length` e **`content: null`**, quindi non nomina **mai** - e con `content: String`
  non opzionale il decode dell'intera risposta falliva, mascherando tutto come generico "richiesta
  fallita". Ora il tetto è **512** (è un massimale, non una spesa: i modelli normali si fermano al
  nome) e `content` è opzionale, con log dedicato che cita il `finish_reason`. I messaggi d'errore
  del client sono `privacy: .public` (sono stringhe di URLSession/JSONDecoder, non payload utente):
  con la redazione di default in console si leggeva `<private>` e la diagnosi andava fatta a mano
  con `curl`.
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
- Shortcut numerici (Cmd/Option + 1..9): gestiti da un `NSEvent` local monitor in
  `AppController`, non dai keyEquivalent di menu. Motivo: i menu con solo Option non matchano (il
  carattere è trasformato, es. Option+1 = "¡"). Le voci numerate del menu "Go" mostrano i **nomi
  reali** di workspace e tab, ripopolate all'apertura (`menuNeedsUpdate` in `AppControllerMenus`:
  il menu si ricostruisce solo al cambio keybinding, quindi non possono essere statiche).
  **Cmd+N segue l'ordine visivo della sidebar** (`orderedWorkspaces`), non quello canonico:
  Cmd+1 apre sempre la riga in cima anche col float dei completati; Option+N naviga la strip del
  pane focused.
- Shortcut rimappabili: **tutte** le azioni rimappabili passano dallo **stesso** local monitor.
  Il monitor converte l'evento in `KeyCombo` (`KeyEventBridge`) e cerca l'azione in
  `settings.keybindings`, poi `perform(action)` (`ShortcutRuntime`). Le voci di menu portano la
  combo come **keyEquivalent vero** (colonna nativa delle scorciatoie), ma il trigger resta il
  monitor, che consuma l'evento **prima** che arrivi al menu: niente doppio trigger. Quando il
  monitor si fa da parte (dashboard/onboarding aperti) i keyEquivalent tornerebbero vivi:
  `validateMenuItem` (`AppControllerMenus`) disabilita lì tutte le voci dell'AppController tranne
  il toggle della dashboard, e a overlay chiuso disabilita le azioni no-op (pane senza split,
  move con una tab sola). Il menu si ricostruisce al cambio binding (`observeKeybindings`).
  Fissi: Copy/Paste/Select All (responder SwiftTerm), Quit, Settings, Hide/Minimize/Full Screen
  (in `KeyCombo.systemReserved`: il recorder li rifiuta) e i select 1..9. Il recorder in
  impostazioni alza `settings.isCapturingShortcut` e consuma ogni keyDown nel suo monitor: né il
  monitor di navigazione né i keyEquivalent vedono la combo. Default e conflitti in `AppSettings`.
- Agent binding: `RELAY_TAB_ID` (= `Tab.id`) è iniettato nell'env della surface e torna dall'hook
  come `paneId`; accanto viaggia `RELAY_RUN_ID` (`Core.RelayRunID`, nonce per processo), che torna
  come `runId` e identifica la **run** dell'app che ha creato la surface (vedi fence di run sotto).
  Il socket è `~/.relay/relay.sock` (override `RELAY_SOCKET`); un socket stantio
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
  dell'ultimo applicato per tab). In più una **soglia anti-stantio** (`WorkspaceStore.eventFloor`,
  timbrata all'avvio dal composition root): scarta ogni evento con timestamp anteriore all'avvio,
  perché non può appartenere a una surface di questa run - è un `SessionEnd`/hook orfano di una
  sessione morta che, col `RELAY_TAB_ID` stabile tra i riavvii, azzererebbe un resume binding
  appena ripristinato (sopprimendo la proposta di resume: era la causa della `ResumeBar` che non
  compariva sempre al riavvio). Il floor però ferma solo gli hook **eseguiti** prima del boot: un
  claude orfano sopravvissuto al riavvio (SIGHUP ignorato, o un `SessionEnd` morente che scavalca
  un relaunch rapido) manda hook con timestamp fresco che passerebbero. Li ferma il **fence di
  run** (`WorkspaceStore.runID` = `RELAY_RUN_ID`): `applyAgentState` scarta gli eventi il cui
  `runId` non è quello della run corrente (compresi i nil), perché uno `Stop` porterebbe la tab
  fuori da `unknown` (barra soppressa a binding intatto) e un `SessionEnd` azzererebbe il binding.
  Alla chiusura, `applicationWillTerminate` ferma il receiver **prima** del flush del layout: i
  `SessionEnd` delle sessioni morenti sono della run corrente e passerebbero il fence proprio
  nello snapshot finale. Il wire codifica le date ISO 8601 **con millisecondi**
  (decode tollerante col vecchio formato a secondi interi e con eventi senza `runId`); un'app
  vecchia però non decodifica gli eventi di un CLI nuovo, e un CLI vecchio (niente `runId`) viene
  scartato dal fence di un'app nuova: dopo un cambio al wire ricompila/reinstalla entrambi.
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
- Cwd di `Cmd+T`: non fidarti dell'OSC 7 da solo. Conseguenza del gotcha sopra: `/etc/zshrc` carica
  l'integrazione da `/etc/zshrc_$TERM_PROGRAM`, e noi non settiamo `TERM_PROGRAM`, quindi **zsh in
  Relay non emette OSC 7** (la shell senza integrazione è il caso di default, non un caso limite); e
  quando arriva è comunque ferma all'ultimo prompt. La precedenza è **shell viva
  (`TerminalSurfaceHandle.currentDirectory()`, `proc_pidinfo`) -> ultimo OSC 7 noto
  (`Tab.currentDirectory`) -> root del workspace**, decisa dal puro `Core.CurrentDirectory` (testato)
  e applicata in `WorkspaceAreaController.currentDirectory(for:)`. Non invertirla: col valore
  memorizzato davanti, la lettura live non viene mai consultata (dopo il primo `Cmd+T` la tab ha
  sempre una cwd nota) e l'ereditarietà torna cieca ai `cd`. E non memoizzare il risultato su
  `Tab.currentDirectory`: quel campo è l'ultimo OSC 7 noto e alimenta anche titolo, sottotitolo e
  snapshot, che si congelerebbero alla cwd dell'ultimo `Cmd+T`.
- Testo da `Option`/AltGr: sui layout internazionali `Option` è anche composizione di testo
 (`Option+ò` = `@`, `Option+digit` = simboli). `Core.KeyboardTextInput` è la policy unica: se
 macOS produce testo stampabile da `Option` senza `Cmd/Ctrl`, quel testo vince sulle shortcut.
 Il monitor delle shortcut lo lascia passare e `OptionTextInterceptor` chiama
 `RelayTerminalView.handleOptionText`, che lo scrive UTF-8 nel PTY prima che il kitty keyboard
 protocol lo codifichi come tasto modificato. **Eccezione: `Option+1..9` (senza Shift) è il
 select-tab fisso e vince sempre sul testo** - il simbolo che il layout comporrebbe (es.
 `Option+1` = `«` sull'italiano) non è digitabile; l'eccezione sta dentro la policy, così monitor,
 surface e recorder restano coerenti senza dipendere dall'ordine dei local monitor. Il recorder
 rifiuta le combo che digitano caratteri sul layout attivo (e `⌘/⌥ 1..9` come `fixedSelect`).
- Selezione durante l'output: di suo SwiftTerm azzera la selezione a **ogni** feed
  (`feedPrepare`), quindi con uno spinner attivo (`railway login`, `npm install`) copiare era
  impossibile. `RelayTerminalView.dataReceived` sincronizza `allowMouseReporting` con lo stato
  reale del mouse tracking (`terminal.mouseMode != .off`, la guardia proposta in SwiftTerm#560):
  con mouse mode spento la selezione sopravvive all'output, con mouse mode attivo (es. Claude
  Code) resta dell'app come prima. Due guardie in più perché le coordinate della selezione sono
  assolute e SwiftTerm non le compensa: la selezione si azzera se lo scrollback **trimma**
  (`totalLinesTrimmed`) o al cambio di buffer primary/alternate (`bufferActivated`), altrimenti
  Cmd+C copierebbe righe mai evidenziate. Semantica bloccata da `SelectionPersistenceTests`
  (passano dal percorso pty vero, `dataReceived`): se un bump di SwiftTerm cambia le regole
  sotto, i test diventano rossi invece di rompersi in silenzio. Quando la #560 (o equivalente)
  verrà mergiata, il toggle diventa ridondante e cancellabile.
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
- **Finestre di servizio SwiftUI (Settings/About/Runtime Stats): sempre da `makePanelWindow`**
  (`PanelWindow.swift`), mai `NSWindow(contentViewController: NSHostingController)` +
  `preferredContentSize`. Con la safe area attiva, ogni `setFrameSize` fa reinvalidare a
  `NSHostingView` i suoi safe area insets, che chiede un altro "update constraints pass", che
  ridimensiona la finestra: superati i pass rispetto al numero di view, AppKit **abortisce**
  (`NSGenericException`, "more Update Constraints passes than there are views"). `makePanelWindow`
  monta una `NSHostingView` con `safeAreaRegions = []` come `contentView` e fissa la dimensione.
  Nella stessa famiglia: `NSWindow.applyRelayChrome` è **idempotente** e confronta l'appearance per
  **nome** (`NSAppearance(named:)` non torna istanze condivise, quindi `!==` è sempre vero).
  Riassegnare appearance/sfondo identici consuma pass e porta allo stesso abort.
- Drag finestra: **non** `isMovableByWindowBackground` (trascinerebbe anche il terminale). Le due
  strip in alto (`ContextTitleBar` nel right pane, `trafficLightsStrip` nella sidebar) usano
  `WindowDragArea` (NSView pura con `performDrag` + doppio click = zoom secondo la preferenza
  macOS). NSView pura, non un gesture SwiftUI: `mouseDownCanMoveWindow` non si propaga in modo
  affidabile sotto hosting SwiftUI.
- Find/Clear/Jump: `Cmd+F` (find bar flottante sul terminale), `Cmd+K` (clear = `ESC[3J` + Ctrl+L
  al pty), `Cmd+J` (`WorkspaceStore.focusNextAttention`, ciclico sull'ordine visivo). Sono **azioni
  rimappabili** (`ShortcutAction.find/findNext/findPrevious/clear/nextAttention`), quindi passano
  dallo **stesso local monitor** delle altre, non da keyEquivalent di menu; il monitor consuma
  l'evento anche col terminale in focus. Search/clear passano dal protocollo `TerminalSurfaceHandle`
  (niente tipi SwiftTerm fuori dall'engine).
- Ricerca (Cmd+F) - due metà **coerenti per opzioni ma con sorgenti diverse**: (1) **navigazione,
  contatore e match corrente** li fa il motore di SwiftTerm (`findNext`/`findPrevious`/
  `searchMatchSummary`), autorevole su **tutto** il buffer, col match corrente evidenziato dalla
  **selezione nativa** (colore selezione del tema); (2) **l'evidenziazione di tutti i match** la
  disegna Relay perché SwiftTerm **non espone le posizioni dei match** (`findAll` è internal). È una
  **subview** (`SearchHighlightOverlay`, in `RelayTerminalView+Search`), non un override di `draw`
  (SwiftTerm dichiara `draw` `public`, non `open`); legge la sola **viewport** (`getLine`), cerca col
  matcher puro `Core.TerminalSearchMatcher` (case/word/regex, testato) e mappa gli indici di
  carattere alle **colonne-cella** (celle wide comprese). Geometria allineata al `draw` nativo: view
  non flipped, righe ancorate a `bounds.maxY`, **cella esatta da `caretFrame.size`** (non
  `cellSizeInPixels`, arrotondato). Si riallinea su output (`dataReceived`), scroll (`scrolled`) e
  resize (`setFrameSize`) - questi tre override stanno nel **corpo** della classe, non in extension.
  **Limite noto**: `isWrapped` è internal in SwiftTerm, quindi l'overlay cerca riga fisica per riga
  (niente unione dei blocchi wrapped): un match esattamente a cavallo di un a-capo automatico non
  viene evidenziato (il contatore/navigazione, che vedono il wrap, lo trovano comunque). Cercare per
  riga fisica evita i falsi positivi da righe concatenate. **Scrollback 10k** (`changeHistorySize` in
  `SwiftTermSurface.start`, non 500 di default: la ricerca deve vedere lo storico di una sessione
  agente). **Robustezza streaming**: a ricerca attiva `allowMouseReporting` è forzato **spento**
  (`setSearchState` + `dataReceived`), così `feedPrepare` non azzera la selezione a ogni feed e la
  posizione da cui `findNext` riparte sopravvive all'output (senza, con un agente che streamma Invio
  tornava sempre al primo match). **Stato legato alla tab**: la find bar ricorda la tab su cui è
  aperta (`RightPaneController.findTabID`) e opera su **quella** anche se il focus si sposta;
  `observeFindTarget` la chiude se la tab focused cambia (niente find bar orfana col contatore
  stantio). `Cmd+F` a barra aperta **rifocalizza** il campo (`FindModel.requestFocus`), non chiude
  (chiude Esc/x). Colore evidenziazione dal giallo ANSI del tema (`ansiColor(3)`, coerente con
  badge/ring).
- Ring di attenzione (`AttentionRingView`): bordo colorato attorno al terminale della tab in vista
  che ne segnala lo stato (verde = completato non visto, statico + flash; giallo/rosso pulsante =
  aspetta input/errore). Il ring risponde solo a `unseen`: un sospeso (`pending`) non accende il
  bordo (segnale quieto: badge ad anello vuoto + dashboard), altrimenti useresti la shell con un
  ring verde permanente. Colori dai colori ANSI del tema, coerenti coi badge. Overlay con `hitTest`
  nil (non intercetta eventi); i terminali si inseriscono `positioned: .below` così resta in cima.
  L'observer del ring (`observeRing`) è **separato** da `render()` e **non** scrive `attention`:
  altrimenti un completamento sulla tab in vista si spegnerebbe da solo (loop col reset della
  visita). Il declassamento (mark-read) lo fa solo l'interazione col terminale (monitor key/mouse).
- Onboarding: overlay full-window come la dashboard (`AppControllerOnboarding`, wiring identico a
  `AppControllerDashboard`), al primo avvio (`AppSettings.onboardingSeen`, timbrato alla
  presentazione; mai in demo mode) e da Help > Welcome to Relay. Mentre è aperto il monitor si fa
  da parte (`isOnboardingOpen`, i tasti vanno alla vista: frecce/Invio/Esc via `.focusable` +
  first responder deferito). Un solo overlay full-window alla volta: aprire l'uno chiude l'altro
  (`presentOnboarding`/`openDashboard` si chiudono a vicenda, altrimenti gli host resterebbero
  incoerenti). Niente screenshot nelle pagine: componenti veri (`AgentBadge`, keycap dai binding
  correnti, `ThemeSwatch` che seleziona il tema dal vivo, `RelayMarkView` = icona ridisegnata in
  SwiftUI con la geometria di `bundle/make-icon.swift`, usata anche da About - da dev build
  `NSApp.applicationIconImage` darebbe l'icona generica).
- Overlay full-window e hit-testing: `presentFullOverlay` avvolge l'overlay in un
  `FullOverlayContainerView` il cui `hitTest` non torna mai `nil` dentro i bounds e consuma il
  mouse nelle zone senza contenuto hit-testable; senza, mouse e cursor update cadevano sul
  terminale sotto (selezione di testo con l'overlay aperto). Le cursor rects della finestra sono
  disattivate finché l'overlay è su (`disableCursorRects`): quelle di SwiftTerm
  (`addCursorRect(bounds, .iBeam)`) non rispettano l'occlusione e terrebbero l'I-beam sopra
  l'overlay.
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
  & drop" sotto), non `onMove`. La sidebar itera `store.orderedWorkspaces` (solo i pinned salgono in
  testa, il resto è l'ordine **canonico** di `store.workspaces`: niente float derivato). L'ordine
  canonico è quello vero e persistente, mutato dal drag **e** dal bump di attività
  (`bumpWorkspaceToTop`); `orderedWorkspaces` è display-only (proietta i pinned). Rename inline del
  workspace dal menu contestuale (`WorkspaceStore.renameWorkspace`).
- Archive: i workspace archiviati (`Workspace.archived`, persistito, additivo) escono da
  `orderedWorkspaces` e vivono in una sezione collassabile ancorata **in fondo** alla sidebar
  (`archiveSection`, header **sempre presente** anche a zero archiviati = drop zone e affordance
  permanente; il conteggio accanto a "Archive" compare solo se > 0; aperta e vuota mostra un empty
  state discreto "No archived workspaces"; lista archiviati con tetto ~metà sidebar,
  poi scroll interno; espansa/collassata in `AppSettings.archiveExpanded`). L'altezza del contenuto
  si misura con **`onGeometryChange` sul contenuto dentro lo ScrollView, mai con una preference**:
  su macOS le preference non attraversano il confine dello `ScrollView` (bridge NSScrollView) - a
  `onPreferenceChange` fuori arrivava solo lo 0 iniziale e la lista restava alta 1px (freccia sì,
  contenuto no: il bug dell'archivio che "non si apriva"). La lista è un **`VStack`, non
  `LazyVStack`**: dentro lo `ScrollView` alto `min(archivedHeight, ...)` che parte da 1px, il lazy
  non realizzerebbe le righe e la misura resterebbe 0.
  L'header è ancorato, non nel flusso scrollabile, perché su macOS
  lo `ScrollView` non fa drag-scroll: sotto la piega non ci potresti trascinare sopra. `archived`
  è mutuamente esclusivo con `pinned` (archiviare de-pinna) e col float (gli archiviati non
  galleggiano). `setArchived`/`toggleArchive`: non archivia l'ultimo visibile e sposta la selezione
  fuori dall'archiviato; un archiviato con attenzione fresca accende un pallino discreto
  sull'header (non un buco nero). Archivia/ripristina dal menu contestuale (`Archive`/`Unarchive`).
- Riordino drag & drop (sidebar e strip dei pane): meccanismo in `Panels/Reorderable` (`reorderableRow` +
  `reorderableContainer` + `ReorderInsertionLine`). **Non** `onDrag`/`onDrop` di sistema (generano
  una preview con snap-back al rilascio): la riga *vera* si solleva con un `DragGesture` + `.offset`
  (semitrasparente, zIndex alto) seguendo il puntatore, una linea segnala l'inserimento, e al
  rilascio lo scambio parte in `withAnimation` mentre l'offset torna a zero (nessun salto).
  L'indice di inserimento viene dal **centro proiettato della riga in volo** (frame originale +
  traslazione), **non** dal puntatore grezzo: così la linea segue il corpo della riga ed è
  **indipendente dal punto di presa** (afferrarla in cima o in fondo dà lo stesso risultato; col
  puntatore la decisione sfasava di quanto eri lontano dal suo centro). I frame
  di layout li raccoglie un `PreferenceKey` in un coordinate space nominato, misurato **dopo**
  l'`.offset` del drag (dentro `reorderableRow`, mai con un GeometryReader sotto l'offset):
  l'offset è un GeometryEffect e si propaga alla geometria dei discendenti anche nello space
  nominato - con la misura dentro, il frame della riga in volo seguiva il gesto, il centro
  proiettato raddoppiava la traslazione e la linea di inserimento derivava proporzionalmente alla
  distanza (il bug del drop impreciso). Lo stato del gesto (`ReorderDragState`) vive in un **`@GestureState`** con
  `resetTransaction` animata: si azzera da solo anche a gesto annullato (menu contestuale, perdita
  focus) - con `@State` manuale un drag interrotto lasciava la riga sollevata e rompeva i drag
  successivi. Store puro e posizionale: `WorkspaceStore.moveWorkspace(_:before:/after:)` e
  `moveTab(_:before:in:)` (inserisce prima/dopo il target, `nil` = in fondo). **Sidebar**: la linea
  è libera (niente clamp: col vecchio vincolo di segmento un blocco da 1 elemento inchiodava
  l'inserimento = drag morto); il drag edita direttamente l'ordine canonico e il drop lo risolve il
  resolver puro `SidebarDrop` (testato, due segmenti pinned/resto): attraversare il blocco pinned
  pinna/spinna (il bordo esatto non cambia lo stato), l'ancora preferisce il vicino dello stesso
  segmento e ripiega sul vicino grezzo. Durante il gesto l'ordine visivo è **congelato**
  (`frozenOrder`): senza, un evento agente che bumpa un workspace riordinerebbe le righe sotto il
  puntatore. **Strip dei pane**: nessun segmento, ordine unico, il riordino resta **dentro** la
  strip (`Workspace.moveTab` è no-op cross-pane: il drag di tab fra pane è lavoro futuro). Su
  macOS lo `ScrollView` non fa drag-scroll, quindi il `DragGesture` non confligge con lo scroll;
  niente pasteboard, niente drop incrociati.
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
  solo dai campi persistiti. La gran parte degli eventi agente non scatena scritture; un **bump**
  però riordina `workspaces` (campo persistito), quindi un'attività non vista **sì** (l'ordine è
  dato utente da salvare) - assorbito dal debounce, non a raffica. **Demo mode non
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
  upgrade. La validità è pura (`isValidForPersistence`, testata). **Downgrade**: la compat del
  layout è solo all'indietro - dal primo save post-split-v2 il file è in formato pane e un binario
  <= 0.8.2 non lo decodifica (dal secondo save nemmeno il `.bak`): un downgrade riparte dal seed.
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
- Cap LRU surface: `SurfaceRegistry.enforceLRU` è un **soft cap**. Sfratta le meno recenti **solo se
  idle** (`hasRunningChildren == false`: shell senza figli, copre foreground/background/agente) e
  non protette: mai la visibile, le tab del workspace attivo, le tab con attenzione fresca
  (`needs_input`/`error`/`unseen`) o quelle usate negli ultimi ~30 minuti. Eviction = teardown
  SwiftTerm (scrollback perso, shell ricreata alla cwd al re-focus). Cap in
  `WorkspaceAreaController` (12, knob `RELAY_SURFACE_CAP`). Se cambi il criterio, tienilo
  conservativo: meglio sforare il cap che resettare contesto utile o uccidere un processo.
- Resume Claude: `ResumeBinding` (agent/sessionId/label) catturato in `applyAgentState` (viva) e
  azzerato su `unknown`, persistito nel `TabSnapshot`. Al primo focus di una tab `pendingResume`
  (binding + `agentState==unknown`) `RightPaneController` overlaya `ResumeBar` sul terminale;
  `Resume` -> `surface.sendText("claude --resume <id>\n")`. Setting `autoResumeAgents` (default off)
  inietta da solo. **Il wiring della barra vive nel composition root (RelayApp), non in
  TerminalHostUI**: il path caldo non dipende da Panels. Il resume è **lazy** (al focus), mai in
  massa al boot.
- Dashboard (`Cmd+D`, azione rimappabile `toggleDashboard`): overlay full-window
  (`RootOverlayController.presentFullOverlay`, wiring in `AppControllerDashboard`). **Due viste**
  scambiabili da un toggle in header (preferenza persistita `AppSettings.dashboardLayout`, default
  **kanban**): kanban per stato su quattro corsie di triage (Needs You = needs_input/error, Running,
  Done = completati non visti, Idle = pending/idle/resume) e la **griglia flat** storica per
  urgenza. **Il pannello è identico nelle due viste** (stessa barra di ricerca, stessa dimensione
  fissa; le colonne kanban sono flessibili, il toggle scambia solo il contenuto - non ridimensiona).
  Card con età e dismiss, filtro type-to-search, frecce + Invio (nav flat nella griglia, 2D nel
  kanban), Esc chiude. Logica pura in `Panels/DashboardModel` (raggruppamento `Lane`/`Column`/
  `columns` testato); rendering board + `SessionCard` in `Dashboard+Board.swift` (estratti dal
  corpo di `DashboardView` per i limiti file/tipo). Solo dati del model, funziona anche per tab
  sfrattate dal cap LRU (niente preview del terminale: richiederebbe surface vive). **Mentre è
  aperta il monitor si fa da parte**: i tasti vanno al filtro (niente nav 1..9, niente mark-read),
  resta attivo solo il toggle per chiuderla; Esc lo gestisce la vista (`onExitCommand`). La
  decadenza dei sospesi si applica a boot/foreground/apertura dashboard (niente timer). Il set
  differito del first responder in `FullOverlayPresenter` **non ruba** il focus al campo che l'ha
  già preso via `@FocusState` (salta se il first responder è già un discendente dell'host).
- Sposta tab in nuovo workspace ("Move to New Workspace", menu contestuale della tab, visibile
  solo con **>=2 tab**): `WorkspaceStore.moveTabToNewWorkspace` sposta lo **stesso** oggetto `Tab`
  (stesso `Tab.id`), così la surface legata per id resta **viva** - niente teardown del pty, il
  lavoro dentro la tab non si tocca. L'append del nuovo workspace e il `removeTab` dall'origine
  avvengono nella **stessa mutazione sincrona**: la tab è sempre presente in `store.workspaces` a
  ogni istante osservabile, quindi il reconcile delle surface (`retain` su tutti gli id, vedi
  TerminalHostUI) non la sfratta mai. Il nuovo workspace eredita la cwd della tab come `rootPath`,
  nasce `.default` (eleggibile alla nomina automatica: il nome è un placeholder) e diventa il
  selezionato con la tab spostata attiva. **No-op se la tab è l'unica del suo workspace**
  (svuoterebbe l'origine) o se l'id non esiste lì. Il nome placeholder ("Workspace N") lo assegna
  il composition root (`AppController.moveTabToNewWorkspace`), non lo store, come per `newWorkspace`.
- CI deterministica: gli strumenti di lint sono **pinnati** (SwiftFormat/SwiftLint, versioni nel
  Makefile), scaricati come binari dai release GitHub in `.build/tools` da `make tools` (uno stamp
  versionato forza il riscarico al bump). `make lint`/`format`/`check` li usano; il workflow CI non
  fa più `brew install` (prendeva l'ultima: una regola nuova upstream rompeva il lint su codice
  invariato, la causa della CI rossa da 0.7.0). CI e locale girano la stessa identica versione.
- **Split panes (modello cmux, v2)**: i **pane ospitano le tab**. L'albero (`Workspace.layout`,
  **sempre presente**) ha foglie `SplitPane` = {id, tabIDs ordinate, selectedTabID}; ogni pane ha
  la **sua strip** (`Panels/PaneTabBar`, montata dentro la `PaneView` via factory
  `makePaneStrip` iniettata dal composition root: TerminalHostUI non dipende da Panels) con
  action lane a destra (nuova tab, split right/down). La tab bar globale non esiste più. La Tab
  resta l'unità della sessione agente. Due nozioni **distinte**: **visibile** (`isVisible`,
  selezionata nella sua strip -> ring, mark-read, protezione LRU, soppressione di notifica/bump)
  vs **focused** (`focusedPaneID` + la sua selezione = `selectedTabID`, ora **derivato**). Ogni
  "seleziona questa tab" passa da `reveal` (seleziona nel suo pane + focus al pane): selezionare
  **non muta mai la struttura**. Il design "foglie = Tab.id" (v1) e ogni sua semantica
  (monta/smonta, replacing) sono superati; il Codable di `SplitNode` decodifica ancora il formato
  v1 (le tab fuori dall'albero vengono **adottate** al restore, vedi `Workspace.init`).
  Invarianti: una tab sta in un pane solo, ogni pane ha >= 1 tab (`sanitized` li ripristina).
  `closePane` (⌥⌘W, action lane, menu) **chiude il pane con le sue tab** (sessioni comprese,
  conferma sui processi in foreground): nel nuovo modello non c'è un posto fuori dai pane. "Open
  in Split Right/Down" (menu della tab) **sposta** la tab esistente in un pane nuovo accanto al
  suo; no-op se è l'unica della sua strip. `Cmd+W` chiude la tab selezionata del pane focused
  (selezione index-stable tipo browser); `Opt+1..9` e Ctrl+Tab navigano **la strip del pane
  focused**. **Click-to-focus**: un click nel terminale di un pane aggiorna il focus del model
  (monitor -> `owningPane` -> `focusPane`), non solo il first responder AppKit. Il rendering
  (`WorkspaceAreaController+PaneTree`) riusa le `PaneView` per **`SplitPane.id`** e ricostruisce
  solo se cambia la **struttura** (`hasSameStructure` ignora ratio E contenuto dei pane): un
  cambio di selezione **scambia solo il terminale attaccato** (`attachTerminal`, le surface
  restano nella registry per `Tab.id`). Il first responder si prende quando cambia la coppia
  (pane focused, sua tab) **o dopo ogni rebuild** (staccare le view resetta il responder). Ratio:
  write-back nello store **solo con mouse premuto** (i layout pass programmatici del boot
  stomperebbero il ratio persistito con un 50/50) e riapplicazione in `viewDidLayout` al primo
  layout con dimensioni vere.
- **Ciclo di vita di una finestra (due trappole, pagate con un crash)**: (1) `isReleasedWhenClosed`
  è **`true` di default** sulle `NSWindow` costruite a mano, e la finestra è già posseduta dal suo
  `RelayWindowController` (`let window`): il release extra di AppKit alla chiusura la manda sotto
  zero e il pop dell'autorelease pool fa `objc_release` su memoria morta (SIGSEGV). Va spento in
  `RelayWindowController.init`, come già in `PanelWindow`. Sulla finestra **principale** non si
  vedeva (chiuderla termina l'app): il crash arrivava solo chiudendo una **secondaria**.
  (2) Il teardown del controller è **differito di un giro di runloop** (`windowDidClose`): siamo
  dentro `windowWillClose`, e il controller *è* il delegate della finestra oltre a possederla -
  rilasciarlo lì dealloca finestra e delegate mentre AppKit li sta ancora usando. Il delegate si
  stacca subito, il rilascio va su `DispatchQueue.main.async`.
- **Multi-window**: le finestre **partizionano** i workspace (`Workspace.windowID` + `RelayWindow`
  con la **sua** `selectedWorkspaceID`); lo store, il `layout.json`, il receiver e la
  **`SurfaceRegistry` restano unici** (una tab ha una surface sola ovunque sia montata). Nessuna
  finestra è privilegiata: chiuderne una **rimpatria** i suoi workspace in quella attivata più di
  recente (`closeWindow`), l'ultima chiude l'app. `store.selectedWorkspaceID` è una **proiezione**
  della finestra key, così menu e scorciatoie non sanno nulla di finestre. **`isVisible` si lega alla
  finestra non occlusa (`NSWindow.occlusionState`), NON alla key**: con due monitor la finestra che
  fissi spesso non ha il focus, e notificarla sarebbe il bug del caso d'uso. Il monitor chiede il
  pane a **quella da cui l'evento arriva** (`windowController(for:)`), non alla key. Alla
  terminazione il rimpatrio è **sospeso** (`isTerminating`): macOS chiude le finestre una per una, e
  rimpatriare a ogni passaggio collasserebbe il layout multi-window prima del flush. I frame stanno
  nel `LayoutSnapshot` per id (`setFrameAutosaveName` ne gestirebbe una sola).
- Non ancora fatto: distribuzione firmata Developer ID, generalizzazione multi-agente
  (Codex/opencode), drag di workspace **fra** finestre, drag di tab **fra** pane (incluso
  l'edge-drop stile bonsplit per creare split trascinando), zoom del pane, rename del workspace
  dalla menu bar (resta nel contestuale della sidebar).
