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
| Renderer vivi simultanei | pane visibili + 3 recenti (LRU) |
| Scrollback per surface | 10k righe default, configurabile |
| Costo di un workspace mai aperto | ~0 (solo metadata) |

I numeri sono target iniziali: lo spike engine (Fase 1) li valida o li corregge.

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
    Split Pane Tree + Focus Routing
    Terminal Host View
    Keyboard Shortcuts

  Terminal Runtime
    GhosttyKit / libghostty
    Surface Lifecycle Manager (lazy + LRU renderer)
    PTY Session

  Agent Runtime
    Local Socket Receiver
    Agent Session Store
    Agent Event Timeline
    Hook Installer

  Workspace Model
    Workspace / Tab / Pane Store
    Ordinamento, pin, aggregazione stati
    Persistence + Restore

  UI Panels (SwiftUI isolato)
    Sidebar
    Dashboard
    Settings

  CLI
    ourterm hooks setup/uninstall/status
    ourterm state:claude ...
```

## Struttura Repo E Moduli

Monolite modulare: una sola app, molti package SwiftPM locali. Il confine tra moduli è imposto
dal compilatore (dipendenze dichiarate in `Package.swift`), non dalla buona volontà. È la
contromisura strutturale ai file da 12-16k righe e agli `AppDelegate+X` di cmux.

```text
repo/
  App/                  target app minimale: composition root, wiring, entitlements
  Packages/
    Core/               primitivi condivisi: ID, logging, errori; nessuna dipendenza
    AgentProtocol/      tipi evento, stati, codec JSON; puro, niente I/O
    AgentRuntime/       socket receiver, session store, timeline
    WorkspaceModel/     store workspace/tab/pane, aggregazione stati, persistence
    TerminalEngine/     wrapper GhosttyKit, surface lifecycle (lazy + LRU)
    TerminalHostUI/     AppKit: host view, split tree, focus, tastiera
    Panels/             SwiftUI: sidebar, dashboard, settings
    HookInstaller/      manipolazione ~/.claude/settings.json
    LayoutStore/        persistence layout: snapshot JSON su disco (I/O), path iniettato
    CLI/                eseguibile `ourterm`
  docs/
  Makefile
```

Regole di dipendenza:

- solo verso il basso: UI -> runtime/model -> protocol -> Core; mai il contrario;
- `AgentProtocol`, `HookInstaller` e la logica di `WorkspaceModel` non importano
  AppKit/SwiftUI: unit test veloci con `swift test`, senza simulatore;
- l'engine concreto (SwiftTerm oggi, libghostty domani) è importato solo da `TerminalEngine`;
  il resto dell'app parla con `TerminalEngine`, non con l'engine. La policy del lifecycle
  (decisioni lazy/LRU) è un tipo puro testabile senza AppKit;
- `CLI` dipende solo da `AgentProtocol`, `HookInstaller` e `Core`: niente dipendenze app;
- `App` è solo composition root: se cresce, manca un modulo.

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
- Lo scrollback è cappato per surface: i transcript lunghi di Claude non devono gonfiare la
  memoria di ogni pane vivo.
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
- `AppSettings` (`WorkspaceModel`, @Observable) tiene tema selezionato + dimensione font + blink del
  caret, persistiti in `UserDefaults` (preferenze, non lo snapshot del layout). `fontSize` e
  `cursorBlink` sono sovrapposti al tema base (`withFontSize`/`withCursorBlink`). Cambi ->
  `SurfaceRegistry.applyTheme` ridipinge le surface vive; la chrome si aggiorna via Observation.

Pannello impostazioni (`Cmd+,`): master-detail themed - sidebar con ricerca e lista categorie
(Appearance / Terminal), contenuto a destra. Ogni voce è un "blocco" dichiarativo (categoria +
keywords + vista), unica fonte per categorie e ricerca: aggiungere un'impostazione è una riga. Anche
zoom (`Cmd +/-`, `Cmd+0`). Import da config Ghostty: possibile in futuro, non nel baseline.

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
- Sidebar: `NSSplitViewItem` normale, **non** `sidebarWithViewController:` (su macOS 26 quello stila
  la sidebar come pannello glass flottante, in conflitto col design flat themed). Righe con
  selezione/hover dai colori del tema (niente highlight di sistema), sottotitolo per riga
  (`WindowTitle.workspaceSubtitle`: cosa succede nella tab selezionata) e badge aggregato.
- OSC 7: la cwd riportata dalla shell (`Core.OSC7` -> `Tab.currentDirectory`) alimenta titolo,
  sottotitolo e l'ereditarietà cwd di `Cmd+T` (la nuova tab parte dove stai lavorando, non alla
  radice del workspace).

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

- ricevere eventi dagli hook;
- normalizzare stati;
- legare sessione agente a pane;
- mantenere snapshot corrente e timeline eventi;
- notificare gli store UI.

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
| `PreToolUse` | `running` |
| `PostToolUse` | `running` |
| `PermissionRequest` | `needs_input` |
| `Stop` | `idle` |
| `SessionEnd` | `unknown` |

`SubagentStop` non è mappato: lo stop di un subagent non è il completamento del pane. Nomi hook
confermati sulla doc Claude Code corrente (luglio 2026). Nota: nello spike gli stati usano i nomi
Otty (`processing`, `awaiting`, `idle`); nell'app si usano i nomi prodotto qui sopra.

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
  "timestamp": "2026-07-02T08:45:48Z"
}
```

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

Severità: `needs_input` > `error` > `running` > `completed` non visto > `idle`.

| Stato | UI |
| --- | --- |
| `running` | spinner o indicatore working |
| `needs_input` | badge attention + notifica macOS |
| `idle` dopo lavoro | marker completed finché non visitato |
| `error` | marker errore |
| `unknown` | nessun badge forte |

Regole:

- distinzione **stato vs marker**: `running`/`needs_input`/`error` sono stati e il badge li mostra
  in base ad `agentState` finché lo stato cambia. `needs_input` resta finché la sessione è in attesa
  (si spegne quando rispondi a Claude e parte un nuovo hook), **non** alla semplice visita del pane;
- `attention` (`Tab.attention`) è solo il marker "completato non visto": lavoro finito
  (`running` -> `idle`) mentre il pane non era in vista. Quello sì si spegne alla visita;
- `idle` non genera rumore se la sessione era già idle;
- `completed` esiste solo come transizione dopo `running`;
- lo stop di un subagent non è il completamento del pane principale.

## Data Model

Stato V0 (in codice, `WorkspaceModel`), `@Observable`:

```text
WorkspaceStore { workspaces: [Workspace], selectedWorkspaceID }
Workspace      { id, name, rootPath?, pinned, tabs: [Tab], selectedTabID }
Tab            { id, title, hasCustomTitle, currentDirectory?, resume?,  // V0: una tab = terminale
                 agentState, attention, lastEventAt }                    // runtime, non persistiti
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
- Cap LRU sulle surface vive (`SurfaceRegistry.enforceLRU`, cap in `WorkspaceAreaController`): oltre
  il cap si sfrattano le meno recenti **solo se idle** (`hasRunningChildren == false`: shell senza
  figli, copre foreground/background/agente), mai la visibile. Eviction = teardown della surface
  SwiftTerm: scrollback perso, shell ricreata alla cwd salvata al re-focus. La decisione
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
  contestuale), padding riga allineato all'header, riordino drag & drop, x di chiusura su hover per
  tab e workspace, rename inline del workspace dal menu contestuale; float in cima (sotto ai pinned)
  dei workspace con attenzione (`needs_input`/completato) via `orderedWorkspaces` derivato, ordine
  canonico invariato; conferma di chiusura se nel pty gira un comando in foreground; ultima tab
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

Costruito (Milestone 3, in corso):

- cap LRU sulle surface vive (`SurfaceRegistry.enforceLRU` + `SurfaceEvictionPolicy` pura, cap in
  `WorkspaceAreaController`): sfratta le meno recenti solo se idle, mai la visibile né quelle con
  lavoro vivo. Restano da fare le misure (latenza input p99, memoria per surface) per tarare il cap.

Prossimo: misure di performance (M3) poi bundle `.app` (M4), vedi `docs/ROADMAP.md`.

Da fare dopo:

- misure latenza input e memoria a N surface (per tarare il cap LRU);
- bundle `.app` (notifiche macOS, installer hook distribuibile);
- split (pane tree dentro una tab), deprioritizzato; dashboard overview.
