# Architecture

Progetto: **Relay**.
Ultimo aggiornamento: 2026-07-02.

Documento vivo: budget, moduli e confini si rivedono quando misure o sviluppo portano evidenze
nuove. La storia decisionale completa (cicli 0-5: analisi engine, diagnosi lag cmux, benchmark
SwiftTerm) vive nel repo di ricerca `terminal-agent-analysis` (`CYCLES.md`); qui si tiene lo
stato corrente.

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
  scrivi input, leggi dimensioni/titolo/cwd, notifica output/bell/OSC. Il resto dell'app non
  sa quale engine c'è sotto. Questo rende la migrazione un update localizzato, non un rewrite.

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

Nota: nello spike gli stati usano i nomi Otty (`processing`, `awaiting`, `idle`); nell'app si
usano i nomi prodotto qui sopra.

### Local Control API

Trasporto: Unix domain socket, JSON lines. Fallback dev: CLI file-based come in `ourterm-spike`.

Eventi v1:

```text
agent.session.start
agent.state
agent.notification
agent.resume.set
agent.session.end
```

Esempio:

```json
{
  "type": "agent.state",
  "agent": "claude",
  "sessionId": "abc",
  "paneId": "pane-1",
  "state": "needs_input",
  "source": "hook",
  "confidence": 1,
  "timestamp": "2026-07-02T08:45:48Z"
}
```

### Hook Installer

Comandi:

```text
ourterm hooks setup claude
ourterm hooks uninstall claude
ourterm hooks status
```

Regole:

- non sovrascrivere hook esistenti (convivenza con Otty verificata nel Cycle 1);
- validare JSON prima e dopo;
- backup sempre;
- niente segreti nei log;
- lo script hook fallisce in silenzio per non rompere Claude.

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

- `needs_input` resta visibile finché l'utente non visita il pane;
- `idle` non genera rumore se la sessione era già idle;
- `completed` esiste solo come transizione dopo `running`;
- lo stop di un subagent non è il completamento del pane principale.

## Data Model

```text
Workspace    { id, name, rootPath, pinned, sortIndex, createdAt }
Tab          { id, workspaceId, title, sortIndex, paneTree }
Pane         { id, tabId, cwd, lifecycle, agentSessionId? }
AgentSession { sessionId, agent, paneId, state, lastEventAt, resumeCommand, bypass }
AgentEvent   { sessionId, state, source, toolName?, reason?, timestamp }
```

- Sidebar e dashboard leggono `Workspace` + aggregati: nessun accesso alle surface.
- `AgentEvent` è una timeline JSONL con retention breve (debug e dashboard "ultimo evento").
- Persistence v1: snapshot JSON del layout + metadata. Niente database finché non serve.

### Resume

Si salva solo: `sessionId`, `agent`, `cwd`, comando sanitizzato (`claude --resume <sessionId>`).

Non si salva mai: prompt utente, token, chiavi, credenziali, payload con contesto sensibile.

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
  -> carica snapshot layout (tutti i pane unrealized)
  -> ricrea sidebar/tab/split come metadata
  -> al primo focus di un pane: realizza surface, ripristina cwd
  -> resume agente opzionale con comando sanitizzato
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
  ritmi degli agenti (benchmark in `swiftterm-spike/`);
- cap scrollback confermato come leva di memoria giusta.

Da validare (misure di Fase 2, sull'app multi-surface reale):

- latenza input p99 contro il budget < 1 frame;
- costo memoria incrementale per surface dentro un solo processo;
- lifecycle surface lazy + LRU in app reale;
- binding sessione -> pane;
- socket locale al posto del file store;
- badge UI in tempo reale.
