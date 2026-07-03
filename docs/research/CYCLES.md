# Cycles

Questo file traccia i cicli di lavoro e le decisioni prese durante l'analisi del terminale
agent-aware.

## Cycle 0 - Analisi Repo E Direzione

Data: 2026-07-02
Stato: completato

### Obiettivo

Capire se usare `manaflow-ai/cmux` come base, partire da Ghostty/libghostty, oppure valutare
alternative come iTerm2, Alacritty, WezTerm, Kitty, Rio, Contour, Tabby e xterm.js.

### Attività

- Clonati localmente i repo candidati in `terminal-agent-analysis/repos`.
- Analizzato `cmux` come prodotto, architettura e build.
- Analizzati engine embeddabili e terminali forkabili.
- Studiati Otty e hook Claude Code.
- Eseguito primo spike di build `cmux`.

### Evidenze

- `cmux` ha feature match molto alto, ma è un prodotto completo e ampio: Swift/AppKit,
  GhosttyKit, CLI monolitica, browser/webviews, iOS, cloud/presence, remote daemon, molti
  agent hooks.
- `cmux` non è ideale come fork diretto per una app snella.
- `libghostty` / `GhosttyKit` è il miglior candidato per nuova app macOS nativa.
- `xterm.js` è ottimo per prototipi web/Electron, ma non rispetta il target di app nativa.
- `iTerm2` e `WezTerm` sono reference utili per automazione/status/mux, non basi primarie.

### Build Spike

Submodule `cmux` inizializzati:

- `ghostty` -> `541e5e8`
- `homebrew-cmux` -> `a5f372e`
- `vendor/bonsplit` -> `01751ef`

Blocker trovati:

- `zig` mancante;
- `bun` mancante;
- Xcode/CoreSimulator incompleto, `xcodebuild` suggerisce `xcodebuild -runFirstLaunch`.

### Decisioni

- Non forkare `cmux` intero come base primaria.
- Procedere verso nuova app macOS nativa.
- Usare `cmux` come reference architetturale e di prodotto.
- Usare Otty come reference comportamentale per agent states.

### Artifact

- `REPORT.md`
- canvas Cursor `terminal-agent-analysis.canvas.tsx`

## Cycle 1 - Agent State Hooks

Data: 2026-07-02
Stato: completato

### Obiettivo

Capire se possiamo replicare la qualità degli stati Otty senza avere il codice Otty open
source.

### Attività

- Letto `~/.claude/settings.json`.
- Letto script Otty:
  - `/Applications/Otty.app/Contents/Resources/agent-integration/claude/otty-hook.sh`
- Mappati hook Claude Code in stati agent.
- Creato spike `spikes/ourterm-spike`.
- Installati i nostri hook in parallelo a quelli Otty.
- Validato flusso reale e simulato.

### Mapping Confermato

| Claude event | State |
| --- | --- |
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `processing` |
| `PreToolUse` | `processing` |
| `PostToolUse` | `processing` |
| `PermissionRequest` | `awaiting` |
| `Stop` | `idle` |

### Implementazione Spike

File creati:

- `spikes/ourterm-spike/bin/ourterm-state.py`
- `spikes/ourterm-spike/bin/ourterm-state-log.py`
- `spikes/ourterm-spike/bin/ourterm-claude-hook.sh`
- `spikes/ourterm-spike/docs/ARCHITECTURE.md`
- `spikes/ourterm-spike/docs/CLAUDE_HOOKS_SNIPPET.json`
- `spikes/ourterm-spike/README.md`

Funzioni disponibili:

- `ourterm-state.py state:claude ...`
- `ourterm-state.py dump`
- `ourterm-state.py timeline <session-id>`

Output runtime:

- `spikes/ourterm-spike/state/agent-states.json`
- `spikes/ourterm-spike/state/agent-state-events.jsonl`

### Validazioni

- Config `~/.claude/settings.json` valida dopo modifica.
- Hook nostri installati in parallelo a Otty, non in sostituzione.
- Backup creato:
  - `/Users/doppia/.claude/settings.backup-ourterm-20260702-1043.json`
- Simulata sequenza: `processing`, `awaiting`, `idle`.
- Ricevuti eventi da sessioni Claude reali.

### Decisioni

- Gli hook Claude Code sono fonte autorevole degli agent states.
- Le euristiche su output terminale non devono guidare gli stati agente.
- OSC e shell integration restano utili solo per comandi generici.
- Il protocollo futuro deve separare `agent state` e `shell command state`.

### Rischi Residui

- Bisogna legare `sessionId` al pane corretto nella futura app.
- `PermissionRequest` porta contesto base64: va sanitizzato e gestito con retention breve.
- `Stop` segnala idle, ma bisogna distinguere completamento utile, sessione pronta e
  notification noise.
- Subagent events non devono generare falsi completed sul pane principale.

## Cycle 2 - Architecture Documentation

Data: 2026-07-02
Stato: completato

### Obiettivo

Separare roadmap, architettura e log cicli per rendere il progetto continuabile senza
dipendere dalla chat.

### Attività

- Creato `ROADMAP.md`.
- Creato `CYCLES.md`.
- Creato `ARCHITECTURE.md`.

### Decisioni Documentate

- App nuova, nativa macOS.
- Engine primario: `libghostty` / `GhosttyKit`.
- Agent runtime basato su hook e IPC locale.
- UI snella con tab verticali, split e sidebar.
- Fuori prodotto baseline: browser, cloud, iOS, remote tmux, skill marketplace, hibernation,
  orchestrazione multi-agent complessa.

## Cycle 3 - Diagnosi Lag cmux E Tesi Di Prodotto

Data: 2026-07-02
Stato: completato

### Obiettivo

Capire perché cmux lagga con molti workspace (anche su hardware recente) e chiarire il motivo
per costruire una nuova app invece di usare Otty o cmux.

### Tesi Di Prodotto Chiarita

- Otty ha gli stati agente giusti ma non ha workspace che raggruppano tab.
- cmux ha i workspace ma lagga e cresce in direzioni non richieste (browser, cloud, iOS).
- Il prodotto è: organizzare e sorvegliare molti progetti/agenti da un posto solo, con
  sidebar drag/pin e dashboard overview. Il terminale è il substrato.

### Evidenze (analisi codice `repos/cmux`)

- `Sources/BackgroundWorkspacePrimeCoordinator.swift`: priming eager dei workspace in
  background, attende `surfaceReady` per ciascuno. Con molti workspace = molte surface vive.
- `Sources/AppDelegate+PaneMemoryGuardrail.swift`, `Sources/AgentHibernation/`, discard delle
  webview sotto memory pressure: mitigazioni a valle di un design che sovra-alloca.
- `Sources/GhosttyTerminalView.swift`: policy di occlusione/visibilità
  (`setRendererPortalVisible`, `setOcclusion`) aggiunte a posteriori.
- `Sources/ContentView.swift` 16.484 righe, `GhosttyTerminalView.swift` 12.212,
  `Workspace.swift` 13.071; 140 file importano SwiftUI: view tree monolitico, invalidazioni
  larghe durante typing e aggiornamenti sidebar.

### Conclusioni

- Il lag di cmux è architetturale (eager allocation + SwiftUI monolitico), non dell'engine:
  GhosttyKit è con ogni probabilità sano.
- Il vantaggio "veloce" della nostra app non è gratis: è disciplina architetturale.

### Decisioni

- Lifecycle surface lazy: PTY/VT/renderer nascono al primo focus, mai priming in background.
- Budget renderer LRU: vivi solo i visibili + pochi recenti; PTY/VT dei pane nascosti restano
  vivi (gli agenti continuano), si rilascia solo il renderer.
- Scrollback cappato per surface.
- Sidebar/dashboard disaccoppiate dal view tree del terminale (AppKit per il path caldo,
  SwiftUI solo in pannelli isolati).
- Limite indicativo 500 righe per file.
- Architettura completa riscritta in `ARCHITECTURE.md` (tesi di prodotto, budget, data model,
  anti-pattern cmux).
- Struttura repo a monolite modulare SwiftPM con dipendenze imposte dal compilatore
  (`ARCHITECTURE.md`) e disciplina di stile/test/CI in `CONVENTIONS.md` (bozza per il repo
  app).

### Aperto

- Nome prodotto: candidato Relay, riserve per il clash con Relay di Meta (GraphQL).

## Cycle 4 - Engine Spike

Stato: completato (concluso con un pivot, vedi Cycle 5). L'obiettivo iniziale - validare
GhosttyKit da sorgente - è risultato bloccato dal toolchain (zig 0.15.2 non linka sul SDK
26.5); l'esito è la revisione della scelta engine nel Cycle 5.

### Obiettivo

Validare tecnicamente `GhosttyKit` dentro una app macOS minimale e misurare contro i budget di
`ARCHITECTURE.md`.

### Task

1. Preparare toolchain: `zig`, Xcode first launch/system content.
2. Compilare esempio Ghostty Swift/XCFramework.
3. Creare finestra macOS minimale con terminal surface.
4. Verificare input tastiera e shell locale.
5. Misurare: latenza input, tempo di realizzazione surface, memoria per surface con
   scrollback pieno.
6. Documentare scelta: `GhosttyKit` completo oppure `libghostty-vt`.

### Exit Criteria

- Surface terminale visibile e interattiva.
- Build ripetibile.
- Misure raccolte e confrontate con i budget.
- Blocker tecnici documentati.
- Decisione engine definitiva.

Timebox: 2-3 giorni, poi decisione o piano B.

### Progressi 2026-07-02 (sessione 1)

Toolchain e blocker mappati. Stato: engine binario in mano, rendering non ancora validato.

Fatto:

- Installati zig 0.15.2 e 0.16.0 in `~/.local/` (fuori repo).
- Ottenuta `GhosttyKit.xcframework` (slice `macos-arm64_x86_64` con `ghostty-internal.a` +
  Headers) via il prebuilt checksum-verificato di cmux (fork Manaflow, ghostty `541e5e8`).
  Cache in `~/.cache/cmux/ghosttykit/`.
- Risolto un blocker Xcode: `xcodebuild` era rotto (CoreSimulator.framework assente),
  sistemato con `xcodebuild -runFirstLaunch` (senza sudo). Ora xcodebuild funziona.

Blocker trovati (importanti, cambiano la strategia di build):

1. **zig 0.15.2 non linka contro il SDK macOS 26.5.** Repro minimale: anche un hello-world
   con libc fallisce con undefined symbol su `_getcwd`, `_sigaction`, `_realpath$DARWIN_EXTSN`
   ecc., pure con `--sysroot`/`-lSystem` espliciti. Formato `.tbd` del libSystem troppo nuovo
   per il linker di 0.15.2.
2. **ghostty (anche upstream main) richiede esattamente la linea zig 0.15** (`requireZig`:
   stesso major.minor, patch >= 2). L'unica 0.15.x esistente è la 0.15.2. zig 0.16.0 linka sul
   SDK 26.5 ma ghostty lo rifiuta (usa API std 0.15 + `@compileError`).
   => **ghostty non è compilabile da sorgente su questa macchina** finché upstream non passa a
   zig 0.16, oppure si installa un SDK macOS più vecchio (14/15) e si punta zig 0.15.2 lì.
3. **L'app macOS di riferimento non basta col solo xcframework.** Il bundle copia da
   `zig-out/share/` (terminfo, shell integration, temi, sintassi bat/fish/vim/nvim/man) che
   sono prodotti da `zig build`. Con il solo prebuilt quelle `CpResource` falliscono, e il link
   di `__preview.dylib` fallisce. Quindi il path "builda l'app di riferimento" dipende
   dall'intero output di `zig build`, di nuovo bloccato dal punto 1.

Implicazione architetturale: la nostra assunzione (CONVENTIONS) di buildare GhosttyKit in CI
dal sorgente non regge oggi. Opzioni per la nostra app: (a) consumare un GhosttyKit prebuilt
come fa cmux; (b) pinnare un SDK macOS più vecchio in dev/CI per usare zig 0.15.2;
(c) aspettare/forzare la migrazione ghostty a zig 0.16. Decisione da prendere.

Vie per arrivare a un rendering, ancora aperte:

- **App minimale nostra** (SwiftPM/`swiftc` + prebuilt xcframework): bypassa sia zig sia il
  bundle di risorse; usa il terminfo di sistema. È il vero deliverable di Fase 1. Costo: ore di
  embedding sulla C API; couplata all'ABI della fork Manaflow finché non risolviamo il build da
  sorgente.
- **Sblocco build da sorgente** via SDK macOS 14/15 + zig 0.15.2 su upstream pulito.
- **Sanity check rapido**: scaricare la Ghostty.app ufficiale e misurarne il feel, per validare
  che l'engine di suo sia veloce su questa macchina (non valida il nostro embedding).

## Cycle 5 - Revisione Decisione Engine (SwiftTerm)

Data: 2026-07-02
Stato: completato

### Obiettivo

Dopo il muro del Cycle 4, verificare sul web se libghostty sia davvero l'engine embeddabile
migliore da adottare "come si deve", senza workaround (prebuilt di fork, toolchain rotto).

### Evidenze (ricerca web)

- **libghostty non è ancora una libreria embeddabile stabile.** Fonte: Mitchell Hashimoto,
  "Libghostty Is Coming". È in alpha pubblica, nessuna release. Solo `libghostty-vt` (il parser
  VT, NON il rendering) è in arrivo, taggato "entro 6 mesi" e comunque solo parser. La C API
  completa con rendering (quella usata da cmux/GhosttyKit) è dichiarata dall'autore
  internal-only: "It isn't a good C API. It is internal-only." Si builda solo da sorgente con
  zig, oppure da prebuilt di terzi.
- **SwiftTerm** (migueldeicaza) è l'engine embeddabile proper disponibile oggi: puro Swift/SPM,
  toolchain standard, MIT, `TerminalView` (NSView) + `LocalProcessTerminalView` (PTY) turnkey,
  rendering CoreText con backend Metal opzionale. In produzione embedded: Secure Shellfish, La
  Terminal, CodeEdit, Pane.
- **Skwad** (app Swift/SwiftUI per agenti, caso quasi identico al nostro) usa "libghostty (GPU)
  con SwiftTerm come fallback". Anche chi punta al GPU tiene SwiftTerm come rete.

### Conclusione

Adottare libghostty oggi significa dipendere da una C API internal-only + toolchain zig (rotto
sul SDK 26.5) o da un binario di fork: è un workaround, non "farlo come si deve". SwiftTerm si
builda proper col toolchain standard ed è pensato per l'embedding.

### Decisione

- **Engine v1: SwiftTerm**, dietro l'astrazione `TerminalEngine` (interfaccia sottile: crea/
  distruggi surface, input, dimensioni/titolo/cwd, eventi output/bell/OSC).
- **libghostty: backend futuro** dietro la stessa astrazione, quando esce una C API
  embeddabile stabile con rendering (stimato 6-12 mesi).
- Tradeoff accettato: throughput di rendering (CoreText vs GPU), mitigato dal backend Metal di
  SwiftTerm, dallo scrollback cap e dal fatto che il lag vero è architetturale (Cycle 3).
- Fase 1 riparte su SwiftTerm.

### Fonti

- https://mitchellh.com/writing/libghostty-is-coming
- https://github.com/migueldeicaza/SwiftTerm
- https://rywalker.com/research/skwad
- https://github.com/Uzaaft/awesome-libghostty
- https://github.com/ghostty-org/ghostling

### Benchmark SwiftTerm (release, `spikes/swiftterm-spike/`)

Misure reali su questa macchina (M-series), non stime.

VT core (headless, solo parsing + buffer, `swiftterm-bench vt`):

| Payload | Throughput |
| --- | ---: |
| plain text | 82.5 MB/s |
| ANSI color-heavy | 34.6 MB/s |
| scroll / cursor-heavy | 55.8 MB/s |

Core RSS: 10 MB. Conclusione: il parser non è il collo di bottiglia. Gli agenti producono
KB/s-MB/s; anche un `cat` di 100 MB = ~2-3s di solo parsing.

End-to-end nella view viva (`swiftterm-bench render`, ~52 MB streaming):

- 20.2 MB/s (52 MB ingest+render+scroll in 2.6s). Ampiamente sopra i ritmi reali degli agenti.
- RSS 199 MB con 1 surface e **1M righe di scrollback** ritenute.

Memoria:

- Floor idle GUI (1 surface, shell, scrollback vuoto): 90 MB. È il baseline di processo
  (AppKit + Metal + runtime Swift + SwiftTerm), pagato una volta, condiviso tra le surface.
- Lo scrollback è la variabile: ~110 MB per 1M righe => col nostro cap a 10k righe ~1 MB. Il
  cap scrollback (già nei principi) è confermato come scelta giusta.

Aperto (richiede l'app multi-surface reale, Fase 2):

- costo incrementale per surface aggiuntiva DENTRO un solo processo (lo spike è 1 surface/
  processo, non lo misura);
- latenza input p99 contro il budget < 1 frame (serve strumentazione frame-level).

Verdetto: il rischio principale temuto (throughput CoreText) è **smentito dai dati** per il
nostro caso d'uso. Restano da chiudere latenza input e memoria a N surface, entrambe misure di
Fase 2.

## Cycle 6 - Repo Relay e V0 App

Data: 2026-07-02
Stato: completato

### Obiettivo

Creare il repo dell'app e costruire una V0 completa: sidebar che crea workspace, ognuno con più
terminali gestiti a tab (Workspace -> Tab -> terminale). Split deprioritizzato dall'utente.

### Fatto

- Repo `relay` (nome scelto) creato e pushato su github.com/essedev/relay (privato).
- Scaffold modulare SwiftPM (9 moduli, dipendenze imposte dal compilatore), Makefile, SwiftLint/
  SwiftFormat, CI GitHub Actions, docs canoniche (ARCHITECTURE/CONVENTIONS/STATE_SCHEMA/README/
  CLAUDE). `make check` verde dal primo commit.
- Engine: `TerminalEngine` con backend SwiftTerm; surface = `LocalProcessTerminalView` con cwd
  per-processo, teardown (SIGTERM), propagazione titolo (OSC). Nessun tipo SwiftTerm fuori dal
  modulo.
- Model: `WorkspaceStore`/`Workspace`/`Tab` (@Observable), puro e testato (12 unit test), con
  create/select/pin/reorder workspace e add/select/close/rename tab.
- UI: `SurfaceRegistry` (Tab.id -> surface, lazy, teardown per reconcile) + `WorkspaceAreaController`
  (AppKit, osserva lo store, scambia il terminale attivo). `SidebarView` e `TabBarView` (SwiftUI
  isolata) con design tokens (`Theme`). Terminale AppKit, chrome SwiftUI.
- App: NSSplitViewController (sidebar + area), menu e shortcut (New Workspace da folder picker
  Cmd+N, New Tab Cmd+T, Close Tab Cmd+W, Copy/Paste), seed workspace home. Gira, RSS ~77 MB.

### Decisioni / note

- V0: una tab = un terminale. Split (pane tree in `Tab`) previsto ma deprioritizzato.
- Le surface vive di tab visitate restano tutte in memoria: manca ancora un cap LRU (prossimo).
- Bridge Observation -> AppKit via `withObservationTracking` che si ri-arma.
- `Tab` va qualificato `WorkspaceModel.Tab` dove si importa anche SwiftUI (ambiguità con SwiftUI.Tab).

### Rifiniture V0 (stessa sessione)

- Workspace folder-less (`Cmd+N`, parte da home) e da cartella (`Cmd+O`); `Cmd+T`/`Cmd+W` tab.
- Navigazione a due assi stile cmux: `Cmd+1..9` workspace, `Option+1..9` tab.
- Fix: gli shortcut di menu con solo Option non matchano (AppKit confronta il carattere
  trasformato, es. Option+1 = "¡"); risolto con un `NSEvent` local monitor che intercetta
  `Cmd/Option + cifra` prima del terminale.

### Prossimi

Il piano forward è ora in `../ROADMAP.md`. In sintesi: (1) agent runtime + badge, (2)
persistence + rename, (3) cap LRU + misure, (4) bundle `.app`, poi dashboard e split.

## Cycle 7 - Agent Runtime + Badge

Stato: completato (Milestone 1). Relay è agent-aware.

### Obiettivo

Rendere Relay agent-aware nell'app reale: gli stati Claude (via hook, non parsing) diventano
badge su tab e sidebar. È il differenziatore del prodotto. Pipeline hook -> stato già validata
nel Cycle 1 (`spikes/ourterm-spike`).

### Task (dettaglio in `../ROADMAP.md`, Milestone 1)

1. Receiver Unix socket (JSON lines) in `AgentRuntime` -> `AgentSessionStore`.
2. Binding sessione -> tab via env `RELAY_TAB_ID` iniettata per surface.
3. Hook adapter + `relay hooks setup|uninstall|status` (idempotente, backup, convive con Otty).
4. Stato agente su `Tab`; applicazione evento -> tab in un coordinatore nel composition root.
5. Badge in `TabBarView`/`SidebarView` con aggregazione `AgentSeverity`; attention su needs_input.

### Note

- Notifiche macOS vere -> richiedono il bundle `.app` (milestone successiva); prima badge in-app.
- Anti-rumore: subagent stop != completamento; niente notifiche idle->idle.

### Esito

Costruito tutto il piano. Scelte di rilievo emerse in corso d'opera:

- **Trasporto tutto in Swift**: il CLI (`relay-cli claude-hook <state>`) fa da client del socket,
  lo script hook è solo un thin wrapper. Niente `nc`/`jq`/parsing shell: codice nostro, testabile.
- **Wire v1 = `AgentStateEvent` JSON line** (niente envelope `type`): in v1 tutto è `agent.state`.
- **Nomi hook confermati** sulla doc Claude corrente: `PermissionRequest` -> `needs_input` (lo
  spike aveva ragione), `matcher` solo per gli eventi tool, aggiunto `SessionEnd` -> `unknown`.
- **Logica evento -> tab in `WorkspaceStore.applyAgentState`** (reducer puro + visibilità),
  orchestrata da `AgentCoordinator`: così è unit-testabile senza app né socket.
- Aggiunto override `RELAY_CLAUDE_SETTINGS` dopo aver scoperto che `NSHomeDirectory()` ignora `$HOME`
  (un test manuale aveva toccato il vero `~/.claude`, poi ripristinato).

Test: socket end-to-end (Swift + reader Python indipendente), installer (fixture + round-trip su
disco, convivenza Otty), reducer, apply su store; smoke test dell'app viva (socket + evento senza
crash). `make check` verde (35 test). Manca solo la conferma visiva del badge con Claude reale.

Prossimo: Milestone 2 (persistence + rename), vedi `../ROADMAP.md`.

## Cycle 8 - UI/UX Quality Pass + Tooling

Stato: completato (fuori milestone). Giro di qualità sull'esperienza dopo che l'agent runtime era
funzionante ma l'app era "grezza".

### Obiettivo

Rendere Relay bella e coerente di default (il principio "pulita ma con possibilità di renderla
bella"), e darsi strumenti per vedere/testare gli stati agente senza sessioni Claude vere.

### Cosa è stato fatto

- **Sistema di temi** come design system: modello puro `RelayTheme` in `Core` (colori base + 16
  ANSI + font + blink del caret), unica fonte per terminale (via SwiftTerm `installColors`/native
  colors/font/`setCursorStyle`) e chrome (via `ChromeColors` -> SwiftUI). Due temi (Dark/Light),
  zoom font (`Cmd +/-`), blink cursore on/off; `fontSize`/`cursorBlink` sovrapposti al tema
  (`withFontSize`/`withCursorBlink`). Persistiti in `UserDefaults` (`AppSettings`). Badge dai colori
  ANSI del tema.
- **Pannello impostazioni** (`Cmd+,`): master-detail themed (sidebar con ricerca + categorie
  Appearance/Terminal, contenuto a destra). Voci come blocchi dichiarativi (categoria + keywords +
  vista), unica fonte per categorie e ricerca; anteprima palette sola lettura.
- **Semantica badge affinata**: distinzione stato vs marker. `needs_input`/`error` sono stati (il
  badge resta finché rispondi, non si spegne al focus); `completed` (idle dopo running) è transitorio
  e si spegne alla visita. Contatore sul workspace quando ≥2 tab condividono lo stato più severo.
- **Chrome finestra**: full-size content view, appearance che segue la luminanza del tema, titolo
  contestuale centrato sul body (`WindowTitle`: nome chat Claude via titolo OSC, `user@host:path`,
  cwd OSC 7, cartella workspace), toggle sidebar (`Cmd+B`) come overlay che insegue il bordo della
  sidebar, sidebar flat con selezione themed, sottotitolo per workspace, `Cmd+T` eredita la cwd.
- **Tooling di test** sul socket reale (nessun percorso finto nel model): `relay-cli simulate` dentro
  una tab e `relay --demo NxM` per popolare l'app con sessioni concorrenti simulate.

### Scelte/gotcha di rilievo

- Chrome full-size content view: le `NSHostingView` vanno con `safeAreaRegions = []`, altrimenti
  SwiftUI spinge il contenuto sotto la title bar.
- Toggle sidebar: overlay a livello finestra, NON `NSTitlebarAccessoryViewController` (non
  renderizzato con titolo nascosto su macOS 26).
- Sidebar: `NSSplitViewItem` normale, non `sidebarWithViewController:` (macOS 26 lo stila come glass
  flottante, in conflitto col design flat). Scroller interno di SwiftTerm nascosto a mano.
- `secondary` colore chrome = foreground con opacità, non ANSI bright black: contrasto garantito su
  ogni tema (il tema chiaro aveva smascherato icone illeggibili).

`make check` verde lungo tutto il ciclo (fino a 69 test). Prossimo: Milestone 2 (persistence).

## Cycle 9 - Interazione, Persistence, LRU, Resume

Stato: completato (Milestone 2 + inizio Milestone 3 + resume). Da app usabile a dogfood-abile.

### Obiettivo

Chiudere il giro di interazione su sidebar/tab (chiusura, rename, ordinamento), rendere il layout
persistente ai riavvii (M2), mettere un tetto alla memoria delle surface (M3), e riportare le
sessioni Claude dopo un riavvio (resume).

### Cosa è stato fatto

- **Interazione sidebar/tab e chiusura**: lista workspace custom (`LazyVStack`, non `List`) per
  togliere l'highlight full-size del menu contestuale; padding riga allineato all'header; riordino
  drag & drop (`moveWorkspace(_:onto:)`); x di chiusura su hover per tab e workspace; conferma di
  chiusura se nel pty gira un comando in foreground (`tcgetpgrp` vs `shellPid` + safe-list, stato
  Claude solo per il messaggio); chiudere l'ultima tab chiude il workspace, finestra mai senza
  workspace. Rename inline di workspace e tab dal menu contestuale. Float in cima (sotto ai pinned)
  dei workspace con attenzione (`needs_input`/completato) via `orderedWorkspaces` derivato, ordine
  canonico invariato.
- **Persistence del layout (M2)**: `LayoutSnapshot` Codable (`WorkspaceModel`) + modulo `LayoutStore`
  (I/O atomico su `~/.relay/layout.json`, versionato, path iniettato) + `LayoutAutosave`
  (debounced-live + flush on quit). Restore al boot con pane `unrealized` (surface lazy al focus),
  demo mode esclusa. Smoke end-to-end save+restore.
- **Cap LRU sulle surface (M3)**: `SurfaceRegistry.enforceLRU` + `SurfaceEvictionPolicy` (pura,
  testabile). Sfratta le meno recenti solo se idle (`hasRunningChildren == false` via
  `proc_listchildpids`: copre foreground/background/agente), mai la visibile né con lavoro vivo. Cap
  12, da tarare con le misure (ancora aperte).
- **Resume assistito Claude**: `ResumeBinding {agent, sessionId, label}` su `Tab`, catturato dagli
  hook in `applyAgentState` e persistito. Al primo focus di una tab `pendingResume`, la barra
  `ResumeBar` (Panels, riga vera che spinge giù il terminale) propone il resume; `surface.sendText`
  inietta `claude --resume <id>`. Setting `autoResumeAgents` (default off) per l'auto-inject lazy.
  Verificato a mano con Claude reale: il resume funziona, il che valida anche la pipeline
  hook -> socket -> tab (badge).

### Scelte/gotcha di rilievo

- Chiusura/conferma centralizzate in `AppController` (`requestClose*`), non nello store: policy e
  presentazione (`NSAlert`) nel composition root; `Cmd+W` e le x passano di lì.
- LRU eviction è distruttiva con SwiftTerm (teardown = kill PTY): sicura solo su tab senza figli.
  Meglio sforare il cap che uccidere un processo. La LRU non interseca il resume: una tab con Claude
  vivo ha figli -> non sfrattabile, quindi il resume serve solo dopo un riavvio.
- Il wiring della barra di resume vive in `RelayApp` (`RightPaneController`), non in `TerminalHostUI`:
  il path caldo non dipende da Panels. Resume lazy (al focus, un agente alla volta), non al boot.
- Resume: si persiste solo sessionId/agent/cwd/label; mai prompt/token/credenziali.
- Nuovi moduli/target: `LayoutStore` (persistence I/O); test target `LayoutStoreTests` e
  `TerminalHostUITests`.

`make check` verde lungo tutto il ciclo (fino a 90 test). Prossimo: chiudere le misure di
performance di M3 (latenza input p99, memoria per surface) per tarare il cap LRU, poi Milestone 4
(bundle `.app`).

## Cycle 10 - Misure M3, Bundle + Notifiche (M4), Temi e Font

Stato: completato (chiusura M3 + Milestone 4 + espansione appearance). Baseline delle milestone
chiuso.

### Obiettivo

Chiudere le misure di performance di M3 e tararne il cap; portare a casa Milestone 4 (bundle `.app`)
e con essa le notifiche macOS complete (impostazioni + suono); aggiungere temi classici e la scelta
del font family. Sempre con documentazione e test aggiornati.

### Cosa è stato fatto

- **Misure di performance (M3, chiuse)**: strumentazione integrata gated da `RELAY_PERF`
  (`PerfSampler`): campiona RSS e surface vive, e cronometra l'hook di input
  (`handleNavigationKey`) su keyDown sintetici dell'hot path. `LatencyStats` in `Core` (puro,
  testato) riassume i campioni; cap LRU reso configurabile via `RELAY_SURFACE_CAP` per esplorare la
  pendenza. Risultati (`docs/research/PERF.md`): latenza input aggiunta dallo shell **max 2.4µs**
  (budget 16ms p99, ~4 ordini di grandezza di margine), **~0.3-0.5 MB per surface idle**, **~98 MB
  con 30 surface vive**. Cap confermato a 12: non è un limite di memoria stretto ma una diga contro
  la crescita illimitata.
- **Milestone 4 - bundle `.app`**: `make bundle` assembla `.build/Relay.app` (release +
  `bundle/Info.plist`, bundle id `dev.relay.app` = subsystem di logging, + icona + firma ad-hoc);
  `make run-app` lo avvia. Serve perché `UNUserNotificationCenter` richiede un bundle id (da bare
  executable crasha). Verificato: il bundle parte pulito (rpath ok).
- **Icona e installer locale**: icona generata proceduralmente (`bundle/make-icon.swift`, Core
  Graphics headless -> `bundle/AppIcon.icns` via `make icon`): concept "prompt" (chevron accento +
  cursore a blocco allineato, gap netto) su squircle scuro della palette Relay Dark, iterata a vista
  su feedback. Installer locale non firmato: `make dmg` (`.build/Relay.dmg`, drag su /Applications) e
  `make install-app`. Distribuzione a terzi (Developer ID + notarizzazione) lasciata fuori: richiede
  account a pagamento.
- **Notifiche macOS complete**: trigger puro e testabile nel reducer
  (`AgentStateReducer.notification`, coerente con le regole anti-rumore dei badge: needs_input alla
  entrata, completato solo se non in vista). Lo store emette una `AgentNotification` (dato puro) via
  callback `onNotifiableTransition` - `WorkspaceModel` resta senza AppKit. Il composition root
  (`NotificationCoordinator`) applica preferenze + soppressione runtime (niente notifica se stai già
  guardando la tab con Relay in primo piano) e consegna via `UNUserNotificationCenter`. Impostazioni
  (categoria Notifications): master, per-tipo (needs input / finished), suono on/off + scelta suono
  (alert di sistema), persistite in `AppSettings` (default on). Attive solo dal bundle.
- **Temi e font**: quattro temi classici curati aggiunti al modello puro (`Core`): Solarized
  Dark/Light e Gruvbox Dark/Light coi 16 ANSI canonici. Con sei temi il picker segmented non regge:
  sostituito da una lista selezionabile, ogni riga anteprima la sua palette. Scelta font family
  (`AppSettings.fontName` sovrascrive il tema come `fontSize`; picker che enumera i monospace
  installati via `NSFontManager`).
- **Dettaglio UI**: nel badge del workspace il contatore delle tab in quello stato spostato a
  sinistra del pallino.

### Note di ragionamento

- La latenza input dello shell è trascurabile per costruzione: Relay non siede sul path di input
  del terminale (SwiftTerm possiede keyDown), aggiunge solo un check dei modificatori. Il budget
  keystroke-to-glyph è dominato dal rendering di SwiftTerm, fuori dal nostro controllo e fuori dal
  budget "latenza aggiunta dallo shell".
- Le notifiche riusano la logica anti-rumore dei badge invece di duplicarla: un unico classificatore
  puro decide sia il marker sia la notifica. La soppressione "la stai già guardando" è l'unica parte
  runtime, e vive nel composition root con `NSApp.isActive`.
- Refactor per rispettare i limiti di dimensione file (lint 400/250): componenti e binding di
  `SettingsView` estratti in `SettingsComponents.swift`; seeding demo in `DemoSeeder`.

### Rifiniture verificate dal vivo (post-M4)

- **Notifiche, consegna reale**: verificando dal vivo sono emersi due punti. (1) `isVisible` era solo
  "tab selezionata": se Relay è in background non la stai guardando, quindi ora `isVisible = tab
  selezionata && NSApp.isActive` (il coordinatore passa `appActive` allo store, che resta puro); al
  ritorno in primo piano la tab in vista viene visitata. (2) macOS **sopprime i banner dell'app in
  primo piano**: aggiunto `UNUserNotificationCenterDelegate` che forza `willPresent`. Diagnosi: la
  consegna funzionava (log `deliver`), ma i banner sparivano perché l'utente aveva **OBS** attivo
  (macOS nasconde le notifiche durante la registrazione schermo), non per un bug. Aggiunto log dello
  stato di autorizzazione al boot (diagnostica firma ad-hoc).
- **Anteprima del suono**: scegliendo un suono nel picker Notifications lo si sente subito
  (`NotificationSoundPreview`, `NSSound`).
- **Navigazione**: `Cmd+1..9` ora segue l'ordine visivo della sidebar (`orderedWorkspaces`), non
  quello canonico: `Cmd+1` apre sempre la riga in cima, anche quando un completamento la fa
  galleggiare su. Handler di menu estratti in `AppControllerNavigation`.
- **Drag & drop di file**: `RelayTerminalView` (sottoclasse della view SwiftTerm, che non lo fa da
  sola) inserisce i path escaped nel PTY come Terminal.app; escaping puro e testato in
  `Core.ShellEscape`.

`make check` verde lungo tutto il ciclo (fino a 114 test). L'app è installabile in locale
(`make install-app`/`make dmg`) con icona propria, notifiche verificate dal vivo.

### Giro "qualità terminale" (find, clear, jump, drag finestra)

Analisi dello stato: verificato nel codice che copy/paste e link cliccabili erano già coperti da
SwiftTerm (nessun gap), mentre mancavano ricerca, clear e un modo per navigare gli agenti che
chiedono attenzione. Quattro rifiniture:

- **Find nello scrollback** (`Cmd+F`): il motore c'era già in SwiftTerm (`findNext`/`findPrevious`/
  `searchMatchSummary`), mancava l'esposizione. Aggiunto al protocollo `TerminalSurfaceHandle`
  (`search`/`endSearch`, solo `Int` in uscita: nessun tipo SwiftTerm fuori dall'engine) e una
  `FindBar` flottante in alto a destra sul terminale (stile browser) con contatore "3/12", frecce
  su/giù, Invio/Esc. `FindModel` osservabile guida il contatore.
- **Clear** (`Cmd+K`): `ESC[3J` svuota lo scrollback del buffer, poi Ctrl+L al pty fa ripulire lo
  schermo alla shell e ridisegnare il prompt (come Cmd+K di iTerm).
- **Jump-to-attention** (`Cmd+J`): `WorkspaceStore.focusNextAttention` porta in vista la prossima
  tab in `needs_input`/completata-non-vista, in ordine visivo (`orderedWorkspaces`) e ciclico,
  saltando sempre la corrente. È il differenziatore del parallelismo agent. Testato (ciclo,
  salta-corrente, no-op, intra-workspace).
- **Drag finestra solo dalla title strip**: rimosso `isMovableByWindowBackground` (trascinava anche
  il terminale). Le due strip in alto usano `WindowDragArea`, una NSView pura con `performDrag` +
  doppio click = zoom secondo la preferenza macOS. NSView pura e non un gesture SwiftUI perché
  `mouseDownCanMoveWindow` non si propaga in modo affidabile sotto hosting SwiftUI. `Cmd+F`/`Cmd+K`/
  `Cmd+J` sono keyEquivalent veri del menu (non l'event monitor): funzionano col terminale in focus.

### Modello attention (ring + mark-read, ispirato a cmux)

Emerso da un feedback: al ritorno in foreground non si vedeva quale chat avesse finito, e non era
chiaro *quando* un completamento si segnava come "letto". Prima di intervenire abbiamo analizzato il
codice reale di cmux (Swift nativo, open source `manaflow-ai/cmux`), non la doc marketing. Scoperte:

- cmux sul desktop **non** colora il bordo per stato: ring **sempre blu**, binario letto/non letto
  (`Panel.swift` -> `.systemBlue`); i colori per stato (working/needs-input/done) esistono solo
  nella app mobile. La distinzione la lascia al testo della notifica.
- Il ring persistente **non pulsa**: statico, con un **flash** momentaneo (doppio blink 0.9s,
  `[1,0,1,0]`) all'arrivo e al ritorno in foreground. Due layer distinti (ring + flash).
- Il mark-read è una **matrice per contesto** (`NotificationDismissalModel`): il **focus del pane
  non basta**, **solo l'interazione reale** (typing/click nel terminale, `.terminalInteraction`)
  spegne l'unread manuale. Nessun timer di auto-read. `Cmd+Shift+U` salta all'unread più recente.

Cosa abbiamo adottato per Relay (divergendo dove utile):

- **Ring di stato colorato** (`AttentionRingView`), non binario come cmux: più informativo, e
  abbiamo già i colori nel design system. Verde = completato (statico + flash all'accensione/ritorno,
  idea presa da cmux: niente pulse infinito che stanca), giallo/rosso pulsante = aspetta input/errore.
  Colori dai colori ANSI del tema, coerenti coi badge. Overlay `hitTest` nil sopra il terminale.
- **Mark-read = interazione** (tasto o click, dal monitor locale), non il semplice ritorno in
  foreground - che invece fa solo un flash. Confermato dall'analisi cmux. Il ring vive in un observer
  separato dal `render()` del terminale, che **non** scrive `attention` (altrimenti il completamento
  sulla tab in vista si spegnerebbe da solo: loop col reset della visita).
- `Cmd+J` (già fatto nel giro precedente) = il loro `Cmd+Shift+U`.

Nota tecnica: `keyDown`/`mouseDown` di SwiftTerm sono `public` non `open`, quindi non overridabili da
un altro modulo; l'interazione si cattura con un `NSEvent` local monitor (`[.keyDown, .leftMouseDown]`)
nel composition root, non con un override nella view.

`make check` verde (118 test). Prossimo giro a scelta: distribuzione firmata (Developer ID +
notarizzazione), dashboard overview, oppure split.
