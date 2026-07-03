# Roadmap

Piano forward dell'app Relay. La storia decisionale (analisi engine, benchmark, diagnosi lag
cmux) vive in `docs/research/` (`CYCLES.md`). Qui c'è cosa manca e in che ordine. Dettagli di design
in `ARCHITECTURE.md`.

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
in `docs/research/spikes/ourterm-spike` (Cycle 1); qui la si porta nell'app.

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

**Interazione sidebar/tab e chiusura**: lista workspace custom (`LazyVStack`, non `List`) per
togliere l'highlight full-size del menu contestuale, padding riga allineato all'header, riordino via
drag & drop, x di chiusura su hover per tab e workspace, rename inline del workspace dal menu
contestuale (`TextField` in riga: commit su Invio/blur, Esc annulla, path sotto sempre visibile). I
workspace con attenzione (`needs_input` o completato-non-visto) galleggiano in cima, sotto ai pinned
(`orderedWorkspaces` derivato dallo stato, ordine canonico dello store invariato). Chiudere una
tab/workspace chiede conferma se nel pty gira un comando in foreground (`tcgetpgrp` + safe-list shell,
stato Claude solo per il messaggio); chiudere l'ultima tab chiude il workspace, e la finestra non
resta mai senza workspace (se ne riapre uno default).

**Tooling di test** (entrambi sul socket reale): `relay-cli simulate [coding|permission|burst]`
dentro una tab, e `relay --demo NxM` per popolare l'app con sessioni concorrenti simulate.

Fatto in seguito (vedi Milestone 4): scelta del font family e altri temi. Altre rifiniture:
`Cmd+1..9` segue l'ordine visivo della sidebar (`orderedWorkspaces`), drag & drop di file nel
terminale (inserisce i path escaped, come Terminal.app), ricerca nello scrollback (`Cmd+F`, motore
SwiftTerm, find bar flottante), clear del terminale (`Cmd+K`), jump alla prossima tab che richiede
attenzione (`Cmd+J`, ciclico), trascinamento finestra solo dalle strip del titolo (`WindowDragArea`,
non `isMovableByWindowBackground`), ring di attenzione colorato attorno al terminale con mark-read su
interazione (modello ispirato a cmux, vedi `docs/research/CYCLES.md`) e scorciatoie rimappabili
(cicla tab/workspace, chiudi workspace, find next/prev, jump indietro; recorder in Impostazioni >
Shortcuts). Resta aperto (later): import da config Ghostty.

## Milestone 2 - Persistence + rename (dogfood-ability) - fatto

- Layout salvato/ripristinato su disco (`~/.relay/layout.json`, versionato): `LayoutSnapshot`
  Codable + modulo `LayoutStore` (I/O atomico) + `LayoutAutosave` (debounced-live + flush on quit).
  Al restore i pane nascono `unrealized`; la surface nasce al primo focus. Demo mode non persiste.
- Rename inline di workspace e tab dal menu contestuale (rispetta `hasCustomTitle`).
- Test: round-trip encode/decode, snapshot->restore, file mancante/corrotto/versione ignota,
  selezione validata; smoke test end-to-end save+restore.
- Resume assistito delle sessioni Claude (fatto, follow-on): `ResumeBinding` catturato dagli hook e
  persistito; al primo focus di una tab ripristinata la barra `ResumeBar` propone il resume (o
  auto-inject col setting `autoResumeAgents`, default off), che scrive `claude --resume <id>` nel
  PTY. Lazy (un agente alla volta), non un big-bang al boot.

## Milestone 3 - Disciplina performance - fatto

- Cap LRU sulle surface vive (`SurfaceRegistry.enforceLRU` + `SurfaceEvictionPolicy` pura, cap in
  `WorkspaceAreaController`). Sfratta le meno recenti solo se idle (shell senza figli: copre
  foreground/background/agente), mai la visibile; al re-focus la surface rinasce lazy alla cwd
  salvata (scrollback perso).
- Misure di performance chiuse (`docs/research/PERF.md`) con strumentazione integrata (`RELAY_PERF`):
  latenza input aggiunta dallo shell max 2.4µs (budget 16ms p99), ~0.3-0.5 MB per surface idle,
  ~98 MB con 30 surface vive. Cap confermato a 12; knob `RELAY_SURFACE_CAP` per ri-tarare.

## Milestone 4 - Bundle `.app` + notifiche - fatto

- Bundle `.app` (`make bundle` -> `.build/Relay.app`): `bundle/Info.plist` (bundle id
  `dev.relay.app`) + icona + firma ad-hoc; `make run-app` lo avvia. Sblocca l'uso fuori da `swift run`.
- Icona dell'app generata proceduralmente (`bundle/make-icon.swift` -> `bundle/AppIcon.icns` via
  `make icon`): prompt terminale (chevron + cursore a blocco) su squircle scuro.
- Installer locale non firmato: `make dmg` (`.build/Relay.dmg`, drag su /Applications) e
  `make install-app`.
- Notifiche macOS su `needs_input`/completato (`NotificationCoordinator` + `UNUserNotificationCenter`,
  solo dal bundle), classificazione pura nel reducer, con impostazioni (categoria Notifications:
  master, per-tipo, suono on/off + scelta suono). Soppressione se stai già guardando la tab.
- Dodici temi curati (Solarized, Gruvbox, Tokyo Night, Catppuccin e GitHub oltre a Relay
  Dark/Light) e scelta font family, nel pannello impostazioni.

## Più avanti

- Distribuzione: firma Developer ID + notarizzazione + dmg firmato; installer hook distribuibile.
- Dashboard overview di tutti i workspace/agenti con jump-to.
- Split (pane tree dentro una tab), deprioritizzato dall'utente.
- Altri agenti (Codex/OpenCode), export timeline; import da config Ghostty.

## Prossima azione

Baseline delle milestone chiuso, con app installabile in locale (bundle + icona + dmg). Prossimo
giro a scelta dell'utente: distribuzione firmata (Developer ID + notarizzazione), dashboard overview,
oppure split.
