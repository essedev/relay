# Architecture

Progetto: **Relay**.
Ultimo aggiornamento: 2026-08-08.

Documento vivo: budget, moduli e confini si rivedono quando misure o sviluppo portano evidenze
nuove. La storia decisionale completa (cicli 0-8: analisi engine, diagnosi lag cmux, benchmark
SwiftTerm) vive in `docs/research/` (`CYCLES.md`); qui si tiene lo stato corrente.

## Tesi Di Prodotto

Un terminale macOS nativo per lavorare con molti coding agent in parallelo. Combina:

- gli stati agente affidabili (hook Claude Code e Codex, non parsing dell'output);
- l'organizzazione a workspace di cmux (progetti che raggruppano tab, sidebar, pin, riordino);
- una dashboard overview di tutti i progetti e i loro agenti;
- velocità e leggerezza dove cmux lagga.

Il centro del prodotto non è "un terminale con badge": è organizzare e sorvegliare N progetti con
agenti attivi da un posto solo, calmo e rapido. Il terminale è il substrato.

Non è un fork di cmux. È una nuova app che usa:

- **SwiftTerm** come terminal engine v1, dietro un'astrazione sostituibile (`TerminalEngine`);
- cmux come reference di prodotto e come catalogo di anti-pattern di performance;
- Otty come reference comportamentale per gli stati agente;
- hook Claude Code e Codex come fonti autorevoli del lifecycle agente.

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
memoria per surface. Gli switch di workspace (< 50ms / < 300ms) restano target non misurati.
**Cap dello scrollback per surface**: implementato, **10.000 righe** (`changeHistorySize` in
`SwiftTermSurface.start`, contro le 500 di default: la ricerca deve vedere lo storico di una
sessione agente). Le due leve di memoria sono quindi il cap di righe per surface e il cap LRU sulle
surface vive.

## Modello Di Prodotto

```text
App (uno store, un receiver, una SurfaceRegistry)
  Window 1..N (partizione dei workspace)
    Sidebar (sinistra)
      Sezione pinned (workspace e gruppi pinnati)
      Lista workspace di QUESTA finestra (drag per riordinare)
        Gruppo (card colorata: header + i suoi workspace, collassabile)
      Sezione Archive
    Content
      Workspace selezionato da QUESTA finestra
        Albero di split -> pane, ognuno con la SUA strip di tab
          (visibile = la selezionata di ogni strip, focused = riceve la tastiera)
    Dashboard (overlay full-window sopra il workspace attivo)
```

- **Workspace**: un progetto (tipicamente una cartella/repo). Raggruppa tab. Ha nome, cwd di
  default, pin, archiviazione, **gruppo** (`groupID`), posizione in sidebar, stato agente aggregato,
  **finestra** (`windowID`) e **layout dei pane** (`layout`, sempre presente).
- **Gruppo** (`WorkspaceGroup`): una card colorata della sidebar attorno a dei workspace. Porta solo
  identità e aspetto (nome, colore, collasso, pin del blocco): **l'appartenenza vive sul workspace**,
  quindi non c'è una lista di membri da tenere in sync con l'ordine canonico e la posizione della
  card è quella del suo primo membro. Un gruppo senza membri non esiste.
- **Tab**: una sessione terminale. È **l'unità a cui si lega una sessione agente** (`RELAY_TAB_ID`
  = `Tab.id` = surface = badge = attention = resume = card della dashboard).
- **Pane** (`SplitPane`): una porzione di schermo che **ospita** una lista ordinata di tab con la
  sua selezione e la sua strip (modello cmux/bonsplit). Ospita, non possiede: spostare una tab non
  ne cambia l'identità né tocca la sua sessione.
- **Finestra**: un contenitore di workspace, non di sessioni. Nessuna è privilegiata.
- **Dashboard**: overview read-only di tutti i workspace con stato agenti, ultimo evento e
  jump-to al click. v1 volutamente minimale.
- **Gruppi di workspace**: fuori dalla v1, il data model non deve impedirli.

Due design precedenti sono stati superati, in due giri:
1. il pane tree *dentro* la Tab (design originale): la Tab *è già* l'unità agente (il wire la
   chiama `paneId`), spostare l'attention model più in basso costava il doppio;
2. le foglie-tab con tab bar globale (split v1): tab bar e pane erano due viste dello stesso
   insieme con la semantica ambigua "montata vs selezionata", e non esisteva un posto naturale per
   "una tab accanto a una porzione". Ora **i pane ospitano le tab** (v2, il pattern di cmux): ogni
   pane ha la sua strip, la tab bar globale non esiste più, e le finestre restano una
   **partizione** dei workspace su un solo store. Dettagli e migrazione:
   `docs/features/split-panes.md`.

Da qui nascono due nozioni che vanno tenute distinte leggendo il codice:

- **visibile** (`Workspace.isVisible`) = la tab è a schermo (selezionata nella strip del suo
  pane). Guida tutto ciò che significa "la stai guardando": ring, mark-read, protezione dal cap
  LRU, soppressione di notifica e bump.
- **focused** (`Workspace.focusedPaneID`; `selectedTabID` ne è la selezione, **derivata**) = il
  pane che riceve la tastiera e i comandi (`Cmd+K`, find). Con uno split è **uno** dei visibili.

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

  Servizi di rete (solo nel composition root)
    NamingController + ChatCompletionClient   nomina workspace (LLM opzionale)
    UpdateController                          check della GitHub Release

  CLI (relay-cli)
    hooks setup/uninstall/status [claude|codex|all]
    claude-hook/codex-hook <state>, simulate
```

Nota: non c'è (ancora) una timeline degli eventi né un session store persistente: `AgentRuntime`
fa solo trasporto, il binding evento -> tab e l'aggregazione vivono in `WorkspaceModel`.

**Uscite verso la rete, due e solo due**, entrambe confinate nel composition root perché nessun
modulo di dominio deve poter fare I/O di rete: la **nomina automatica dei workspace**
(`NamingController` decide *quando*, `ChatCompletionClient` fa la chiamata all'endpoint
OpenAI-compatible, `NamingCredentialStore` tiene la API key in un file `0600` fuori da UserDefaults;
la logica pura di prompt/parse/trigger sta in `Core.WorkspaceNaming` e `Core.NamingTriggerPolicy`) e
il **check aggiornamenti** (`UpdateController` interroga la GitHub Release, con confronto versioni e
parsing puri in `Core.SemanticVersion`/`ReleaseCheck`; non scarica nulla, propone il comando brew).
Entrambe sono opt-out dalle impostazioni. La nomina **non dipende** dalla rete: senza API key i nomi
li deriva `Core.WorkspaceNaming.localNames` (regola pura, zero I/O) con gli stessi trigger, e la
chiamata al modello è l'upgrade opzionale.

## Struttura Repo E Moduli

Monolite modulare: **un solo package SwiftPM** con molti target (moduli). Il confine tra moduli è
imposto dal compilatore (dipendenze dichiarate in `Package.swift`), non dalla buona volontà. È la
contromisura strutturale ai file da 12-16k righe e agli `AppDelegate+X` di cmux.

```text
repo/
  Sources/
    Core/               primitivi condivisi e logica pura: logging, tema, OSC7, escaping, matcher
                        di ricerca, versioni, prompt/policy della nomina; nessuna dipendenza
    AgentProtocol/      tipi evento e stati (AgentStateEvent); puro, niente I/O
    AgentRuntime/       socket receiver + client, runtime paths; puro, niente AppKit
    WorkspaceModel/     store workspace/tab, reducer stati, attention, persistence, settings,
                        contenuto della guida utente (dato, reso in due modi: vedi sotto)
    TerminalEngine/     backend SwiftTerm dietro un'astrazione, surface lifecycle
    TerminalHostUI/     AppKit: host view, surface registry (lazy + LRU), attention ring
    Panels/             SwiftUI: sidebar, strip dei pane, dashboard, settings, guida, stats, badge
    HookInstaller/      installer JSON Claude/Codex + mapping hook -> stato
    LayoutStore/        persistence layout: snapshot JSON su disco (I/O), path iniettato
    relay/              eseguibile `relay` (RelayApp): composition root e wiring
    relay-cli/          eseguibile `relay-cli`: hooks, claude-hook/codex-hook, simulate, guide-md
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
- `relay-cli` dipende da `Core`, `AgentProtocol`, `AgentRuntime` (client socket), `HookInstaller` e
  `WorkspaceModel` (la guida come dato, per generare `docs/GUIDE.md`): niente dipendenze dal target
  app;
- `relay` è solo composition root: se cresce oltre il wiring, manca un modulo.

Disciplina di codice, test e processo: `docs/CONVENTIONS.md`.

### Confine AppKit / SwiftUI

- **AppKit**: finestre, split tree, host della terminal surface, focus, tastiera. Tutto il path
  sensibile alla latenza.
- **SwiftUI**: solo pannelli isolati (sidebar, dashboard, settings), ognuno montato in un
  `NSHostingView` proprio, che osserva store a grana fine (Observation framework). Un
  cambiamento di badge invalida la riga della sidebar interessata, non altro.

## Terminal Runtime

### Lifecycle Della Surface

Il cuore anti-lag. Due stati per tab, più la distinzione fra a schermo e fuori schermo:

```text
unrealized --primo focus--> live (a schermo o fuori) --sfratto LRU--> unrealized
```

- `unrealized`: nessun PTY, nessun emulatore, nessuna view. Solo metadata (cwd, titolo, resume
  binding). È lo stato di ogni tab al restore e di ogni workspace mai visitato.
- `live`: PTY + emulatore + view attivi. Nasce al primo focus e **resta viva anche fuori schermo**
  (la tab non selezionata nella strip del suo pane, il workspace di sfondo): in SwiftTerm la view
  *è* l'emulatore, quindi non esiste uno stato intermedio "emulatore vivo, view rilasciata".

Non esiste un terzo stato: l'uscita da `live` è lo **sfratto LRU**, che è un teardown vero (view,
emulatore e PTY), non una sospensione. Lo scrollback di quella tab si perde e la shell viene
ricreata alla sua cwd al focus successivo. Per questo lo sfratto è **conservativo**: colpisce solo
le surface idle (`hasRunningChildren == false`) e non protette (mai la visibile, le tab del
workspace attivo, quelle con attenzione fresca, quelle usate negli ultimi ~30 minuti).

Regole:

- **Una tab possiede la sessione POSIX della sua pty.** Sono suoi la shell che `forkpty` ha reso
  session leader e i process group nati sotto quel controlling terminal: il teardown li chiude
  tutti. Un processo che si è staccato apposta (`setsid`, o un `nohup` che ha abbandonato la
  sessione) esce da quel perimetro e non lo inseguiamo. È l'invariante che dice cosa "terminare una
  tab" significa, e senza di lei il perimetro del kill sarebbe arbitrario.
- **Il teardown lo fa Relay, non l'engine** (`TerminalEngine.PtySessionTeardown`): SIGHUP al gruppo
  in foreground e a quello della shell, poi escalation a SIGTERM e SIGKILL, poi `waitpid`.
  `LocalProcessTerminalView.terminate()` di SwiftTerm da solo non chiude niente, e senza questo
  passaggio ogni tab chiusa lasciava dietro shell, agente e descrittore della pty. Il perché sta nel
  tipo; i numeri del leak e la riproduzione in `docs/research/PERF.md`.
- PTY ed emulatore restano vivi finché il processo figlio vive: mai uccidere un agente che lavora
  perché la sua tab è fuori schermo. È l'invariante che rende il cap un *soft* cap.
- La creazione è sempre lazy: al restore nessuna view nasce; nasce al primo focus.
- Il cap di scrollback per surface è **10.000 righe** (i transcript lunghi di Claude non devono
  gonfiare la memoria di ogni tab viva, ma la ricerca deve vedere lo storico della sessione).
- La chiusura dell'app termina i PTY: il restore riparte da `unrealized` + resume command.

Con SwiftTerm l'unità viva è `LocalProcessTerminalView` (NSView + PTY): view, emulatore e processo
sono lo stesso oggetto, e la libreria non permette di scollegare la view tenendo l'emulatore. È il
motivo per cui il lifecycle ha due stati e non tre: il lazy/LRU si applica creando e distruggendo
quella view. Una view fuori schermo resta comunque **attaccata** (fuori dalla gerarchia visibile ma
viva); il rendering la scambia nel pane (`attachTerminal`), non la ricrea.

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
- la chrome (`Panels`) converte in SwiftUI Color (`ChromeColors`): sidebar/strip/badge dal tema;
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
(Appearance / Terminal / Agents / Notifications / Updates / Shortcuts), contenuto a destra. Ogni voce è un "blocco"
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
  osservabile), con toggle case/word/regex. Navigazione, contatore e match corrente vengono dal
  motore di SwiftTerm (`TerminalSurfaceHandle.search`, autorevole su tutto il buffer); tutti i match
  visibili sono evidenziati da un overlay che Relay disegna da sé perché SwiftTerm non espone le
  posizioni dei match (`RelayTerminalView+Search` + `Core.TerminalSearchMatcher` puro). Scrollback
  esteso a 10k perché la ricerca veda lo storico; a ricerca attiva il mouse reporting è forzato
  spento così la posizione sopravvive all'output in streaming; lo stato è legato alla tab su cui la
  barra è aperta. Dettagli e limiti nel gotcha "Ricerca" del CLAUDE.md di progetto. `Cmd+K`
  pulisce il terminale (`clear`), `Cmd+J` salta alla prossima tab in attenzione
  (`WorkspaceStore.focusNextAttention`). Sono azioni rimappabili (vedi sotto), gestite dal monitor
  così scattano anche col terminale in focus.
- Dashboard (`Cmd+D`): overlay full-window sopra tutto (`RootOverlayController.presentFullOverlay`)
  con la griglia delle sessioni agente - vedi #Dashboard-Delle-Sessioni.
- Runtime Stats (`View > Runtime Stats…`): pannello read-only separato dalle Settings (non è una
  preferenza), con RSS, CPU del processo, conteggi workspace/tab e surface vive/cap. Campiona solo
  mentre la finestra è aperta; a regime non aggiunge polling.
- Onboarding ("Welcome to Relay"): overlay full-window al primo avvio (flag
  `AppSettings.onboardingSeen`, mai in demo mode), riapribile da Help > Welcome to Relay. Sei
  pagine coi componenti veri del design system al posto di screenshot (badge live, keycap dai
  binding correnti, temi selezionabili dal vivo, icona procedurale `RelayMarkView`); la pagina
  hook riusa `AgentHooksBlock` per Claude Code e Codex (stato + install). Logica di navigazione pura
  (`OnboardingModel`, testata), wiring in `AppControllerOnboarding`.
- Gli overlay full-window sono avvolti in un container che chiude i buchi di hit-testing (il
  mouse non passa mai al terminale sotto) e disattivano le cursor rects della finestra finché
  sono su (quelle di SwiftTerm non rispettano l'occlusione: I-beam sopra l'overlay).
- Sidebar: `NSSplitViewItem` normale, **non** `sidebarWithViewController:` (su macOS 26 quello stila
  la sidebar come pannello glass flottante, in conflitto col design flat themed). Righe con
  selezione/hover dai colori del tema (niente highlight di sistema), sottotitolo per riga
  (`WindowTitle.workspaceSubtitle`: cosa succede nella tab selezionata) e badge aggregato.
- Struttura della sidebar: righe libere, **card dei gruppi** (header + membri rientrati, vedi
  `docs/features/workspace-groups.md`) e la sezione Archive ancorata in fondo. Il rendering è
  annidato (la card si disegna attorno ai suoi membri) ma il drag lavora su un **piano piatto** di
  righe e slot (`SidebarLayout`): ogni slot porta scritto in quale contenitore si rilascia, deciso
  alla costruzione e non da euristiche sui vicini. Il drop è risolto dal puro `SidebarDrop`
  (contenitore + ancora canonica) e la meccanica del gesto vive in `SidebarReorder`, separata da
  `Reorderable` (che resta per la strip dei pane) perché qui il gesto attraversa due `ScrollView`.
- OSC 7: la cwd riportata dalla shell (`Core.OSC7` -> `Tab.currentDirectory`) alimenta titolo e
  sottotitolo. L'ereditarietà cwd di `Cmd+T` **non** si fida solo di lei: la precedenza è
  **shell viva -> ultimo OSC 7 noto -> root del workspace**, decisa dal puro `Core.CurrentDirectory`
  e applicata in `WorkspaceAreaController.currentDirectory(for:)`. La shell viva
  (`TerminalSurfaceHandle.currentDirectory()`, via `proc_pidinfo`) vince perché zsh in Relay non
  emette OSC 7 (`/etc/zshrc` carica l'integrazione da `/etc/zshrc_$TERM_PROGRAM` e noi non settiamo
  `TERM_PROGRAM`, vedi kitty keyboard) e perché, quando arriva, è ferma all'ultimo prompt. L'ultimo
  valore noto serve alle tab non realizzate, dove la shell non esiste. Così la nuova tab parte dove
  stai lavorando, non alla radice del workspace.

## Scorciatoie (keybinding rimappabili)

Le azioni sono un enum puro (`ShortcutAction`, in `WorkspaceModel`) con label, gruppo e combo di
default; la combinazione è `KeyCombo` (tasto normalizzato + modificatori, `Codable`, indipendente da
AppKit). `AppSettings` tiene il dizionario `[ShortcutAction: KeyCombo]`, persistito in UserDefaults
(JSON), con default e rilevamento conflitti.

**Un solo punto di dispatch**: tutte le azioni rimappabili passano dall'`NSEvent` local monitor del
composition root, **non** dai `keyEquivalent` di menu (che non gestiscono ogni combinazione, es.
Option-only o `Ctrl+Tab`). Il monitor converte l'evento in `KeyCombo` (`KeyEventBridge`, in Panels
così lo usa anche il recorder), cerca l'azione nei binding e chiama `perform(action)`
(`ShortcutRuntime`). Le voci di menu portano la combo come **`keyEquivalent` vero** (la colonna
nativa delle scorciatoie, come ogni app macOS: mostrarla nel titolo era una resa estetica), e il
doppio trigger non c'è perché il monitor **consuma** l'evento prima che arrivi al menu. Quando il
monitor si fa da parte (dashboard o onboarding aperti) i keyEquivalent tornerebbero vivi: lì
`validateMenuItem` disabilita le voci dell'AppController tranne il toggle della dashboard. I menu si
ricostruiscono al cambio binding (`observeKeybindings`). Restano fissi i comandi di sistema
(Copy/Paste/Select All via responder, Quit, Settings, Hide/Minimize/Full Screen) e i
select-by-number.

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

- hook Claude Code e Codex: fonti autorevoli;
- futuro: plugin OpenCode;
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
| `StopFailure` | `error` |
| `SessionEnd` | `unknown` |

`StopFailure` è l'unica fonte di `error`: scatta quando il turno finisce per un errore API. Il suo
matcher è il tipo di errore (`rate_limit`, `overloaded`, `authentication_failed`, `billing_error`,
`server_error`, `max_output_tokens`, ...) e noi lo installiamo **senza matcher**, che equivale a
`"*"`: tutti i tipi collassano nello stesso stato `error`. La distinzione la legge l'utente dal
terminale; la tab deve solo dire "qui si è fermato, serve la tua mano". Senza questo hook un turno
morto per errore non produce nessun evento - `Stop` copre solo la fine normale - e la tab resta
`running` per sempre, con lo spinner acceso su una sessione ferma: era il buco più grosso del
runtime, perché il caso d'uso di Relay è proprio la sessione che si pianta mentre guardi altrove.

`SubagentStop` non è mappato: lo stop di un subagent non è il completamento del pane. `PostToolUseFailure`
neanche: un tool che fallisce dentro un turno che prosegue non è un errore di sessione. Nomi hook
confermati sulla doc Claude Code corrente (settembre 2026). Nota: nello spike gli stati usano i nomi
Otty (`processing`, `awaiting`, `idle`); nell'app si usano i nomi prodotto qui sopra.

I tool che aprono un prompt bloccante (`AskUserQuestion`, `ExitPlanMode`) non passano da
`PermissionRequest` (non sono permessi) e non producono `Stop` finché l'utente non risponde: il
loro `PreToolUse` viene corretto in `needs_input` dal CLI (`ClaudeHookStateMapper`, che legge
`hook_event_name` e `tool_name` dallo stdin dell'hook); il `PostToolUse`, che arriva solo dopo la
risposta, riporta `running`. Senza questa correzione una tab con una domanda a scelta multipla
aperta resterebbe `running` per sempre. Il mapping è quindi in due metà, entrambe in
`HookInstaller`: statico per evento (`ClaudeHookInstaller.specs`, finisce nei comandi di
settings.json) e dipendente dal payload (`ClaudeHookStateMapper`, applicato dal CLI).

Mapping Codex: stesso lifecycle di base (`SessionStart`, `UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `PermissionRequest`, `Stop`, `SessionEnd`) più `Interrupt`. L'installer scrive
`~/.codex/hooks.json`; `Interrupt` è `idle` con `resetsAttention`, quindi non finge un
completamento. Codex non espone oggi un hook equivalente a `StopFailure`: Relay non interpreta
l'output del terminale e quindi non può produrre lo stato `error` per un errore API Codex. Dopo
l'installazione l'utente rivede e autorizza gli hook globali con `/hooks`.

Il `SessionStart` porta un `source`: su `clear` (`/clear`, `/new`) e `resume` il CLI marca l'evento
`resetsAttention` (lo `state` resta `idle`), che nel reducer risolve il completamento in sospeso -
una ri-presa attiva della conversazione è, come il primo prompt, prova che te ne stai occupando.
Vedi `STATE_SCHEMA.md` per il dettaglio.

### Local Control API

Trasporto: Unix domain socket (`~/.relay/relay.sock`, override `RELAY_SOCKET`), JSON lines. Il
receiver (app, `AgentEventReceiver`) fa da server; il CLI (`relay-cli claude-hook` / `codex-hook`,
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
relay-cli hooks setup all       # installa hook Claude Code e Codex
relay-cli hooks uninstall all   # rimuove solo gli hook gestiti da Relay
relay-cli hooks status all      # riporta lo stato di entrambi
```

Regole (verificate a test):

- append, non replace: gli hook nostri sono marcati (`RELAY_MANAGED_HOOK=1` per Claude,
  `RELAY_MANAGED_CODEX_HOOK=1` per Codex) e si
  aggiungono agli array esistenti - convivenza con Otty/ourterm preservata;
- idempotente: setup ripetuto non duplica (rimpiazza i propri entry);
- uninstall rimuove solo i marcati e ripulisce array/chiavi vuoti;
- validazione JSON prima e dopo, backup sempre (`.relay-backup-<epoch>`), scrittura atomica;
- override path via `RELAY_CLAUDE_SETTINGS` / `RELAY_CODEX_HOOKS` (Codex rispetta anche
  `CODEX_HOME`; test e automazioni non toccano i file reali);
- il CLI dell'hook fallisce in silenzio (exit 0) per non rompere l'agente;
- il path del CLI finisce nei comandi: da build di sviluppo è `.build/.../relay-cli`, dal `.app` è
  il `relay-cli` accanto all'eseguibile nel bundle (per gli utenti brew: Impostazioni > Agents
  installa gli hook senza chiedere di trovarlo nel PATH).

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
| `error` | badge rosso + marker attenzione + notifica |
| `unknown` | nessun badge forte (ma un sospeso sopravvive alla fine sessione) |

Regole:

- distinzione **stato vs marker**: `running`/`needs_input`/`error` sono stati e il badge li mostra
  in base ad `agentState` finché lo stato cambia. `needs_input` resta finché la sessione è in attesa
  (si spegne quando rispondi all'agente e parte un nuovo hook), **non** alla semplice visita del pane;
  `error` è l'unico stato che è **anche** marker: accende `unseen` come un completamento, perché
  senza marker non avrebbe né ring né bump né notifica, e un turno morto mentre guardavi altrove
  non chiamerebbe nessuno. I due canali restano indipendenti: declassare il marker (flash o
  interazione) non spegne il badge rosso, che segue lo stato finché non riprendi;
- `attention` (`Tab.attention`, enum `AttentionLevel`) è il marker post-completamento a **tre
  livelli**, che distingue percezione ("l'ho visto") da risoluzione ("me ne sono occupato"):
  - `unseen` - completato (`running` -> `idle`) mentre il pane non era in vista: segnale forte
    (bump in cima alla sidebar, ring, notifica);
  - `pending` - "in sospeso", visto ma mai ripreso: segnale quieto e persistente (punto dimesso in
    sidebar, strato dedicato in dashboard). L'interazione col terminale **declassa** unseen ->
    pending, non spegne. Un completamento nasce **sempre** `unseen`, anche sulla tab in vista: il
    reducer non guarda la visibilità. Sulla tab in vista è il composition root che, dopo un
    **flash** di qualche secondo, lo declassa a `pending` (`onVisibleCompletion` ->
    `scheduleCompletionFlashDecay` -> `markSeen`): senza il flash un completamento sotto gli occhi
    non si vedeva mai. Sopravvive alla fine della sessione (`unknown`) e al riavvio
    (persistito come `pendingSince` nel `TabSnapshot`);
  - risoluzione: la **ripresa vera** della conversazione (prompt -> `running`, o `needs_input`: la
    sessione si è mossa) spegne il marker a qualunque livello; in alternativa il
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
`needs_input` e alla **entrata** in `error` (non a ogni evento successivo: una raffica di retry
falliti riaccende il badge ogni volta ma notifica una volta sola) e al **completamento non visto**
(running -> idle mentre la tab non è in vista).

Notifichiamo i tre stati segnalati **dall'agente** (l'errore API è osservabile solo su Claude Code);
il titolo identifica Claude o Codex tramite `AgentNotification.agent`. `running` e `unknown` restano fuori di
proposito, e non è un'omissione. `running` lo generano `UserPromptSubmit` e **ogni**
`PreToolUse`/`PostToolUse`: decine di eventi per turno, tutti conseguenza del prompt che hai appena
mandato. `unknown` è `SessionEnd`, cioè `/clear`, `exit` o logout. Sono azioni dell'utente:
notificarle seppellirebbe le tre che contano. Chiave: **"in vista" = la tab è *montata in un pane* del workspace mostrato
*dalla sua finestra*, quella finestra è a schermo, e Relay è in primo piano**. Lo store lo calcola in
`applyAgentState` come `montata && selezionata-nella-sua-finestra && !occlusa && appActive`
(`appActive = NSApp.isActive`, `occlusa` da `NSWindow.occlusionState`, entrambi passati dal
composition root). Tre precisazioni che il codice rende esplicite:
**montata, non focused** (con uno split guardi tutti i pane a schermo, non solo quello che riceve la
tastiera); **non occlusa, non key** (con due monitor la finestra che fissi spesso non ha il focus, e
notificarla sarebbe il bug del caso d'uso che motiva il multi-window); **app in primo piano** (se
Relay è in background non la stai guardando davvero). Se una qualsiasi cade, il completato resta
segnalato (`unseen`) e la notifica parte. Il marker
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
della visita). Le tab non in vista restano coi badge (strip del pane); un'attività non vista (completamento
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
default `Cmd+D`) con tutte le sessioni agente in **due viste** scambiabili da un toggle in header
(preferenza persistita `AppSettings.dashboardLayout`, default **kanban**). Il **kanban** raggruppa
per stato su quattro **corsie di triage** (**Needs You** = needs_input/error, **Running**, **Done**
= completati non visti, **Idle** = pending/idle/resume): le corsie sono sempre tutte presenti (una
colonna vuota è informazione, non un buco) e ordinate come il ciclo di vita, quanto reclama *te* da
sinistra. La **griglia flat** storica è la seconda vista, ordinata per urgenza (`needs_input` >
`error` > `unseen` > `pending` > `running` > idle/resume; a pari rango l'evento più recente). Il
pannello è **identico nelle due viste** (stessa dimensione fissa, stessa barra di ricerca): il
toggle scambia solo il contenuto interno, le colonne del kanban sono flessibili e si dividono la
larghezza. L'unità è la sessione, non il workspace: col pattern d'uso reale (~1 tab agente per
workspace) le sezioni sarebbero solo overhead - l'appartenenza è un **chip colorato** sulla card
(colore stabile per workspace dai colori ANSI del tema). Ogni card: stato, titolo, chip, **età
dell'ultimo evento** ("aspetta input da 4m" pesa diverso da "lavora da 20s"), dismiss su hover per
i marker. Type-to-filter (titolo/workspace/cwd), frecce + Invio per saltare, Esc chiude; le frecce
navigano l'ordine flat nella griglia e in 2D nel kanban (su/giù dentro la corsia, sinistra/destra
alla corsia adiacente).

Struttura: logica pura in `Panels/DashboardModel` (filtri, rank, età, corsie
`Lane`/`Column`/`columns`: testata), vista SwiftUI (`DashboardView`, col rendering board + card in
`Dashboard+Board.swift`), wiring nel composition root (`AppControllerDashboard` + overlay
full-window in `RootOverlayController`). Mentre l'overlay è aperto il monitor locale si fa da parte
(i tasti vanno al filtro; niente nav 1..9 né mark-read). Solo dati del model: la dashboard funziona
anche per tab sfrattate dal cap LRU o mai realizzate - una preview del terminale nelle card
richiederebbe surface vive ed è fuori scope. `Cmd+J` è il fratello cieco della dashboard: cicla
prima l'attenzione fresca, esauriti quelli i sospesi.

## Data Model

Stato V0 (in codice, `WorkspaceModel`), `@Observable`:

```text
WorkspaceStore { workspaces: [Workspace], windows: [RelayWindow], groups: [WorkspaceGroup],
                 keyWindowID, occludedWindowIDs, selectedWorkspaceID }  // proiezione della key
RelayWindow    { id, selectedWorkspaceID, frame? }          // ogni finestra ha la SUA selezione
WorkspaceGroup { id, name, colorIndex, collapsed, pinned }  // solo aspetto: i membri stanno
                                                            // su Workspace.groupID
Workspace      { id, windowID, name, nameOrigin, rootPath?, pinned, archived, groupID?,
                 tabs: [Tab],          // il sacco degli oggetti Tab: identità e sessione
                 layout: SplitNode,    // SEMPRE presente: l'ordine visivo sta qui
                 focusedPaneID }       // selectedTabID è derivato: la selezione del pane focused
SplitNode      { .pane(SplitPane) | .split(id, axis, ratio, first, second) }  // foglie = pane
SplitPane      { id, tabIDs: [Tab.id], selectedTabID }   // il pane ospita le tab (modello cmux)
Tab            { id, title, hasCustomTitle, currentDirectory?, resume?,
                 agentState, attention (AttentionLevel), lastEventAt,
                 attentionSince }   // runtime; il sospeso persiste come pendingSince nel
                                    // TabSnapshot, attentionSince è il clock del marker
```

Due punti che il codice rende espliciti e che vale rileggere qui: `layout` non è opzionale (il pane
singolo è un `.pane` con tutte le tab, non un caso speciale), e `selectedTabID` sul workspace è una
**computed** - la selezione vera vive nel pane. Invariante: l'unione dei `tabIDs` dei pane = gli id
di `tabs`, ogni tab in un pane solo, ogni pane con almeno una tab.

Futuro (quando servono):

```text
AgentSession   { sessionId, agent, tabId, state, lastEventAt, resumeCommand, bypass }
AgentEvent     { sessionId, state, source, toolName?, reason?, timestamp }
```

- Il model è puro e osservabile: **nessun riferimento alle surface del terminale**. Le surface
  vive sono legate per `Tab.id` fuori dal model, in `SurfaceRegistry` (TerminalHostUI).
- Gerarchia prodotto: **Workspace -> pane -> tab -> terminale** (modello cmux). Il layout
  (`Workspace.layout`, sempre presente) ha foglie `SplitPane` che ospitano le tab; la Tab resta
  l'unità della sessione agente. `selectTab` significa **rivela**: seleziona la tab nel suo pane e
  dà il focus a quel pane - non muta mai la struttura. Tutta la navigazione (strip, `Cmd+T`, click
  su notifica, dashboard, `Cmd+J`) passa di lì e lo eredita senza casi speciali.
- `SplitNode` mantiene due invarianti: **una tab sta in un pane solo** (una surface, una view) e
  **ogni pane ha almeno una tab**. Le operazioni li preservano invece di fidarsi, e `sanitized`
  (+ l'adozione in `Workspace.init`) li ripristina su un albero arrivato dal disco.
- **Gruppi**: l'appartenenza è un campo del workspace (`groupID`), non una lista di membri sul
  gruppo. Conseguenze volute: nessun secondo ordinamento da tenere in sync (la posizione della card
  è quella del suo primo membro nell'ordine canonico), la contiguità dei membri è una comodità che
  le operazioni mantengono ma da cui la correttezza non dipende, e un gruppo senza membri non è
  rappresentabile - esce l'ultimo membro, la card sparisce. `pinned`, `archived` e `groupID` sono
  mutuamente esclusivi: dentro una card pinna la card (`WorkspaceGroup.pinned`), archiviare o
  cambiare finestra tira fuori dal gruppo. La proiezione per la sidebar è `sidebarItems`
  (`SidebarItem`: riga libera o gruppo coi membri), da cui derivano `orderedWorkspaces` (ordine
  logico, membri nascosti compresi) e `navigableWorkspaces` (solo le righe **visibili**: i membri di
  una card chiusa non entrano in `Cmd+1..9` né nel menu Go).
- **Dove nasce una cosa nuova**: accanto a quella su cui stai lavorando, non in fondo. Una tab entra
  nel pane focused **subito dopo la sua tab selezionata**; un workspace entra **subito dopo il
  selezionato della sua finestra** e ne eredita il `groupID`, quindi creare dentro una card crea
  dentro quella card (`WorkspaceStore.insertionAnchor`, in `+Ordering`). Creare è un gesto
  contestuale, e il fondo della lista è per giunta il posto che il primo bump altrui scavalca. Se la
  card è collassata viene aperta, come farebbe `reveal`.
  L'ancora salta solo se il selezionato è archiviato (sta fuori da `orderedWorkspaces`: ancorarcisi
  darebbe una posizione che nella lista non esiste) e si ferma al pin (il nuovo non è pinned, quindi
  apre il segmento non pinned - la riga più vicina possibile a quella da cui è nato).
- Le finestre **partizionano** i workspace: uno store, un `layout.json`, un receiver di eventi, una
  `SurfaceRegistry` (una tab ha una surface sola ovunque sia montata). Chiudere una finestra
  **rimpatria** i suoi workspace in quella attivata più di recente: è un gesto sul contenitore, non
  sul lavoro che contiene.
- Sidebar e strip dei pane leggono lo store e si aggiornano via Observation, senza toccare le
  surface.
- Persistence: snapshot JSON del layout su disco (vedi Persistence Del Layout). Niente database.

### Binding Surface (lazy, fuori dal model)

- `SurfaceRegistry` mappa `Tab.id -> TerminalSurfaceHandle`. La surface nasce alla **prima
  visita** della tab (lazy) e viene distrutta quando la tab non esiste più (reconcile via
  `retain(aliveTabIDs)`). Il PTY di una tab non visibile resta vivo.
- **Una sola registry per l'app**, condivisa da tutte le finestre: una tab ha una surface sola
  ovunque sia montata, quindi spostare un workspace di finestra non ricrea i pty.
- `WorkspaceAreaController` (AppKit) osserva lo store e riconcilia l'**albero di pane**
  (`Workspace.layout`) in `NSSplitView` annidate. Tre regole: (1) le `PaneView` sono chiavate
  per `SplitPane.id` e riusate, e le view si ricostruiscono solo se cambia la *struttura*
  dell'albero (`SplitNode.hasSameStructure`, che ignora ratio e contenuto dei pane) - trascinando
  un divider cambiano solo i rapporti, e rifare le view sotto il puntatore darebbe flicker; (2) un
  cambio di selezione nella strip **scambia solo il terminale attaccato** al pane
  (`attachTerminal`): le surface restano nella registry; (3) il first responder si prende quando
  cambia la coppia (pane focused, sua tab) **o dopo un rebuild** (staccare le view dalla finestra
  lo resetta), perché un render scatta anche a ogni OSC 7 dello shell. Una tab non selezionata
  della strip non ha view a schermo ma la sua surface (e la sessione agente) resta viva.
- Cap LRU sulle surface vive (`SurfaceRegistry.enforceLRU`, cap in `WorkspaceAreaController`): il
  cap è **soft**. Oltre budget si sfrattano le meno recenti **solo se idle** (`hasRunningChildren ==
  false`: shell senza figli, copre foreground/background/agente) e non protette: mai le **montate**
  (in qualunque finestra: sfrattarne una lascerebbe un terminale bianco davanti agli occhi), le
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

Ripristinare la sessione di un agente dopo un riavvio (il PTY muore, la sessione finisce):

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
  `ResumeBar` (Panels) overlaid sul terminale: `Resume` inietta `claude --resume <id>` oppure
  `codex resume <id>` nel PTY
  (`surface.sendText`), la x scarta. Il setting `autoResumeAgents` (default off) salta la barra e
  inietta da solo, con un piccolo ritardo per far arrivare la shell al prompt.
- La LRU non interseca: una tab con un agente vivo ha processi figli -> non è sfrattabile, quindi il
  resume serve solo dopo un riavvio, non dopo uno sfratto.

Si salva solo: `sessionId`, `agent`, `cwd`, `label`. Mai prompt, token, chiavi, credenziali.

## Data Flow

### Agent State Flow

```text
Claude Code / Codex hook
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
  -> resume agente: ResumeBar al primo focus (o iniezione diretta con autoResumeAgents)
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

Restano aperte solo queste. Chiuse per storico: nome prodotto e repo (Relay, rilasciata e
distribuita via tap brew), formato del protocollo v1 (`STATE_SCHEMA.md`), strategia di
distribuzione degli hook (`HookInstaller` + `docs/features/agent-runtime.md`), budget performance
(misurati, `docs/research/PERF.md`).

1. Engine: SwiftTerm chiuso per la v1 (Cycle 5); resta da definire la soglia oggettiva che farebbe
   scattare il passaggio a libghostty.
2. Isolamento di `WorkspaceStore`: oggi `@Observable` non isolato, mutato dal solo main thread per
   convenzione. Renderlo `@MainActor` è una decisione aperta, non un fatto.
3. Firma Developer ID + notarizzazione: oggi self-signed, la quarantena la toglie il cask.

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
- badge nella strip del pane (per tab) e sidebar (workspace, aggregato per severità + contatore se ≥2 tab
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
  la sposti a mano (la ripresa non la muove; un membro di un gruppo bumpa **dentro la sua card**, che
  non si muove); archivio dei workspace (`Workspace.archived`)
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
  Distribuito via Homebrew tap (`brew install --cask essedev/relay/relay-terminal`), firma
  self-signed stabile; Developer ID + notarizzazione ancora da fare;
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

Costruito dopo ancora (split, finestre, nomina):

- split panes al modello cmux (i pane ospitano le tab) e multi-window come partizione dei workspace
  su un solo store (`docs/features/split-panes.md`);
- archivio dei workspace, onboarding, nomina automatica dei workspace (regola locale di default,
  LLM se c'è una chiave), check aggiornamenti,
  pannello Runtime Stats, ricerca nel terminale con evidenziazione, scroll fluido;
- integrazione Codex tramite hook nativi, installer condiviso e resume specifico per agente.

Da fare dopo:

- distribuzione firmata Developer ID + notarizzazione (toglie l'"Apri comunque");
- terzo agente (opencode, con plugin anziché hook shell);
- drag di tab **fra** pane e di workspace **fra** finestre (incluso l'edge-drop per creare split
  trascinando), zoom del pane.
