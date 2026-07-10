# Architecture

Progetto: **Relay**.
Ultimo aggiornamento: 2026-07-02.

Documento vivo: budget, moduli e confini si rivedono quando misure o sviluppo portano evidenze
nuove. La storia decisionale completa (cicli 0-8: analisi engine, diagnosi lag cmux, benchmark
SwiftTerm) vive in `docs/research/` (`CYCLES.md`); qui si tiene lo stato corrente.

## Tesi Di Prodotto

Un terminale macOS nativo per lavorare con molti coding agent in parallelo. Combina:

- gli stati agente affidabili di Otty (hook Claude Code, non parsing dell'output);
- l'organizzazione a workspace di cmux (progetti che raggruppano tab, sidebar, pin, riordino);
- una dashboard overview di tutti i progetti e i loro agenti;
- velocità e leggerezza dove cmux lagga.

Il centro del prodotto non è "un terminale con badge": è organizzare e sorvegliare N progetti con
agenti attivi da un posto solo, calmo e rapido. Il terminale è il substrato.

Non è un fork di cmux. È una nuova app che usa:

- **SwiftTerm** come terminal engine v1, dietro un'astrazione sostituibile (`TerminalEngine`);
- cmux come reference di prodotto e come catalogo di anti-pattern di performance;
- Otty come reference comportamentale per gli stati agente;
- hook Claude Code come fonte autorevole del lifecycle agente.

Motivo della scelta engine (rivisto nel Cycle 5): libghostty non è ancora una libreria
embeddabile stabile. Solo `libghostty-vt` (il parser VT, non il rendering) è in arrivo, alpha,
taggato "entro 6 mesi"; la C API completa con rendering è dichiarata internal-only dall'autore
e si builda solo da sorgente con zig (che sul SDK macOS 26.5 di questa macchina non linka).
SwiftTerm invece è puro Swift/SPM, toolchain standard, MIT, provato in produzione embedded
(Secure Shellfish, La Terminal, CodeEdit, Pane). libghostty resta il backend futuro dietro
`TerminalEngine` quando la sua API si stabilizza.

## Principi Non Negoziabili

Derivano dalla diagnosi del lag di cmux (CYCLES.md, Cycle 3). Ogni decisione di design va
verificata contro questa lista.

1. **Lazy, non eager.** Nessuna risorsa pesante (PTY, VT, renderer) nasce prima che serva.
   Niente priming dei workspace in background.
2. **Budget espliciti.** Renderer vivi, scrollback, memoria per workspace chiuso: tutto ha un
   tetto dichiarato e misurato. Se serve un sottosistema di "hibernation" per stare in piedi,
   il design di base è sbagliato.
3. **Sidebar e terminale disaccoppiati.** Un aggiornamento di stato agente non deve mai
   invalidare il view tree del terminale. Mai un unico body SwiftUI che contiene tutto.
4. **Event-driven, niente polling.** Gli stati arrivano da hook e notifiche; la UI reagisce.
5. **File e moduli piccoli.** Limite indicativo 500 righe per file. `ContentView.swift` di cmux
   (16k righe) è il controesempio.
6. **UI pulita e semplice, ma con margine estetico.** Il default è essenziale e leggibile, non
   spartano: i pannelli SwiftUI attingono a un piccolo design system (token di spaziatura,
   tipografia, colore, raggi) invece di valori hardcoded, così alzare l'asticella estetica è un
   cambio di token, non un refactor. Niente cromo inutile che compete col terminale.

### Budget v1

| Voce | Budget |
| --- | --- |
| Latenza input aggiunta dall'app shell | < 1 frame (16ms) p99 |
| Switch workspace con surface viva | < 50ms |
| Switch workspace con surface da realizzare | < 300ms percepiti |
| Renderer vivi simultanei | cap LRU (default 12) sulle surface vive |
| Memoria per surface | ~0.3-0.5 MB idle (misura M3) |
| Costo di un workspace mai aperto | ~0 (solo metadata) |

I numeri erano target iniziali; le misure di Milestone 3 (`docs/research/PERF.md`) confermano il
budget di latenza input (max 2.4µs, ~4 ordini di grandezza di margine) e tarano il cap LRU sulla
memoria per surface. **Cap dello scrollback per surface**: previsto ma non ancora implementato -
oggi la leva di memoria è solo il cap LRU (surface idle sfrattate), non un limite di righe per
surface; lo scrollback usa il default di SwiftTerm.

## Modello Di Prodotto

```text
Window
  Sidebar (sinistra)
    Sezione pinned
    Lista workspace (drag per riordinare)
  Content
    Workspace attivo
      Tab verticali
        Split pane tree
          Pane terminale
  Dashboard (vista alternativa al workspace attivo)
```

- **Workspace**: un progetto (tipicamente una cartella/repo). Raggruppa tab. Ha nome, cwd di
  default, pin, posizione in sidebar, stato agente aggregato.
- **Tab**: una vista di lavoro dentro il workspace. Contiene un albero di split pane.
- **Pane**: una sessione terminale. È l'unità a cui si lega una sessione agente.
- **Dashboard**: overview read-only di tutti i workspace con stato agenti, ultimo evento e
  jump-to al click. v1 volutamente minimale.
- **Gruppi di workspace**: fuori dalla v1, il data model non deve impedirli.

## Architettura Logica

```text
macOS App
  App Shell (AppKit)
    Window Controller
    Terminal Host View + Focus Routing
    Keyboard Shortcuts (event monitor)

  Terminal Runtime
    SwiftTerm (dietro TerminalEngine; libghostty futuro)
    Surface Registry (lazy + LRU)
    PTY Session

  Agent Runtime
    Local Socket Receiver (+ self-heal)
    Hook Installer

  Workspace Model
    Workspace / Tab Store
    Ordinamento, pin, aggregazione stati, attention
    Persistence + Restore

  UI Panels (SwiftUI isolato)
    Sidebar
    Dashboard
    Settings

  CLI (relay-cli)
    hooks setup/uninstall/status
    claude-hook <state>, simulate
```

Nota: non c'è (ancora) una timeline degli eventi né un session store persistente: `AgentRuntime`
fa solo trasporto, il binding evento -> tab e l'aggregazione vivono in `WorkspaceModel`.

## Struttura Repo E Moduli

Monolite modulare: **un solo package SwiftPM** con molti target (moduli). Il confine tra moduli è
imposto dal compilatore (dipendenze dichiarate in `Package.swift`), non dalla buona volontà. È la
contromisura strutturale ai file da 12-16k righe e agli `AppDelegate+X` di cmux.

```text
repo/
  Sources/
    Core/               primitivi condivisi: logging, tema, OSC7, escaping; nessuna dipendenza
    AgentProtocol/      tipi evento e stati (AgentStateEvent); puro, niente I/O
    AgentRuntime/       socket receiver + client, runtime paths; puro, niente AppKit
    WorkspaceModel/     store workspace/tab, reducer stati, attention, persistence, settings
    TerminalEngine/     backend SwiftTerm dietro un'astrazione, surface lifecycle
    TerminalHostUI/     AppKit: host view, surface registry (lazy + LRU), attention ring
    Panels/             SwiftUI: sidebar, tab bar, dashboard, settings, stats, badge
    HookInstaller/      manipolazione ~/.claude/settings.json + mapping hook -> stato
    LayoutStore/        persistence layout: snapshot JSON su disco (I/O), path iniettato
    relay/              eseguibile `relay` (RelayApp): composition root e wiring
    relay-cli/          eseguibile `relay-cli` (CLI): hooks setup, claude-hook, simulate
  Tests/
  docs/
  Makefile
```

Regole di dipendenza:

- solo verso il basso: UI -> runtime/model -> protocol -> Core; mai il contrario;
- `AgentProtocol`, `AgentRuntime`, `HookInstaller` e `WorkspaceModel` non importano AppKit/SwiftUI:
  unit test veloci con `swift test`, senza simulatore;
- l'engine concreto (SwiftTerm oggi, libghostty domani) è importato solo da `TerminalEngine`;
  il resto dell'app parla con `TerminalEngine`, non con l'engine. La policy del lifecycle
  (decisioni lazy/LRU) è un tipo puro testabile senza AppKit;
- `relay-cli` dipende da `Core`, `AgentProtocol`, `AgentRuntime` (client socket) e `HookInstaller`:
  niente dipendenze dal target app;
- `relay` è solo composition root: se cresce oltre il wiring, manca un modulo.

Disciplina di codice, test e processo: `CONVENTIONS.md` (bozza qui, poi `docs/CONVENTIONS.md`
nel repo app).

### Confine AppKit / SwiftUI

- **AppKit**: finestre, split tree, host della terminal surface, focus, tastiera. Tutto il path
  sensibile alla latenza.
- **SwiftUI**: solo pannelli isolati (sidebar, dashboard, settings), ognuno montato in un
  `NSHostingView` proprio, che osserva store a grana fine (Observation framework). Un
  cambiamento di badge invalida la riga della sidebar interessata, non altro.

## Terminal Runtime

### Lifecycle Della Surface

Il cuore anti-lag. Tre stati per pane:

```text
unrealized --primo focus--> live-visible <--switch--> live-hidden
```

- `unrealized`: nessun PTY, nessun emulatore, nessuna view. Solo metadata (cwd, titolo, resume
  binding). È lo stato di ogni pane al restore e di ogni workspace mai visitato.
- `live-visible`: PTY + emulatore + view attivi. Solo i pane effettivamente a schermo.
- `live-hidden`: PTY + emulatore attivi, view di rendering rilasciata o sospesa oltre il budget
  LRU.

Regole:

- PTY ed emulatore restano vivi finché il processo figlio vive: mai bloccare la pipe di un
  agente che lavora in background. Ciò che si toglie ai pane nascosti è la view di rendering,
  non il processo.
- La creazione è sempre lazy: al restore nessuna view nasce; nasce al primo focus.
- Un cap di scrollback per surface è previsto (i transcript lunghi di Claude non devono gonfiare la
  memoria di ogni pane vivo), ma **non ancora implementato**: oggi la memoria è tenuta bassa solo
  dallo sfratto LRU delle surface idle.
- La chiusura dell'app termina i PTY: il restore riparte da `unrealized` + resume command.

Con SwiftTerm l'unità viva è `LocalProcessTerminalView` (NSView + PTY). Il lifecycle lazy/LRU
si applica creando/distruggendo quella view; per i pane `live-hidden` si valuta se SwiftTerm
permette di scollegare la view mantenendo l'emulatore, altrimenti si distrugge la view e si
ricrea al focus (la policy resta la stessa, cambia solo il meccanismo).

### Engine: Decisione E Astrazione

- **v1: SwiftTerm.** Puro Swift/SPM, toolchain standard, `TerminalView` (NSView) +
  `LocalProcessTerminalView` (PTY) turnkey, rendering CoreText con backend Metal opzionale.
- **Futuro: libghostty**, quando esce una C API embeddabile stabile (oggi internal-only/alpha,
  vedi Cycle 5). Rendering GPU superiore.
- Entrambi dietro `TerminalEngine`, che espone un'interfaccia sottile: crea/distruggi surface,
  scrivi input, leggi dimensioni/titolo/cwd e il processo in foreground del pty, notifica
  output/bell/OSC. Il resto dell'app non sa quale engine c'è sotto. Questo rende la migrazione un
  update localizzato, non un rewrite.
- Drag & drop di file: `RelayTerminalView` (sottoclasse della view SwiftTerm, dentro il modulo)
  registra il drop e scrive nel PTY i path escaped (`Core.ShellEscape`, puro e testato), come
  Terminal.app. SwiftTerm non lo fa da solo; il tipo SwiftTerm resta confinato qui.

### Chiusura E Conferma

Chiudere una tab o un workspace passa dal composition root (`AppController.requestClose*`), non
direttamente dallo store: lì vive la policy. Prima di chiudere si guarda se nel pty gira un comando
in foreground (`TerminalSurfaceHandle.foregroundProcessName()`: `tcgetpgrp` del pty confrontato col
pid della shell, con safe-list per le shell interattive); se sì si conferma con un `NSAlert` sheet,
altrimenti si chiude subito. Il gate è **il processo**, non l'agente: vale anche per build, ssh,
editor, non solo Claude. Lo stato agente (`running`/`needs_input`) serve solo ad arricchire il
messaggio. Tradeoff accettato: solo foreground - i job in background (`&`, dietro tmux) non contano;
prenderli richiederebbe enumerare i discendenti della shell (più costoso, più falsi positivi).

Invarianti: chiudere l'ultima tab di un workspace chiude il workspace (cascade in `closeTab`);
chiudere l'ultimo workspace ne riapre uno default (la finestra non resta mai senza workspace). Il
teardown delle surface resta reattivo (reconcile via `retain` in `WorkspaceAreaController`), non
esplicito nel percorso di chiusura.

## Tema (Design System)

Il principio UI #6 (bella di default, personalizzabile) si concretizza in un modello di tema come
dato puro in `Core` (`RelayTheme`/`RelayColor`): colori base + 16 ANSI + font. È l'**unica fonte**:

- il terminale (`TerminalEngine`) converte in colori SwiftTerm/NSColor e applica via `apply(theme:)`;
  i badge e la chrome ANSI-derivati restano coerenti con l'output di Claude Code/`git`/`ls`;
- la chrome (`Panels`) converte in SwiftUI Color (`ChromeColors`): sidebar/tab bar/badge dal tema;
- `AppSettings` (`WorkspaceModel`, @Observable) tiene tema selezionato + dimensione font + font
  family + blink del caret + preferenze notifiche + decadenza dei sospesi (`pendingDecayHours`),
  persistiti in `UserDefaults` (preferenze, non lo snapshot del layout). `fontSize`, `fontName` e `cursorBlink` sono sovrapposti al tema base
  (`withFontSize`/`withFontName`/`withCursorBlink`); il terminale usa `theme.fontName` (fallback al
  monospace di sistema). Cambi -> `SurfaceRegistry.applyTheme` ridipinge le surface vive; la chrome
  si aggiorna via Observation.
- Dodici temi curati (dato puro in `Core`), sei coppie dark/light: **Relay** (One Dark/Light),
  **Solarized**, **Gruvbox**, **Tokyo Night** (night/day), **Catppuccin** (Mocha/Latte),
  **GitHub** (Primer dark/light default).

Pannello impostazioni (`Cmd+,`): master-detail themed - sidebar con ricerca e lista categorie
(Appearance / Terminal / Agents / Notifications), contenuto a destra. Ogni voce è un "blocco"
dichiarativo (categoria + keywords + vista), unica fonte per categorie e ricerca: aggiungere
un'impostazione è una riga. Temi come lista selezionabile (ogni riga anteprima la sua palette),
scelta font family (monospace installati), zoom (`Cmd +/-`, `Cmd+0`). Import da config Ghostty:
possibile in futuro, non nel baseline.

## Chrome E Finestra

Finestra `fullSizeContentView`: il contenuto sale fino al bordo, titolo nativo nascosto (resta per
Mission Control/Cmd+Tab), appearance AppKit che segue il tema (`darkAqua`/`aqua` dalla luminanza di
`RelayTheme.isDark`, così i controlli di sistema restano leggibili). La chrome vive nel composition
root:

- `RootOverlayController` sovrappone al contenuto (lo split) un overlay a posizione fissa - il
  toggle sidebar (`Cmd+B`) - accanto ai semafori. Segue la larghezza reale della sidebar
  frame-by-frame (`splitViewDidResizeSubviews`): da aperta è al bordo destro della sidebar, alla
  chiusura scivola in continuità fino ai semafori. Un solo bottone, niente swap.
- `ContextTitleBar` (in cima al right pane): strip del titolo centrata sul body, contenuto da
  `WindowTitle` - titolo OSC del programma (Claude manda il nome della chat, zsh `user@host:path`),
  altrimenti cwd corrente (OSC 7) abbreviata con `~`, altrimenti cartella/nome del workspace.
- Drag finestra: **non** `isMovableByWindowBackground` (trascinerebbe anche il terminale). Le due
  strip in alto (`ContextTitleBar`, `trafficLightsStrip` della sidebar) usano `WindowDragArea`: una
  NSView pura (via `NSViewRepresentable`) che in `mouseDown` fa `performDrag` e, sul doppio click,
  lo zoom/minimizza secondo la preferenza macOS. NSView pura e non un gesture SwiftUI perché
  `mouseDownCanMoveWindow` non si propaga in modo affidabile sotto hosting SwiftUI, mentre
  `performDrag` è deterministico.
- Find bar (`Cmd+F`): overlay flottante in alto a destra sul terminale (`FindBar` + `FindModel`
  osservabile), motore di ricerca di SwiftTerm esposto via `TerminalSurfaceHandle.search`. `Cmd+K`
  pulisce il terminale (`clear`), `Cmd+J` salta alla prossima tab in attenzione
  (`WorkspaceStore.focusNextAttention`). Sono azioni rimappabili (vedi sotto), gestite dal monitor
  così scattano anche col terminale in focus.
- Dashboard (`Cmd+D`): overlay full-window sopra tutto (`RootOverlayController.presentFullOverlay`)
  con la griglia delle sessioni agente - vedi #Dashboard-Delle-Sessioni.
- Runtime Stats (`View > Runtime Stats…`): pannello read-only separato dalle Settings (non è una
  preferenza), con RSS, CPU del processo, conteggi workspace/tab e surface vive/cap. Campiona solo
  mentre la finestra è aperta; a regime non aggiunge polling.
- Onboarding ("Welcome to Relay"): overlay full-window al primo avvio (flag
  `AppSettings.onboardingSeen`, mai in demo mode), riapribile da Help > Welcome to Relay. Cinque
  pagine coi componenti veri del design system al posto di screenshot (badge live, keycap dai
  binding correnti, temi selezionabili dal vivo, icona procedurale `RelayMarkView`); la pagina
  hook riusa `ClaudeHooksBlock` (stato + install). Logica di navigazione pura
  (`OnboardingModel`, testata), wiring in `AppControllerOnboarding`.
- Gli overlay full-window sono avvolti in un container che chiude i buchi di hit-testing (il
  mouse non passa mai al terminale sotto) e disattivano le cursor rects della finestra finché
  sono su (quelle di SwiftTerm non rispettano l'occlusione: I-beam sopra l'overlay).
- Sidebar: `NSSplitViewItem` normale, **non** `sidebarWithViewController:` (su macOS 26 quello stila
  la sidebar come pannello glass flottante, in conflitto col design flat themed). Righe con
  selezione/hover dai colori del tema (niente highlight di sistema), sottotitolo per riga
  (`WindowTitle.workspaceSubtitle`: cosa succede nella tab selezionata) e badge aggregato.
- OSC 7: la cwd riportata dalla shell (`Core.OSC7` -> `Tab.currentDirectory`) alimenta titolo,
  sottotitolo e l'ereditarietà cwd di `Cmd+T` (la nuova tab parte dove stai lavorando, non alla
  radice del workspace).

## Scorciatoie (keybinding rimappabili)

Le azioni sono un enum puro (`ShortcutAction`, in `WorkspaceModel`) con label, gruppo e combo di
default; la combinazione è `KeyCombo` (tasto normalizzato + modificatori, `Codable`, indipendente da
AppKit). `AppSettings` tiene il dizionario `[ShortcutAction: KeyCombo]`, persistito in UserDefaults
(JSON), con default e rilevamento conflitti.

**Un solo punto di dispatch**: tutte le azioni rimappabili passano dall'`NSEvent` local monitor del
composition root, **non** dai `keyEquivalent` di menu (che non gestiscono ogni combinazione, es.
Option-only o `Ctrl+Tab`). Il monitor converte l'evento in `KeyCombo` (`KeyEventBridge`, in Panels
così lo usa anche il recorder), cerca l'azione nei binding e chiama `perform(action)`
(`ShortcutRuntime`). I menu mostrano la combo nel **titolo** con `keyEquivalent` vuoto (niente doppio
trigger) e si ricostruiscono al cambio binding (`observeKeybindings`). Restano fissi con
`keyEquivalent` vero solo i comandi di sistema (Copy/Paste/Select All via responder, Quit, Settings)
e i select-by-number.

Il **recorder** (impostazioni) installa un monitor locale temporaneo e alza
`settings.isCapturingShortcut`: il monitor globale si fa da parte, così l'evento arriva al recorder
invece di eseguire l'azione. Rifiuta le combo di sistema e segnala i conflitti; reset per singola
azione o globale.

Precedenza del testo: sui layout internazionali `Option` spesso equivale ad AltGr (`Option+ò` =
`@`, `Option+digit` = simboli). Se macOS produce un carattere stampabile da una combinazione
`Option` senza `Cmd/Ctrl`, Relay la considera digitazione: il monitor non la consuma e la surface
scrive il testo UTF-8 nel PTY prima che il keyboard protocol del terminale lo trasformi in un tasto
modificato. Eccezione: `Option+1..9` (senza Shift) è il select-tab fisso e vince sempre sul simbolo
che il layout comporrebbe (es. `Option+1` = `«` sull'italiano) - quei simboli non sono digitabili
finché esiste la shortcut; il resto del testo da `Option` vince sulle scorciatoie. La regola vive
in un punto solo (`Core.KeyboardTextInput`), condivisa da monitor, surface e recorder.

## Tooling Di Test (Simulatore E Demo)

Due strumenti esercitano la pipeline agente senza sessioni Claude reali, **passando dal socket
reale** (`AgentEventClient` -> receiver -> coordinator): nel model non esiste un percorso finto.

- `relay-cli simulate [coding|permission|burst]`: da lanciare dentro una tab (eredita
  `RELAY_TAB_ID`), recita una chat finta con tempi realistici. Esercita binding, trasporto, reducer
  e badge end-to-end.
- `relay --demo [NxM]`: popola l'app con N workspace da M tab e simula sessioni concorrenti su ogni
  tab (`DemoDriver`, un `Task` per tab). Per vedere badge/contatori/aggregazioni a colpo d'occhio.

## Agent Runtime

### Responsabilità

- ricevere eventi dagli hook (trasporto Unix socket);
- decodificarli in `AgentStateEvent`;
- consegnarli al composition root, che li lega alla tab (`paneId`) e li applica al model.

Il binding sessione -> tab, l'aggregazione e la timeline (non ancora implementata) vivono a valle,
in `WorkspaceModel`, non qui: `AgentRuntime` resta puro trasporto.

### Fonti Stato

- hook Claude Code: fonte autorevole;
- futuro: hook Codex/OpenCode;
- OSC / shell integration (`133`, `9;4`): solo per comandi shell generici;
- euristiche output: fallback opzionale, mai per gli stati agente principali.

### Stati Normalizzati

`running`, `idle`, `needs_input`, `error`, `unknown`.

Mapping Claude v1:

| Claude event | Stato |
| --- | --- |
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `running` |
| `PreToolUse` | `running` (`needs_input` se il tool apre un prompt, vedi sotto) |
| `PostToolUse` | `running` |
| `PermissionRequest` | `needs_input` |
| `Stop` | `idle` |
| `SessionEnd` | `unknown` |

`SubagentStop` non è mappato: lo stop di un subagent non è il completamento del pane. Nomi hook
confermati sulla doc Claude Code corrente (luglio 2026). Nota: nello spike gli stati usano i nomi
Otty (`processing`, `awaiting`, `idle`); nell'app si usano i nomi prodotto qui sopra.

I tool che aprono un prompt bloccante (`AskUserQuestion`, `ExitPlanMode`) non passano da
`PermissionRequest` (non sono permessi) e non producono `Stop` finché l'utente non risponde: il
loro `PreToolUse` viene corretto in `needs_input` dal CLI (`ClaudeHookStateMapper`, che legge
`hook_event_name` e `tool_name` dallo stdin dell'hook); il `PostToolUse`, che arriva solo dopo la
risposta, riporta `running`. Senza questa correzione una tab con una domanda a scelta multipla
aperta resterebbe `running` per sempre. Il mapping è quindi in due metà, entrambe in
`HookInstaller`: statico per evento (`ClaudeHookInstaller.specs`, finisce nei comandi di
settings.json) e dipendente dal payload (`ClaudeHookStateMapper`, applicato dal CLI).

Il `SessionStart` porta un `source`: su `clear` (`/clear`, `/new`) e `resume` il CLI marca l'evento
`resetsAttention` (lo `state` resta `idle`), che nel reducer risolve il completamento in sospeso -
una ri-presa attiva della conversazione è, come il primo prompt, prova che te ne stai occupando.
Vedi `STATE_SCHEMA.md` per il dettaglio.

### Local Control API

Trasporto: Unix domain socket (`~/.relay/relay.sock`, override `RELAY_SOCKET`), JSON lines. Il
receiver (app, `AgentEventReceiver`) fa da server; il CLI (`relay-cli claude-hook`,
`AgentEventClient`) fa da client. Scelta: tutto il trasporto è codice nostro (Swift, testabile),
lo script hook è solo un thin wrapper - niente `nc`/`jq`/parsing shell.

In v1 la riga sul filo è un `AgentStateEvent` codificato JSON (vedi `STATE_SCHEMA.md`): un solo
tipo effettivo (`agent.state`), quindi nessun envelope `type`. `AgentEventType`
(`agent.session.start/state/notification/resume.set/session.end`) resta per quando serviranno
payload diversi; allora si introduce l'envelope.

```json
{
  "agent": "claude",
  "sessionId": "abc",
  "paneId": "11111111-2222-3333-4444-555555555555",
  "state": "needs_input",
  "source": "hook",
  "confidence": 1,
  "timestamp": "2026-07-02T08:45:48.123Z"
}
```

Ordine di consegna: ogni hook è un processo effimero con la sua connessione e il receiver drena
le connessioni in parallelo (un client bloccato non deve fermare gli altri), quindi il trasporto
non garantisce l'ordine tra eventi. Lo ristabiliscono a valle tre pezzi: i timestamp con frazioni
di secondo sul filo (millisecondi; il decode resta tollerante col formato storico senza frazioni),
il pump FIFO del coordinatore (un `AsyncStream` con un solo consumer sul MainActor - mai un `Task`
per evento, che non preserva l'ordine di enqueue) e la guardia di monotonicità nello store, che
scarta gli eventi più vecchi dell'ultimo applicato per tab (`WorkspaceStore.applyAgentState`).

Robustezza del socket: il path è unico e condiviso da ogni processo Relay, quindi va difeso dal
calpestamento tra istanze. Il receiver (a) prima di `unlink`+`bind` fa una `connect` di prova
(`UnixSocket.isListening`): se un owner vivo risponde rifiuta (`addressInUse`), così una seconda
istanza non ruba il socket alla prima (**no-stomp**); (b) osserva la runtime dir con un vnode
`DispatchSource` (non un timer) e **ri-binda** se il socket file sparisce sotto di lui, ma solo
quando è davvero assente (se esiste, un'altra istanza ne ha uno vivo: niente ping-pong). Senza il
self-heal un socket cancellato da fuori orfanava il receiver e la consegna moriva in silenzio,
congelando ogni badge sull'ultimo stato ricevuto. Il complemento a monte è il guard
single-instance basato sul path in `Relay.main` (vedi `STATE_SCHEMA.md`, single-instance), che
copre anche i lanci senza bundle id (`swift run`) che il guard di LaunchServices non intercetta.

### Hook Installer

Comandi (`relay-cli`, implementati in `HookInstaller`):

```text
relay-cli hooks setup       # installa gli hook Relay in ~/.claude/settings.json
relay-cli hooks uninstall   # rimuove solo gli hook gestiti da Relay
relay-cli hooks status      # riporta se sono installati
```

Regole (verificate a test):

- append, non replace: gli hook nostri sono marcati (`RELAY_MANAGED_HOOK=1` nel comando) e si
  aggiungono agli array esistenti - convivenza con Otty/ourterm preservata;
- idempotente: setup ripetuto non duplica (rimpiazza i propri entry);
- uninstall rimuove solo i marcati e ripulisce array/chiavi vuoti;
- validazione JSON prima e dopo, backup sempre (`.relay-backup-<epoch>`), scrittura atomica;
- override path via `RELAY_CLAUDE_SETTINGS` (test/automazioni: non tocca il vero `~/.claude`);
- il CLI dell'hook fallisce in silenzio (exit 0) per non rompere Claude;
- il path del CLI finisce nei comandi: pre-bundle è `.build/.../relay-cli`, col `.app` sarà nel
  bundle (Milestone 4).

## Aggregazione Stati E Badge

Lo stato risale la gerarchia prendendo il più severo:

```text
pane -> tab -> workspace (sidebar) -> dashboard / app icon
```

Severità: `needs_input` > `error` > `running` > `completed` non visto > `in sospeso` > `idle`.

| Stato | UI |
| --- | --- |
| `running` | spinner o indicatore working |
| `needs_input` | badge attention + notifica macOS |
| `idle` dopo lavoro | marker completed (forte), poi "in sospeso" (quieto) finché non ripreso |
| `error` | marker errore |
| `unknown` | nessun badge forte (ma un sospeso sopravvive alla fine sessione) |

Regole:

- distinzione **stato vs marker**: `running`/`needs_input`/`error` sono stati e il badge li mostra
  in base ad `agentState` finché lo stato cambia. `needs_input` resta finché la sessione è in attesa
  (si spegne quando rispondi a Claude e parte un nuovo hook), **non** alla semplice visita del pane;
- `attention` (`Tab.attention`, enum `AttentionLevel`) è il marker post-completamento a **tre
  livelli**, che distingue percezione ("l'ho visto") da risoluzione ("me ne sono occupato"):
  - `unseen` - completato (`running` -> `idle`) mentre il pane non era in vista: segnale forte
    (bump in cima alla sidebar, ring, notifica);
  - `pending` - "in sospeso", visto ma mai ripreso: segnale quieto e persistente (punto dimesso in
    sidebar, strato dedicato in dashboard). L'interazione col terminale **declassa** unseen ->
    pending, non spegne. Un completamento sulla tab in vista nasce direttamente `pending` (la
    percezione è già avvenuta). Sopravvive alla fine della sessione (`unknown`) e al riavvio
    (persistito come `pendingSince` nel `TabSnapshot`);
  - risoluzione: la **ripresa vera** della conversazione (prompt -> `running`, o `needs_input`/
    `error`: la sessione si è mossa) spegne il marker a qualunque livello; in alternativa il
    **dismiss esplicito** (card della dashboard) o la chiusura della tab. La **decadenza**
    (`AppSettings.pendingDecayHours`, default **12h**; `0` = opt-out esplicito, mai) spegne i sospesi
    diventati tali (misura da `attentionSince`, non dall'evento) più vecchi
    della soglia, applicata dal composition root nei momenti naturali (boot post-restore, ritorno
    in foreground, apertura dashboard) - niente timer;
- `idle` non genera rumore se la sessione era già idle;
- `completed` esiste solo come transizione dopo `running`;
- lo stop di un subagent non è il completamento del pane principale.

### Notifiche macOS

Le notifiche riusano le stesse regole anti-rumore dei badge. La decisione è pura e testabile
(`AgentStateReducer.notification(current:incoming:isVisible:)`): notifica alla **entrata** in
`needs_input` (non a ogni evento successivo) e al **completamento non visto** (running -> idle mentre
la tab non è in vista). Chiave: **"in vista" = tab selezionata *e* Relay in primo piano**. Lo store
calcola `isVisible = isSelected && appActive` in `applyAgentState` (`appActive = NSApp.isActive`,
passato dal composition root): se Relay è in background non la stai guardando davvero, anche se è la
tab selezionata, quindi il completato resta segnalato (`unseen`) e la notifica parte. Il marker
**non** si spegne al ritorno in foreground né alla selezione della tab: sparirebbe il segnale prima
che l'utente lo veda (aprire una tab completata mostra il ring verde + flash). La visita reale è
**interagire** col terminale (tasto o click, dal monitor locale), e anche quella non spegne:
**declassa** a "in sospeso" (`pending`), perché guardare non è occuparsene. Modello ispirato al
notification ring di cmux (analisi in `docs/research/CYCLES.md`), esteso col livello quieto.

Il segnale forte è un **ring colorato attorno al terminale** della tab in vista
(`AttentionRingView`, TerminalHostUI): verde = completato non visto (statico, con un flash
all'accensione e al ritorno in foreground), giallo/rosso pulsante = aspetta input/errore. Il ring
risponde solo a `unseen`: un sospeso non accende il bordo (useresti la shell con un ring verde
permanente addosso). Colori dai colori ANSI del tema, coerenti coi badge. Il suo observer
(`observeRing`) è separato dal `render()` del terminale e non scrive `attention`, così un
completamento sulla tab in vista accende il ring senza spegnersi da solo (nessun loop col reset
della visita). Le tab non in vista restano coi badge (tab bar); un'attività non vista (completamento
o `needs_input`) **bumpa** il workspace in cima alla sidebar - riordino reale e persistente, non un
float derivato (vedi "Ordine della sidebar" sotto). Il sospeso (`pending`) mostra un punto quieto -
anello vuoto - nel badge, senza ri-bumpare né far scendere la riga.

Lo store emette una `AgentNotification` (dato puro) via callback `onNotifiableTransition` -
`WorkspaceModel` resta senza AppKit (riceve solo il `Bool appActive`). Il composition root
(`NotificationCoordinator`) applica le preferenze utente (`AppSettings`: master, per-tipo, suono) e
sopprime `needs_input` se `isVisible`, poi consegna via `UNUserNotificationCenter`. Il coordinatore
è anche `UNUserNotificationCenterDelegate` e in `willPresent` ritorna `[.banner, .sound, .list]`:
senza, macOS **sopprime i banner quando Relay è l'app in primo piano**, e noi notifichiamo apposta
per le tab non in vista anche con l'app attiva. **Richiede il bundle `.app`** (serve un bundle id):
da `swift run` le notifiche sono disattivate, non è un errore.

### Dashboard delle sessioni

La control tower del triage: un **overlay effimero** a livello finestra (hotkey rimappabile,
default `Cmd+D`) con la griglia flat di tutte le sessioni agente, ordinata per urgenza
(`needs_input` > `error` > `unseen` > `pending` > `running` > idle/resume; a pari rango l'evento
più recente). L'unità è la sessione, non il workspace: col pattern d'uso reale (~1 tab agente per
workspace) le sezioni sarebbero solo overhead - l'appartenenza è un **chip colorato** sulla card
(colore stabile per workspace dai colori ANSI del tema). Ogni card: stato, titolo, chip, **età
dell'ultimo evento** ("aspetta input da 4m" pesa diverso da "lavora da 20s"), dismiss su hover per
i marker. Type-to-filter (titolo/workspace/cwd), frecce + Invio per saltare, Esc chiude.

Struttura: logica pura in `Panels/DashboardModel` (filtri, rank, età: testata), vista SwiftUI
(`DashboardView`), wiring nel composition root (`AppControllerDashboard` + overlay full-window in
`RootOverlayController`). Mentre l'overlay è aperto il monitor locale si fa da parte (i tasti vanno
al filtro; niente nav 1..9 né mark-read). Solo dati del model: la dashboard funziona anche per tab
sfrattate dal cap LRU o mai realizzate - una preview del terminale nelle card richiederebbe surface
vive ed è fuori scope. `Cmd+J` è il fratello cieco della dashboard: cicla prima l'attenzione fresca,
esauriti quelli i sospesi.

## Data Model

Stato V0 (in codice, `WorkspaceModel`), `@Observable`:

```text
WorkspaceStore { workspaces: [Workspace], selectedWorkspaceID }
Workspace      { id, name, rootPath?, pinned, tabs: [Tab], selectedTabID }
Tab            { id, title, hasCustomTitle, currentDirectory?, resume?,  // V0: una tab = terminale
                 agentState, attention (AttentionLevel), lastEventAt }   // runtime; il sospeso
                                                       // persiste come pendingSince nel TabSnapshot
```

Futuro (quando servono):

```text
Tab.paneTree   { split dei pane dentro una tab }    // split deprioritizzato dall'utente
AgentSession   { sessionId, agent, tabId, state, lastEventAt, resumeCommand, bypass }
AgentEvent     { sessionId, state, source, toolName?, reason?, timestamp }
```

- Il model è puro e osservabile: **nessun riferimento alle surface del terminale**. Le surface
  vive sono legate per `Tab.id` fuori dal model, in `SurfaceRegistry` (TerminalHostUI).
- Gerarchia prodotto: **Workspace -> Tab -> terminale**. Lo split (pane tree dentro una tab) è
  previsto ma deprioritizzato (l'utente non lo usa molto).
- Sidebar e tab bar leggono lo store e si aggiornano via Observation, senza toccare le surface.
- Persistence: snapshot JSON del layout su disco (vedi Persistence Del Layout). Niente database.

### Binding Surface (lazy, fuori dal model)

- `SurfaceRegistry` mappa `Tab.id -> TerminalSurfaceHandle`. La surface nasce alla **prima
  visita** della tab (lazy) e viene distrutta quando la tab non esiste più (reconcile via
  `retain(aliveTabIDs)`). Il PTY di una tab non visibile resta vivo.
- `WorkspaceAreaController` (AppKit) osserva lo store e scambia la view della surface attiva.
- Cap LRU sulle surface vive (`SurfaceRegistry.enforceLRU`, cap in `WorkspaceAreaController`): il
  cap è **soft**. Oltre budget si sfrattano le meno recenti **solo se idle** (`hasRunningChildren ==
  false`: shell senza figli, copre foreground/background/agente) e non protette: mai la visibile, le
  tab del workspace attivo, le tab con attenzione fresca (`needs_input`/`error`/`unseen`) o quelle
  usate negli ultimi ~30 minuti. Se tutte le candidate sono protette o vive, si resta sopra cap:
  meglio sforare che resettare contesto utile. Eviction = teardown della surface SwiftTerm:
  scrollback perso, shell ricreata alla cwd salvata al re-focus. La decisione
  (`SurfaceEvictionPolicy`) è pura e testabile.

### Persistence Del Layout

Il layout (workspace, tab, cwd, pin, ordine, nomi, selezione) sopravvive ai riavvii come snapshot
JSON in `~/.relay/layout.json` (override `RELAY_LAYOUT`; path iniettato, i test usano una dir
temporanea). Design:

- **Tipi**: `LayoutSnapshot`/`WorkspaceSnapshot`/`TabSnapshot` Codable puri in `WorkspaceModel`, con
  `version` per migrazioni. `WorkspaceStore.snapshot()`/`restore(from:)` convertono da/verso lo store.
  **Non** si persiste lo stato agente (effimero) né le surface.
- **I/O**: modulo `LayoutStore` (dipende solo da `WorkspaceModel`), scrittura atomica; `load()`
  ritorna `nil` su file mancante/corrotto/versione ignota, così il boot ricade sul seed di default e
  non crasha mai.
- **Quando salvare**: `LayoutAutosave` (composition root) osserva lo store e salva **debounced**
  (~500ms dopo l'ultimo cambio) + **flush sincrono** su `applicationWillTerminate`. Legge
  `snapshot()` dentro l'observation tracking: dipende solo dai campi persistiti, quindi gli eventi
  agente (cambi di `agentState`) non scatenano scritture.
- **Restore**: al boot i pane rinascono `unrealized` (la surface parte al primo focus), la shell
  riparte dalla cwd salvata; la selezione è validata contro i workspace ricostruiti.
- **Demo mode non persiste**: `relay --demo` non istanzia l'autosave, per non sovrascrivere il file
  reale.

### Resume

Ripristinare la sessione Claude di una tab dopo un riavvio (il PTY muore, la sessione finisce):

- `ResumeBinding {agent, sessionId, label}` su `Tab`, persistito nel `TabSnapshot`. Catturato da
  `WorkspaceStore.applyAgentState` (agent + sessionId dagli hook) mentre la sessione è viva, azzerato
  su `SessionEnd` (`unknown`). `label` = titolo della tab alla cattura: la shell fresca ridipinge il
  titolo via OSC, il binding lo conserva per la barra.
- Il binding ripristinato è protetto dagli hook di sessioni morte, che il `RELAY_TAB_ID` stabile tra
  i riavvii farebbe atterrare sulla tab ricostruita: la **soglia anti-stantio** (`eventFloor`) scarta
  gli hook eseguiti prima del boot, il **fence di run** (`runID` = `RELAY_RUN_ID`, nonce per
  processo) scarta quelli eseguiti dopo ma nati da una run precedente (claude orfani sopravvissuti al
  riavvio). Senza, uno `Stop` orfano toglieva la tab da `unknown` o un `SessionEnd` azzerava il
  binding, e la barra non compariva.
- Al restore la tab è `pendingResume` (binding presente + `agentState == unknown`). Al **primo
  focus** (lazy, un agente alla volta, non un big-bang al boot) `RightPaneController` mostra la barra
  `ResumeBar` (Panels) overlaid sul terminale: `Resume` inietta `claude --resume <id>` nel PTY
  (`surface.sendText`), la x scarta. Il setting `autoResumeAgents` (default off) salta la barra e
  inietta da solo, con un piccolo ritardo per far arrivare la shell al prompt.
- La LRU non interseca: una tab con Claude vivo ha processi figli -> non è sfrattabile, quindi il
  resume serve solo dopo un riavvio, non dopo uno sfratto.

Si salva solo: `sessionId`, `agent`, `cwd`, `label`. Mai prompt, token, chiavi, credenziali.

## Data Flow

### Agent State Flow

```text
Claude Code hook
  -> hook adapter (script)
  -> unix socket receiver
  -> agent runtime (normalizzazione + binding paneId)
  -> workspace store (aggregazione)
  -> sidebar/dashboard/badge + notifica
  -> timeline
```

### Terminal Flow

```text
User input -> focused pane -> TerminalEngine surface / PTY -> processo -> output -> render view
```

### Restore Flow

```text
App launch
  -> LayoutStore.load() (file mancante/corrotto -> seed default)
  -> WorkspaceStore.restore(from:) (tutti i pane unrealized)
  -> LayoutAutosave.start() (salvataggio debounced sui cambi successivi)
  -> al primo focus di un pane: realizza surface, ripristina cwd
  -> resume agente opzionale con comando sanitizzato (fuori scope M2)
  -> rebind degli stati in arrivo per sessionId/paneId
```

## Anti-Pattern cmux (Da Non Ripetere)

Evidenze raccolte nel Cycle 3 su `repos/cmux`:

1. **Priming eager dei workspace in background**
   (`BackgroundWorkspacePrimeCoordinator.primePendingBackgroundWorkspaces`): crea surface per
   workspace non visibili. Con molti workspace la memoria e il main thread saturano.
2. **Mitigazioni a valle invece che design a monte**: `PaneMemoryGuardrail`,
   `AgentHibernation/`, discard delle webview sotto memory pressure. Esistono solo perché la
   base sovra-alloca.
3. **View tree SwiftUI monolitico**: `ContentView.swift` da 16.484 righe, 140 file con SwiftUI;
   sidebar e host terminale condividono invalidazioni.
4. **File monstre**: `GhosttyTerminalView.swift` 12k righe, `Workspace.swift` 13k righe.

Conclusione chiave: il lag di cmux è architetturale, non dell'engine (cmux usa GhosttyKit, il
massimo delle performance di rendering, e lagga comunque). Quindi è evitabile a prescindere
dall'engine che scegliamo; ma "veloce" non è gratis, è disciplina su questi quattro punti.
Corollario: con SwiftTerm (rendering CoreText) la disciplina conta ancora di più, ma il collo
di bottiglia reale resta l'architettura, non il parser.

## Fuori Scope Baseline

- browser automation;
- iOS companion;
- cloud VM / presence / sync;
- remote tmux avanzato;
- skill marketplace;
- hibernation automatica agenti (non deve servire, by design);
- orchestrazione multi-agent complessa;
- hook per tutti gli agenti (si parte da Claude Code, il protocollo resta aperto).

## Rischi Tecnici

### Rendering Throughput SwiftTerm

- Rischio: rendering CoreText più lento del GPU di ghostty con output molto rapido (agenti
  verbosi, `cat` di file grossi).
- Mitigazione: backend Metal opzionale di SwiftTerm; scrollback cap; coalescing degli update di
  output; misurare nello spike contro i budget. Se emergesse un limite reale e non aggirabile,
  scatta il piano libghostty dietro `TerminalEngine` (motivo per cui l'astrazione esiste).

### VT Processing In Background

- Rischio: molti pane `live-hidden` con output massiccio (agenti verbosi) costano CPU anche
  senza view di rendering.
- Mitigazione: scrollback cap; misurare nello spike; eventuale throttling della frequenza di
  aggiornamento per pane nascosti.

### Astrazione Engine Non A Tenuta

- Rischio: `TerminalEngine` modellato troppo intorno a SwiftTerm, rendendo cara la migrazione a
  libghostty.
- Mitigazione: tenere l'interfaccia sottile e orientata alle capacità (input/output/dimensioni/
  eventi), non ai tipi SwiftTerm; nessun tipo SwiftTerm deve trapelare fuori da `TerminalEngine`.

### UI Latency

- Rischio: sidebar/badge invalidano UI durante il typing.
- Mitigazione: confine AppKit/SwiftUI sopra; store a grana fine; misurare con budget dichiarati.

### Session Binding

- Rischio: `sessionId` non legato al pane giusto.
- Mitigazione: env iniettata per pane al lancio di `claude`; mapping `sessionId -> paneId`
  persistito; `pid`, `cwd`, `tty` come segnali secondari.

### Hook Config

- Rischio: interferire con Otty o hook utente.
- Mitigazione: installer idempotente, backup, marker propri, append non replace, uninstall
  pulito.

## Decisioni Da Chiudere

1. Nome prodotto e repo (candidato: Relay, con riserve sul clash GraphQL).
2. Engine v1 SwiftTerm chiuso (Cycle 5); resta da definire la soglia oggettiva che farebbe
   scattare il passaggio a libghostty.
3. Dettaglio budget performance dopo misure reali dello spike.
4. Formato protocollo v1 definitivo.
5. Strategia di distribuzione hook (firma, bundle, path).

## Stato Attuale

Validato:

- pipeline hook Claude -> receiver -> state store (Cycle 1);
- installazione hook in parallelo a Otty;
- mapping stati base;
- diagnosi lag cmux e regole anti-pattern (Cycle 3).

Deciso e validato (Cycle 5):

- engine v1 SwiftTerm dietro `TerminalEngine`, libghostty backend futuro;
- throughput SwiftTerm sufficiente: core VT 34-82 MB/s, end-to-end 20 MB/s, ampiamente sopra i
  ritmi degli agenti (benchmark in `docs/research/spikes/swiftterm-spike/`);
- cap scrollback confermato come leva di memoria giusta.

Costruito (V0, Cycle 6):

- app reale: Workspace -> Tab -> terminale, con sidebar (crea/seleziona/pin/riordina) e tab bar
  (crea/seleziona/chiudi);
- surface lazy per `Tab.id` con teardown per reconcile; terminale AppKit, chrome SwiftUI isolata;
- workspace folder-less (`Cmd+N`, parte da home) e da cartella (`Cmd+O`); `Cmd+T`/`Cmd+W` tab;
- navigazione a due assi stile cmux via event monitor: `Cmd+1..9` workspace, `Option+1..9` tab.

Costruito (Milestone 1, agent runtime + badge):

- receiver Unix socket + client in `AgentRuntime`; wire = `AgentStateEvent` JSON line;
- binding `RELAY_TAB_ID` (= `Tab.id`) iniettato per surface, rimandato dall'hook come `paneId`;
- `relay-cli hooks setup|uninstall|status` (idempotente, backup, convivenza Otty) e
  `relay-cli claude-hook <state>` (client emit, fail-safe);
- stato agente su `Tab` (`agentState`, `attention`, `lastEventAt`); reducer puro con anti-rumore;
  applicazione evento -> tab in `WorkspaceStore.applyAgentState`, orchestrata dal coordinatore
  (`AgentCoordinator`) nel composition root;
- badge in tab bar (per tab) e sidebar (workspace, aggregato per severità + contatore se ≥2 tab
  condividono lo stato); `needs_input`/`error` sono stati (restano finché rispondi), `completed` è
  transitorio (si spegne alla visita);
- test: socket end-to-end, installer (fixture + round-trip su disco), reducer, apply su store;
  `make check` verde. Validazione GUI live (badge che cambia con Claude reale) da fare a mano.

Costruito (UI/UX e tooling, fuori milestone):

- sistema di temi (`RelayTheme` in `Core`): terminale + chrome + badge coerenti, due temi
  (Dark/Light), pannello impostazioni (`Cmd+,`), zoom font (`Cmd +/-`), persistiti in `UserDefaults`;
- chrome full-size content view: appearance che segue il tema, titolo contestuale centrato sul body
  (`WindowTitle`/OSC 7), toggle sidebar (`Cmd+B`) come overlay che insegue il bordo della sidebar,
  sottotitolo per workspace, `Cmd+T` che eredita la cwd corrente;
- interazione e chiusura: lista workspace custom (`LazyVStack`, no highlight di sistema sul menu
  contestuale), padding riga allineato all'header, riordino di workspace e tab via drag & drop
  (`Panels/Reorderable`: `DragGesture` + `.offset` + linea di inserimento, non `onDrag`/`onDrop` di
  sistema che al rilascio farebbero snap-back; i frame di riga sono misurati **dopo** l'`.offset`
  del drag, dentro `reorderableRow` - un GeometryReader sotto l'offset ne assorbe la traslazione,
  il centro proiettato la raddoppiava e la linea di inserimento derivava con la distanza; store
  posizionale `moveWorkspace(before:/after:)` /
  `moveTab(before:in:)`; nella sidebar la linea è libera e il drop è risolto dal resolver puro
  `SidebarDrop`: il drag edita direttamente l'ordine canonico - due segmenti, pinned/resto -
  attraversare il blocco pinned pinna/spinna), x di chiusura su
  hover per tab e workspace, rename inline del workspace dal menu contestuale; **Ordine della
  sidebar** "lista chat": un'attività **non vista** (`needs_input`/completato) **bumpa** il workspace
  in cima ai non-pinned (`WorkspaceStore.bumpWorkspaceToTop` da `applyAgentState`) - riordino reale e
  persistente, non un float derivato; la posizione resta finché non la scavalca un altro bump o non
  la sposti a mano (la ripresa non la muove); archivio dei workspace (`Workspace.archived`)
  in una sezione collassabile in fondo alla sidebar (menu `Archive`/`Unarchive`); conferma di
  chiusura se nel pty gira un comando in foreground; ultima tab
  chiude il workspace, ultimo workspace ne riapre uno default;
- tooling di test: `relay-cli simulate` e `relay --demo NxM`, entrambi sul socket reale.

Costruito (Milestone 2, persistence + rename):

- rename inline di workspace e tab dal menu contestuale (rispetta `hasCustomTitle`);
- persistence del layout: `LayoutSnapshot` Codable (`WorkspaceModel`) + modulo `LayoutStore` (I/O
  atomico su `~/.relay/layout.json`, versionato) + `LayoutAutosave` (debounced-live + flush on quit);
  restore al boot con pane `unrealized`, demo mode esclusa; smoke test end-to-end save+restore.

Costruito (resume agenti, follow-on M2):

- resume assistito delle sessioni Claude: `ResumeBinding` catturato dagli hook e persistito, barra
  `ResumeBar` al primo focus della tab ripristinata (o auto-inject col setting `autoResumeAgents`),
  `surface.sendText` inietta `claude --resume <id>`. Solo sessionId/agent/cwd/label salvati. Vedi
  #Resume.

Costruito (Milestone 3):

- cap LRU soft sulle surface vive (`SurfaceRegistry.enforceLRU` + `SurfaceEvictionPolicy` pura, cap
  in `WorkspaceAreaController`): sfratta le meno recenti solo se idle e non protette; tiene la
  visibile, il workspace attivo, l'attenzione fresca, le tab recenti e quelle con lavoro vivo;
- misure di performance chiuse (`docs/research/PERF.md`), strumentazione `RELAY_PERF` integrata:
  latenza input aggiunta dallo shell max 2.4µs (budget 16ms p99, ~4 ordini di grandezza di margine),
  ~0.3-0.5 MB per surface idle e ~98 MB con 30 surface vive. Cap confermato a 12, knob
  `RELAY_SURFACE_CAP` per ri-tarare;
- pannello Runtime Stats (`View > Runtime Stats…`) per vedere RSS, CPU del processo, workspace/tab
  e surface vive/cap con campionamento on-demand solo mentre la finestra è aperta.

Costruito (Milestone 4, bundle + notifiche):

- bundle `.app` (`make bundle`): `bundle/Info.plist` (bundle id `dev.relay.app`) + icona + firma
  ad-hoc, `make run-app` lo avvia. Sblocca le notifiche (serve un bundle id);
- icona dell'app generata proceduralmente (`bundle/make-icon.swift`, Core Graphics headless ->
  `bundle/AppIcon.icns` via `make icon`): prompt terminale (chevron accento + cursore a blocco) su
  squircle scuro della palette Relay Dark;
- installer: `make dmg` (`.build/Relay-<version>.dmg`, drag su /Applications) e `make install-app`.
  Distribuito via Homebrew tap (`brew install --cask essedev/relay/relay`), firma self-signed
  stabile; Developer ID + notarizzazione ancora da fare;
- notifiche macOS su `needs_input`/completato (`NotificationCoordinator` +
  `UNUserNotificationCenter`), classificazione pura nel reducer, preferenze in `AppSettings`
  (master, per-tipo, suono + scelta suono). Vedi #Notifiche macOS;
- dodici temi curati (Solarized, Gruvbox, Tokyo Night, Catppuccin e GitHub oltre a Relay
  Dark/Light) e scelta font family.

Costruito dopo (dashboard + distribuzione + hardening):

- dashboard di triage (`Cmd+D`) e attenzione a tre livelli (unseen/pending/risolto);
- distribuzione via Homebrew tap; relay-cli impacchettato nel `.app` + azione in-app per installare
  gli hook (Impostazioni > Agents);
- giro di hardening (self-heal socket, fail-safe SIGPIPE, robustezza persistence, validazione
  input resume, pruning backup, recovery della release).

Da fare dopo:

- distribuzione firmata Developer ID + notarizzazione (toglie l'"Apri comunque");
- split (pane tree dentro una tab), deprioritizzato; generalizzazione multi-agente (Codex/opencode).
