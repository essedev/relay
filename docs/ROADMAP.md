# Roadmap

Piano forward dell'app Relay. La storia decisionale (analisi engine, benchmark, diagnosi lag
cmux) vive nel repo di ricerca `terminal-agent-analysis` (`CYCLES.md`). Qui c'è cosa manca e in
che ordine. Dettagli di design in `ARCHITECTURE.md`.

## Fatto - V0

- Struttura modulare SwiftPM (9 moduli, dipendenze imposte dal compilatore), Makefile, lint, CI.
- Engine SwiftTerm dietro `TerminalEngine` (nessun tipo SwiftTerm fuori dal modulo).
- Model `WorkspaceStore`/`Workspace`/`Tab` (@Observable, testato).
- App reale: Workspace -> Tab -> terminale. Sidebar (crea/seleziona/pin/riordina), tab bar
  (crea/seleziona/chiudi), surface lazy per `Tab.id` con teardown per reconcile.
- Workspace folder-less (`Cmd+N`) e da cartella (`Cmd+O`); `Cmd+T`/`Cmd+W`.
- Navigazione a due assi via event monitor: `Cmd+1..9` workspace, `Option+1..9` tab.

## Milestone 1 - Agent runtime + badge (prossimo)

Obiettivo: rendere Relay agent-aware. È il differenziatore. Pipeline hook -> stato già validata
in `terminal-agent-analysis/ourterm-spike` (Cycle 1); qui la si porta nell'app.

Design (vedi `ARCHITECTURE.md`: Agent Runtime, Local Control API, Aggregazione Stati E Badge):

1. **Receiver locale** (`AgentRuntime`): Unix domain socket, JSON lines; decodifica in
   `AgentProtocol` (`AgentStateEvent` ecc.) e aggiorna `AgentSessionStore` (actor già presente).
2. **Binding sessione -> tab**: iniettare una env per surface (es. `RELAY_TAB_ID`) in
   `SwiftTermEngine.start` (via `environment`); l'hook la rimanda indietro nell'evento, così il
   receiver sa quale tab aggiornare. Nessun parsing dell'output.
3. **Hook adapter + installer** (`HookInstaller` + `CLI`): script hook che manda gli eventi al
   socket, e `relay hooks setup|uninstall|status` che scrive `~/.claude/settings.json` in modo
   idempotente, con backup e validazione JSON, **convivendo con Otty** (append, non replace).
   Mapping: `SessionStart/Stop -> idle`, `UserPromptSubmit/PreToolUse/PostToolUse -> running`,
   `PermissionRequest -> needs_input`.
4. **Stato sul model**: aggiungere a `Tab` lo stato agente corrente (`agentState`, `lastEventAt`).
   L'applicazione evento -> tab avviene in un coordinatore nel composition root (App), NON dentro
   `AgentRuntime` (che resta indipendente da `WorkspaceModel`).
5. **Badge UI**: in `TabBarView` (per tab) e `SidebarView` (per workspace, aggregato con
   `AgentSeverity`). `needs_input` = attention marker che resta finché non visiti la tab;
   `running` = spinner; `idle` dopo `running` = completed marker.
6. **Anti-rumore**: subagent stop != completamento del pane; niente notifiche su idle->idle.

Exit criteria:

- una sessione Claude reale aggiorna il badge della sua tab senza parsing output;
- il badge del workspace nella sidebar riflette il più severo tra le sue tab;
- `needs_input` è visibile e si pulisce alla visita;
- setup/uninstall hook ripetibile e non rompe Otty;
- `make check` verde, con test su receiver (socket end-to-end) e installer (fixture settings.json).

Nota: le notifiche macOS vere richiedono il bundle `.app` (Milestone 4). Qui si fanno i badge
in-app; le notifiche si agganciano dopo il bundle.

## Milestone 2 - Persistence + rename (dogfood-ability)

- Salvare/ripristinare il layout (workspace, tab, cwd, pin, ordine) su disco (snapshot JSON).
  Al restore i pane nascono `unrealized`; la surface nasce al primo focus.
- Rename di workspace e tab (doppio click -> TextField), rispettando `hasCustomTitle`.
- Resume opzionale: `claude --resume <sessionId>` quando sicuro (dopo Milestone 1).

## Milestone 3 - Disciplina performance

- Cap LRU sulle surface vive (ora restano vive tutte le tab visitate): tenere visibili + N
  recenti, distruggere/sospendere le altre (il PTY di una tab con agente attivo resta vivo).
- Chiudere le misure rimandate contro i budget di `ARCHITECTURE.md`: latenza input p99 e costo
  memoria incrementale per surface con molte tab.

## Milestone 4 - Bundle `.app`

- Info.plist, bundle id, entitlements, firma. Sblocca notifiche macOS, installer hook
  distribuibile e uso fuori da `swift run`.

## Più avanti

- Dashboard overview di tutti i workspace/agenti con jump-to.
- Split (pane tree dentro una tab), deprioritizzato dall'utente.
- Altri agenti (Codex/OpenCode), export timeline.

## Prossima azione

Milestone 1, task 1-2: receiver socket in `AgentRuntime` + binding `RELAY_TAB_ID` per surface.
