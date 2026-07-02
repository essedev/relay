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

## Milestone 1 - Agent runtime + badge (fatto)

Relay è agent-aware: un evento sul socket aggiorna il badge della tab legata via `RELAY_TAB_ID`,
senza parsing dell'output. Restano da chiudere a mano solo la verifica GUI live (badge che cambia
con una sessione Claude reale) e le notifiche macOS vere (richiedono il bundle `.app`, Milestone 4).

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
   `AgentSeverity`). `running`/`needs_input`/`error` sono stati: il badge li mostra finché lo stato
   cambia (`needs_input` resta finché rispondi a Claude, non si spegne al focus). `idle` dopo
   `running` = marker "completato" transitorio, si spegne alla visita.
6. **Anti-rumore**: subagent stop != completamento del pane; niente notifiche su idle->idle.

Exit criteria:

- [x] un evento agente aggiorna il badge della sua tab via `paneId`, senza parsing output
  (transport + apply verificati a test e con l'app viva; conferma visiva con Claude reale a mano);
- [x] il badge del workspace nella sidebar riflette il più severo tra le sue tab (`AgentSeverity`);
- [x] `needs_input` resta visibile finché rispondi a Claude (stato, non marker); il "completato"
  si spegne alla visita (reducer + azzeramento in area controller);
- [x] setup/uninstall hook ripetibile e non rompe Otty (test unit + round-trip su disco);
- [x] `make check` verde, con test su receiver (socket end-to-end) e installer (fixture settings.json).

Nota: le notifiche macOS vere richiedono il bundle `.app` (Milestone 4). Qui si fanno i badge
in-app; le notifiche si agganciano dopo il bundle.

Verifica GUI live (da fare quando comodo): `relay-cli hooks setup`, apri Relay, avvia `claude` in
una tab, e osserva il badge passare a running/needs_input/completed. `relay-cli hooks uninstall` per
rimuovere.

## Fatto - UI/UX e tooling (fuori milestone)

Dopo Milestone 1, un giro di qualità sull'esperienza. Dettagli in `ARCHITECTURE.md`
(Tema / Chrome E Finestra / Tooling).

**Tema (design system)**: modello puro in `Core` (`RelayTheme`), terminale tematizzato (palette
ANSI, colori base, font, blink del caret), chrome coerente, badge dai colori ANSI, pulse su
`needs_input`. Due temi (Dark/Light), zoom (`Cmd +/-`, `Cmd+0`), blink cursore on/off, persistiti in
`UserDefaults` (`AppSettings`). L'appearance della finestra segue la luminanza del tema.

**Pannello impostazioni** (`Cmd+,`): master-detail themed - sidebar con ricerca e categorie
(Appearance / Terminal), contenuto a destra. Voci come blocchi dichiarativi (categoria + keywords),
la ricerca filtra cross-categoria. Anteprima palette sola lettura.

**Chrome e finestra**: full-size content view (contenuto a filo bordo), titolo contestuale centrato
sul body (nome chat Claude via OSC, altrimenti cwd corrente OSC 7 o cartella workspace), toggle
sidebar (`Cmd+B`) come overlay che insegue il bordo della sidebar, sidebar flat themed con selezione
propria, sottotitolo per workspace (cosa succede nella tab selezionata), padding attorno al
terminale, doppio click sulla strip = zoom.

**Badge e navigazione**: contatore sul badge workspace quando ≥2 tab condividono lo stato più
severo; `Cmd+T` eredita la cwd corrente della tab attiva.

**Tooling di test** (entrambi sul socket reale): `relay-cli simulate [coding|permission|burst]`
dentro una tab, e `relay --demo NxM` per popolare l'app con sessioni concorrenti simulate.

Restano aperti (later): scelta del font family, altri temi, import da config Ghostty.

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

Milestone 2 - persistence: snapshot JSON del layout (workspace, tab, cwd, pin, ordine) su disco, con
restore che lascia i pane `unrealized` finché non c'è focus. Poi rename di workspace/tab.
