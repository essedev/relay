# Relay - guida per l'agent

Terminale macOS nativo agent-aware. Leggi `docs/ARCHITECTURE.md` prima di toccare la struttura
e `docs/CONVENTIONS.md` prima di scrivere codice. Cosa manca e in che ordine: `docs/ROADMAP.md`;
la storia delle decisioni sta in `docs/research/CYCLES.md`.

Notifiche e check aggiornamenti girano **solo dal bundle** (`make run-app`), non da `swift run`:
una verifica a mano di quelle due aree fatta con `make run` non prova niente.

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
- **Licenza**: MIT (`LICENSE`), con le notice delle dipendenze in `NOTICE`. Entrambi vengono
  copiati in `Relay.app/Contents/Resources` da `make bundle`: la MIT di SwiftTerm impone di
  riprodurre la notice in ogni distribuzione. Se aggiungi una dipendenza, aggiorna `NOTICE`.
- **Guida utente**: `make guide-md` rigenera `docs/GUIDE.md` dalla guida in-app (fonte unica in
  `Sources/WorkspaceModel/Guide*.swift`). Un test fallisce se il file committato è disallineato:
  se tocchi il contenuto, rigenera nello stesso commit. Vedi `docs/features/guide.md`.
- **Screenshot del README**: `scripts/screenshots.sh` (demo isolata, non tocca `~/.relay`).
  Occupa lo schermo per un minuto e serve il permesso Screen Recording.
- **Simulatore agente**: `relay-cli simulate [coding|permission|error|burst] [--loops N] [--fast]`,
  da lanciare *dentro una tab di Relay*: recita una chat finta e manda eventi reali al socket
  (stesso client/wire degli hook). Per testare badge/aggregazioni senza sessioni Claude vere.
- **Demo mode**: `relay --demo [NxM]` (default 4x3): N workspace da M tab con sessioni simulate
  concorrenti su ogni tab, eventi via socket reale. Per vedere l'app "piena" e testare
  badge/contatori/aggregazioni a colpo d'occhio.

## Mappa moduli (dipendenze solo verso il basso)

Dove sta una cosa. Cosa c'è dentro lo dice `ls Sources/<Modulo>/`, il perché sta in
`ARCHITECTURE.md` (sezione Struttura Repo E Moduli): qui solo il ruolo.

- `Core` - primitivi puri, zero dipendenze: log, modello tema, logica senza I/O usata da più moduli.
- `AgentProtocol` - tipi evento/stato agente. Niente I/O, niente AppKit.
- `AgentRuntime` - trasporto eventi (socket Unix, receiver e client). Niente AppKit né model.
- `WorkspaceModel` - lo stato osservabile e tutta la logica pura che decide, incluso il manuale
  come dato. Niente AppKit. Le operazioni stanno nelle extension per area (`+Split`, `+Windows`,
  `+Persistence`, `+Groups`, `+Navigation`, `+Ordering`, `+AgentState`).
- `TerminalEngine` - l'astrazione del terminale e il backend SwiftTerm.
- `TerminalHostUI` - il path caldo: `SurfaceRegistry` e la riconciliazione dell'albero di pane.
- `Panels` - SwiftUI isolata: design system e tutti i pannelli.
- `HookInstaller` - hook Claude/Codex sui file di configurazione: trasformazioni pure separate
  dall'I/O, entry marcate, backup e scrittura atomica.
- `LayoutStore` - I/O del `LayoutSnapshot` su disco. Niente AppKit.
- `RelayApp` (`Sources/relay`) - composition root.
- `CLI` (`Sources/relay-cli`) - `relay-cli`: `hooks`, `claude-hook`/`codex-hook`, `simulate`.

## Regole che non si violano

- AppKit sul path caldo (terminale, input); SwiftUI solo nei pannelli isolati.
- **Nessun tipo SwiftTerm fuori da `TerminalEngine`**: verso l'alto esce solo `NSView`.
- **Una sola `SurfaceRegistry` per l'app**, condivisa dalle finestre: una tab ha una surface sola
  ovunque sia montata, e il cap LRU ragiona sul totale vivo.
- `RelayApp` è l'**unico posto che tocca il mondo esterno** (sistema, rete, file dell'utente). Se
  cresce oltre il wiring, manca un modulo; se prende decisioni, quelle vanno in un tipo puro
  altrove, dove esiste un test target (è il motivo per cui `NotificationPolicy` sta in
  `WorkspaceModel`).
- Lazy + budget: niente priming, niente risorse pesanti prima del bisogno (vedi principi in
  ARCHITECTURE). Cap scrollback.
- Mai `print` per logging (usa `RelayLog`); nel CLI il print è output utente, ok. In un log,
  **un valore interpolato va stampato con `privacy: .public`** se non è dato dell'utente: os_log
  redige per default, e un errore che dice `<private>` è peggio del silenzio, perché sembra una
  diagnosi e non lo è. L'`errno` va letto in una `let` prima del log: l'interpolazione stessa può
  sovrascriverlo.
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
  stato, resume di Claude Code e Codex. **Invariante**: un evento fuori run o anteriore al boot si scarta.
- `docs/features/terminal.md` - integrazioni e limiti di SwiftTerm: kitty keyboard, cwd senza
  OSC 7, selezione durante lo streaming, scroll fluido, ricerca `Cmd+F`, cap LRU delle surface.
- `docs/features/sidebar.md` - lista dei workspace, dove nasce una cosa nuova, archivio, drag &
  drop, e il drag di una tab da una strip a un altro workspace (`TabDragSession`).
- `docs/features/workspace-groups.md` - card di gruppo: l'appartenenza vive sul workspace, il
  gruppo porta solo l'aspetto; un gruppo senza membri non esiste.
- `docs/features/split-panes.md` - modello cmux v2: i pane ospitano le tab, "visibile" vs
  "focused", reconcile dell'albero e ratio dei divider.
- `docs/features/windows.md` - chrome full-size, `makePanelWindow` per le finestre di servizio,
  overlay full-window, ciclo di vita di una `NSWindow`, multi-window.
- `docs/features/keyboard.md` - il local monitor come unico trigger delle azioni rimappabili,
  shortcut numerici, testo composto con `Option`.
- `docs/features/session-deactivation.md` - spegnere l'agente di una tab tenendo il `ResumeBinding`.
  **Invariante**: marcare prima di buttare la surface, o il `SessionEnd` azzera il binding.
- `docs/features/workspace-naming.md` - nomina automatica: due fonti (regola locale, LLM se c'è la
  chiave) con gli stessi trigger, single-flight, `NameOrigin`, API key su file 0600.
- `docs/features/guide.md` - il manuale: una fonte (`Guide.sections`), due rese (pannello e
  `docs/GUIDE.md`), test di allineamento.
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
- Runtime Stats (`View > Runtime Stats…`): `RuntimeStatsSampler` campiona **solo** finché il
  pannello è aperto e invalida il timer in `windowWillClose`. Non trasformarlo in polling
  permanente, e non fonderlo con `PerfSampler`, che è dev tooling.
- `Tab` è ambiguo: SwiftUI ha un suo `Tab`. Nei file che importano SwiftUI + WorkspaceModel usa
  `WorkspaceModel.Tab`.
- Bridge Observation -> AppKit: `WorkspaceAreaController.observe()` usa `withObservationTracking`
  e si ri-arma; leggi le proprietà osservate dentro `render()` o non verranno tracciate.
- **Mai lanciare `relay-cli hooks setup` a mano nei test senza gli override path**:
  `NSHomeDirectory()`
  ignora `$HOME` su macOS e scriverebbe il vero `~/.claude`. Per test/manuale usa
  `RELAY_CLAUDE_SETTINGS=/tmp/....json` e `RELAY_CODEX_HOOKS=/tmp/....json`. I test unit passano
  già un path esplicito. Dalla 0.21.0 l'app **ripara da sola** all'avvio un set di hook Claude
  incompleto: un'istanza di sviluppo senza override riscriverebbe il `~/.claude` vero.
- `RELAY_SOCKET` deve stare sotto ~104 byte (`sun_path`): più lungo, il receiver non parte e
  l'app resta viva ma sorda, senza eventi e senza badge. La dir di scratch di una sessione agent
  supera già il limite: per un'istanza isolata usa un path corto tipo `/tmp/relay-probe.sock`.
- `swift build --target X` può ricompilare un modulo senza rilinkare l'eseguibile: per testare un
  binario aggiornato usa `swift build` completo (o `make build`).
- **Focus dentro un overlay/hosting SwiftUI**, costato tre fix separati: differisci il
  `makeFirstResponder` di un runloop, saltalo se il first responder è già un discendente
  dell'host, e dal lato SwiftUI ritenta il `FocusState` da un `task` (l'`onAppear` corre contro il
  primo layout). Dettagli in `docs/features/windows.md`.
