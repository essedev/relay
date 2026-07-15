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
senza parsing dell'output. Notifiche macOS e verifica live con Claude reale poi chiuse (M4 + a mano).

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
severo; `Cmd+T` eredita la cwd corrente della tab attiva (letta dalla shell viva, non solo
dall'OSC 7: vedi Fatto - cwd di `Cmd+T`).

**Interazione sidebar/tab e chiusura**: lista workspace custom (`LazyVStack`, non `List`) per
togliere l'highlight full-size del menu contestuale, padding riga allineato all'header, riordino via
drag & drop, x di chiusura su hover per tab e workspace, rename inline del workspace dal menu
contestuale (`TextField` in riga: commit su Invio/blur, Esc annulla, path sotto sempre visibile).
Un'attività non vista (`needs_input` o completato-non-visto) bumpa il workspace in cima ai non-pinned
(riordino reale e persistente dell'ordine canonico, non un float derivato; la ripresa non lo muove).
Chiudere una
tab/workspace chiede conferma se nel pty gira un comando in foreground (`tcgetpgrp` + safe-list shell,
stato Claude solo per il messaggio); chiudere l'ultima tab chiude il workspace, e la finestra non
resta mai senza workspace (se ne riapre uno default).

**Tooling di test** (entrambi sul socket reale): `relay-cli simulate [coding|permission|burst]`
dentro una tab, e `relay --demo NxM` per popolare l'app con sessioni concorrenti simulate.

Fatto in seguito (vedi Milestone 4): scelta del font family e altri temi. Altre rifiniture:
`Cmd+1..9` segue l'ordine visivo della sidebar (`orderedWorkspaces`), drag & drop di file nel
terminale (inserisce i path escaped, come Terminal.app), ricerca nello scrollback (`Cmd+F`, find bar
flottante con opzioni case/word/regex, evidenziazione di tutti i match, scrollback 10k), clear del
terminale (`Cmd+K`), jump alla prossima tab che richiede
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

- Cap LRU soft sulle surface vive (`SurfaceRegistry.enforceLRU` + `SurfaceEvictionPolicy` pura, cap
  in `WorkspaceAreaController`). Sfratta le meno recenti solo se idle (shell senza figli: copre
  foreground/background/agente) e non protette: visibile, workspace attivo, attenzione fresca, tab
  recenti e lavoro vivo restano in memoria; al re-focus una surface sfrattata rinasce lazy alla cwd
  salvata (scrollback perso).
- Misure di performance chiuse (`docs/research/PERF.md`) con strumentazione integrata (`RELAY_PERF`):
  latenza input aggiunta dallo shell max 2.4µs (budget 16ms p99), ~0.3-0.5 MB per surface idle,
  ~98 MB con 30 surface vive. Cap confermato a 12; knob `RELAY_SURFACE_CAP` per ri-tarare.
- Pannello Runtime Stats (`View > Runtime Stats…`) con RSS, CPU processo, workspace/tab e surface
  vive/cap; campiona solo mentre la finestra è aperta.

## Milestone 4 - Bundle `.app` + notifiche - fatto

- Bundle `.app` (`make bundle` -> `.build/Relay.app`): `bundle/Info.plist` (bundle id
  `dev.relay.app`) + icona + firma ad-hoc; `make run-app` lo avvia. Sblocca l'uso fuori da `swift run`.
- Icona dell'app generata proceduralmente (`bundle/make-icon.swift` -> `bundle/AppIcon.icns` via
  `make icon`): prompt terminale (chevron + cursore a blocco) su squircle scuro.
- Installer locale non firmato: `make dmg` (`.build/Relay-<version>.dmg`, drag su /Applications) e
  `make install-app`.
- Notifiche macOS su `needs_input`/completato (`NotificationCoordinator` + `UNUserNotificationCenter`,
  solo dal bundle), classificazione pura nel reducer, con impostazioni (categoria Notifications:
  master, per-tipo, suono on/off + scelta suono). Soppressione se stai già guardando la tab.
- Dodici temi curati (Solarized, Gruvbox, Tokyo Night, Catppuccin e GitHub oltre a Relay
  Dark/Light) e scelta font family, nel pannello impostazioni.

## Fatto - Dashboard + attenzione a tre livelli (post-M4)

Il problema: il mark-read a interazione confondeva percezione ("l'ho visto") con risoluzione ("me
ne sono occupato") - clic sulla notifica, occhiata, distrazione, e la sessione che aspettava una
risposta ricadeva nel mucchio anonimo. Design in `ARCHITECTURE.md` #Aggregazione-Stati-E-Badge e
#Dashboard-Delle-Sessioni.

- **Attention a tre livelli** (`AttentionLevel`): `unseen` (completato non visto, segnale forte:
  bump in cima, ring, notifica) -> l'interazione **declassa** a `pending` ("in sospeso", quieto e
  persistente: punto dimesso in sidebar) -> risolve solo la ripresa vera (prompt ->
  running), il dismiss esplicito o la chiusura tab. Il sospeso sopravvive alla fine sessione e al
  riavvio (`pendingSince` nel `TabSnapshot`, campo additivo senza bump).
- **Decadenza** dei sospesi (`AppSettings.pendingDecayHours`, default **12h**; `0` = mai; 4/12/24h
  in Impostazioni > Agents), applicata a boot/foreground/apertura dashboard, senza timer.
- **Dashboard overlay** (`Cmd+D`, rimappabile): griglia flat delle sessioni agente ordinata per
  urgenza (needs_input > error > unseen > pending > running > idle/resume, poi recency), card con
  stato/titolo/chip workspace colorato (stabile, dai colori ANSI)/età dell'ultimo evento, dismiss
  su hover, type-to-filter, frecce + Invio per saltare, Esc chiude. Logica pura testata
  (`DashboardModel`), vista in `Panels`, wiring nel composition root.
- **`Cmd+J` a due livelli**: prima l'attenzione fresca, esauriti quelli i sospesi.

## Fatto - Distribuzione brew + rifiniture (post-dashboard)

- **Distribuzione via Homebrew tap**: `brew install --cask essedev/relay/relay` (tap pubblico
  `essedev/homebrew-relay`, cask che scarica il dmg dalle Release di `essedev/relay`). Versione =
  `./VERSION` (semver), release ripetibile con `make release` (build dmg -> GitHub Release -> aggiorna
  il cask). Firma self-signed stabile (keychain dedicato, trust una tantum via sudo); un postflight
  `xattr` nel cask toglie la quarantena, niente prompt Gatekeeper all'apertura. Metodo e decisioni in
  `research/CYCLES.md` (Cycle 11).
- **Shift+Invio in Claude Code**: la surface dichiara il kitty keyboard protocol con
  `KITTY_WINDOW_ID=1` (SwiftTerm lo implementa gia); Shift+Invio/Ctrl+Invio nativi, senza spoofare
  `TERM_PROGRAM` (issue claude-code#27868).
- **Sidebar width persistita**: default 250, salvata in `AppSettings` (prima ripartiva dal minimo a
  ogni avvio).

## Fatto - Riordino e attenzione manuale (post-brew)

- **Drag & drop sidebar libero**: il riordino non è più vincolato al segmento (un workspace solo
  nel suo gruppo restava inchiodato al punto di partenza, drop = no-op). Il drag edita direttamente
  l'ordine canonico, con resolver puro `SidebarDrop` (due segmenti pinned/resto; attraversare il
  blocco pinned pinna/spinna) e ordine congelato durante il gesto; lo stato del gesto vive in
  `@GestureState` (reset garantito anche se il gesto viene annullato).
- **Mark-read filtrato**: il declassamento del completamento scatta solo su interazione reale col
  terminale (tasto col terminale in focus o click dentro la sua view, `terminalOwns`), non su un
  click di navigazione nella chrome (cambiare tab/workspace non consuma più il marker).
- **Override unread manuale**: dal menu contestuale (workspace nella sidebar, tab nella tab bar)
  "Mark as Unread"/"Mark as Read" riaccende o spegne il marker a mano (`toggleUnread`, riusa
  `unseen`; niente notifica).
- **Drop preciso a ogni distanza** (fix successivo): la misura dei frame di riga vive **dopo**
  l'`.offset` del drag, dentro `reorderableRow`. Prima stava sotto l'offset (un GeometryReader lì
  dentro ne assorbe la traslazione, l'offset è un GeometryEffect): il frame della riga in volo
  seguiva il gesto, il centro proiettato raddoppiava la traslazione e la linea di inserimento
  derivava proporzionalmente alla distanza dal punto di presa - drop sempre più impreciso più il
  drag era lungo.

## Fatto - Resume affidabile + archive (post-brew)

- **Proposta di resume affidabile al riavvio**: due guardie complementari proteggono il resume
  binding ripristinato, che il `RELAY_TAB_ID` stabile tra i riavvii esporrebbe agli hook di sessioni
  morte. La soglia anti-stantio (`WorkspaceStore.eventFloor`, timbrata all'avvio) scarta gli eventi
  **eseguiti** prima del restart. Ma un claude orfano sopravvissuto al riavvio (SIGHUP ignorato, o un
  `SessionEnd` morente che scavalca un relaunch rapido) manda hook con timestamp fresco che
  passerebbero il floor: uno `Stop` portava la tab fuori da `unknown` (barra soppressa a binding
  intatto) e un `SessionEnd` azzerava il binding, quindi la `ResumeBar` non compariva sempre. Li
  ferma il **fence di run** (`WorkspaceStore.runID` = `RELAY_RUN_ID`, nonce per processo iniettato
  nell'env delle surface accanto a `RELAY_TAB_ID`): gli eventi di una run diversa (o senza runId)
  vengono scartati. In più il receiver si ferma prima del flush finale del layout, così i
  `SessionEnd` morenti della run corrente non azzerano i binding nello snapshot alla chiusura.
- **Archive dei workspace**: `Workspace.archived` (persistito, additivo) sposta un workspace in una
  sezione collassabile ancorata in fondo alla sidebar (tetto ~metà + scroll interno, stato espanso
  in `AppSettings`). Fuori da `orderedWorkspaces`, mutuamente esclusivo con pin (e non bumpabile);
  `setArchived` non archivia l'ultimo visibile e sposta la selezione. Archivia/ripristina dal menu contestuale.
  **Ancora da fare**: drag dentro/fuori l'archivio (richiede coordinate space unificato in
  `Reorderable`, giro dedicato).
- **Ordine sidebar "lista chat"**: la posizione non è più un float derivato dall'attenzione ma un
  ordine **reale e persistente**. Un'attività **non vista** (completamento o `needs_input`) bumpa il
  workspace in cima ai non-pinned (`bumpWorkspaceToTop`); ci resta finché non la scavalca un altro
  bump o non la sposti a mano. La **ripresa** (`running`) e ogni evento sulla tab in vista non
  muovono la riga - niente scivolamento sotto le mani. `attention` resta solo un segnale
  (badge/ring), scollegato dall'ordine. Supera il precedente "float sticky" (che cadeva alla ripresa).

## Fatto - Onboarding "Welcome to Relay" (post-resume)

- **Overlay di benvenuto** al primo avvio (flag `AppSettings.onboardingSeen`, timbrato alla
  presentazione; mai in demo mode), riapribile da **Help > Welcome to Relay**. Stessa meccanica
  full-window della dashboard (`AppControllerOnboarding` + `RootOverlayController.presentFullOverlay`):
  mentre è aperto il monitor si fa da parte (i tasti vanno alla vista - frecce/Invio/Esc), e un solo
  overlay full-window alla volta (aprire onboarding o dashboard chiude l'altro).
- **Cinque pagine coi componenti veri** del design system, non screenshot: hero con icona
  procedurale (`RelayMarkView`, geometria dell'`.icns`), pagina hook **azionabile** (riusa
  `ClaudeHooksBlock`: stato live + install col `relay-cli` impacchettato, comando manuale in dev),
  modello di attenzione con **stati cliccabili e preview live** (badge, riga di sidebar finta, mini
  terminale col ring pulsante), scorciatoie lette dai binding correnti, e temi selezionabili **dal
  vivo** (l'app si ridipinge, onboarding compreso). Logica di navigazione pura (`OnboardingModel`,
  testata).
- **Fix collaterale (copre anche la dashboard)**: gli overlay full-window ora bloccano il
  passthrough di mouse e cursore verso il terminale sotto (niente selezione di testo né I-beam con
  l'overlay aperto): container che chiude i buchi di hit-testing + cursor rects della finestra
  disattivate finché l'overlay è su. Icona di About ridisegnata con `RelayMarkView` (dai build di
  sviluppo `NSApp.applicationIconImage` dava l'icona generica).

## Fatto - Pulizia codebase, CI deterministica e move-tab (post-onboarding)

- **Move to New Workspace**: dal menu contestuale di una tab (visibile solo con **>=2 tab**) la si
  estrae in un nuovo workspace placeholder **preservando la sessione viva** - lo store sposta lo
  **stesso** oggetto `Tab` (stesso `Tab.id`), quindi la surface/pty non si tocca; append del nuovo
  workspace + `removeTab` dall'origine nella stessa mutazione sincrona, così il reconcile delle
  surface non sfratta mai la tab. Il nuovo workspace eredita la cwd come `rootPath` e nasce
  `.default` (nominabile). No-op sull'unica tab. Testato (`moveTabToNewWorkspace`).
- **Giro di pulizia del codice** (refactor a comportamento invariato, undici commit atomici
  verificati uno per uno, incluso un passo adversariale commit per commit): componenti UI condivisi
  in `Panels` (`StatusDot`/`CommandChip`/`CloseButton` + token font/tint), dedup nel model
  (`RelayTheme.copy`, helper setter di `AppSettings`, `Array.move`, lookup `tab(id:)`),
  trigger-policy della nomina estratta pura in `Core.NamingTriggerPolicy`, `FullOverlayPresenter`
  unico per dashboard/onboarding, `reveal(workspaceID:tabID:)` centralizzato, conversione
  `NSColor(relay:)` unica in `TerminalEngine`, errori I/O non più inghiottiti (drain/backup/CLI),
  dead code rimosso.
- **CI deterministica**: gli strumenti di lint erano installati con `brew install` (sempre
  l'ultima), e una regola nuova di SwiftFormat bocciava codice invariato - CI **rossa da 0.7.0**.
  Ora versioni **pinnate** (binari dai release GitHub in `.build/tools` via `make tools`), stesse
  in CI e locale.

## Fatto - Rifiniture: input internazionale, LRU, osservabilità (post-pulizia)

- **Testo da `Option` e scorciatoie convivono** (`Core.KeyboardTextInput`, policy pura unica): su
  layout internazionali `Option` è AltGr, quindi un carattere stampabile composto da `Option` senza
  `Cmd/Ctrl` è digitazione e vince sulle scorciatoie (il monitor non consuma, la surface lo scrive
  UTF-8 nel PTY). **Eccezione dentro la policy**: `Option+1..9` senza Shift è il select-tab fisso e
  vince sempre - i tre consumatori (monitor, interceptor, recorder) restano coerenti per costruzione,
  senza dipendere dall'ordine dei local monitor. Prezzo esplicito: i simboli tipografici su
  `Option+cifra` non sono digitabili.
- **La LRU non sfratta più contesto recente**: `SurfaceEvictionPolicy` distingue le tab **protette**
  (visibile, workspace attivo, attenzione fresca, usate negli ultimi ~30 min) da quelle con lavoro
  vivo. Il cap resta un soft cap: sforare costa memoria, sfrattare costa contesto.
- **Runtime Stats** (`View > Runtime Stats…`): RSS, CPU, workspace/tab, surface vive/cap. Campiona
  solo a pannello aperto, non è polling permanente. Distinto da `PerfSampler` (dev tooling).
- **Note di release dai conventional commit** (`release-notes.sh`): `--generate-notes` dava un body
  vuoto su un repo trunk-based (genera dalle PR).

## Fatto - Split panes + multi-window (0.8.0)

Fatti **insieme** perché toccano gli stessi punti (cosa vuol dire "visibile", chi possiede le
surface, come si instrada il monitor): in sequenza li avremmo rifattorizzati due volte.

**Split = split di tab.** L'albero (`SplitNode`, puro e testato) vive sul **Workspace** e le sue
foglie sono `Tab.id`. Non c'è un'entità `Pane` sotto la Tab, come prevedeva il design originale: la
Tab *è* quel pane (il wire la chiama `paneId`), e abbassare l'attention model sarebbe costato il
doppio togliendo i badge per-sessione dalla tab bar. Prezzo accettato: un layout per workspace.

Da qui nascono due nozioni prima coincidenti: **montata** (a schermo in un pane) e **focused**
(riceve la tastiera). `isVisible` - che sopprime notifica e bump - segue la prima, non la seconda:
con due pane a schermo, un completamento su quello non focused non è arrivato mentre non guardavi.
`selectTab` diventa **monta o metti a fuoco**, e tutta la navigazione (tab bar, `Cmd+T`, click su
notifica, dashboard, `Cmd+J`) lo eredita senza casi speciali. `closePane` (⌥⌘W) smonta il pane ma
lascia viva la tab e la sua sessione; `Cmd+W` la uccide: due gesti, due tasti.

**Multi-window = partizione.** Uno store, un `layout.json`, un receiver, **una** `SurfaceRegistry`
(una tab ha una surface sola ovunque sia montata): spostare un workspace di finestra non ricrea i
pty. Ogni finestra ha la sua selezione; `store.selectedWorkspaceID` resta come **proiezione** della
key, così menu e scorciatoie non sanno nulla di finestre. Nessuna finestra è privilegiata: chiuderne
una **rimpatria** i suoi workspace in quella attivata più di recente.

`isVisible` si lega alla finestra **non occlusa** (`NSWindow.occlusionState`), **non** alla key: con
due monitor la finestra che fissi spesso non ha il focus, e notificarla sarebbe il bug del caso
d'uso che motiva la feature.

Rendering: `WorkspaceAreaController` riconcilia l'albero in `NSSplitView` annidate riusando le
`PaneView` per `Tab.id`, e ricostruisce **solo** se cambia la struttura (`hasSameStructure`) -
durante il drag di un divider cambiano solo i rapporti. Il first responder si prende solo quando
cambia il pane focused (un render scatta a ogni OSC 7 dello shell).

Persistenza **additiva**, nessun bump di `LayoutSnapshot.currentVersion`: `splitLayout`, `windowID`
e `windows` assenti nei layout vecchi ricadono su pane singolo e finestra unica. Al restore l'albero
è sanitizzato contro le tab davvero ricostruite (un pane orfano non è renderizzabile) e le finestre
senza workspace cadono.

Chrome **senza icone nuove** (i menu qui sono di solo testo; un pallino nella tab bar confliggerebbe
col badge di stato agente): la tab bar distingue focused (pill piena) da montata (pill tenue), il
menu contestuale della tab offre "Open in Split Right/Down" (porta una tab esistente in un pane
accanto, con la sua sessione viva) e quello del workspace "Move to New Window". Nuovo gruppo "Pane"
fra le scorciatoie rimappabili: ⌘\, ⌘⇧\, ⌘], ⌘[, ⌥⌘W.

**Ancora da fare**: trascinare un workspace **fra** finestre e una tab **fra** pane (oggi si passa
dai menu); riordinare i pane dentro l'albero col drag.

## Fatto - Split v2 sul modello cmux + menu bar HIG (post-0.8.2)

Il modello "split di tab" (sopra) aveva un difetto strutturale emerso all'uso: tab bar globale e
pane erano due viste dello stesso insieme di tab, con la semantica ambigua "montata vs
selezionata" e nessun posto naturale per "apri una tab accanto a questa porzione". Studiati
bonsplit (il framework di split di cmux, `manaflow-ai/bonsplit`) e la sua integrazione in cmux, e
adottato il suo pattern. Design e migrazione: `docs/features/split-panes.md`.

- **I pane ospitano le tab** (`SplitPane`: lista ordinata + selezione per pane; `Workspace.layout`
  sempre presente, `focusedPaneID`; `selectedTabID` derivato). La tab bar globale sparisce: ogni
  pane ha la **sua strip** (`PaneTabBar`) con action lane (nuova tab, split right/down), click su
  tab = selezione + focus al pane, doppio click sullo spazio = nuova tab. `selectTab` = **reveal**:
  non muta mai la struttura.
- **Chiusure**: `Cmd+W` chiude la tab selezionata del pane focused (selezione index-stable);
  l'ultima tab di un pane lo collassa; `closePane` (⌥⌘W, action lane, menu) chiude il pane **con
  le sue tab** (conferma sui processi in foreground). "Open in Split Right/Down" **sposta** la tab
  esistente in un pane accanto (sessione viva); no-op se è sola nella strip.
- **Migrazione senza bump**: il `Codable` di `SplitNode` decodifica il formato v1 (foglie-tab ->
  pane da una tab); le tab fuori dall'albero vengono adottate dal pane della selezione. Verificata
  sul layout reale (25/25 tab).
- **Fix del giro** (dalla review dello split v1): click-to-focus nel terminale (il click aggiorna
  il focus del model, non solo il first responder), first responder riasserito dopo ogni rebuild,
  ratio dei divider protetto dai layout pass programmatici (write-back solo con mouse premuto +
  riapplicazione al primo layout vero), navigazione che passa sempre da reveal, due fix
  multi-window (focusAttention attiva la finestra giusta; moveTabToNewWorkspace resta nella
  finestra d'origine).
- **Menu bar HIG-conforme**: ordine standard (Relay, File, Edit, View, Workspace, Pane, Go,
  Window, Help), Services/Hide/Show All, menu Window (`NSApp.windowsMenu`) e Help
  (`NSApp.helpMenu`), **File > New Window** (`⇧⌘N`) e **Close Window** (`⇧⌘W`, standard macOS;
  Close Workspace scala a `⌥⇧⌘W`), Find raggruppato, Enter Full Screen, menu Go coi **nomi reali**
  di workspace e tab (`menuNeedsUpdate`), nuovo menu Workspace con le azioni prima solo
  contestuali, keyEquivalent **veri** sulle voci (colonna nativa; il monitor consuma prima, e
  `validateMenuItem` disabilita con overlay aperti). Title Case ovunque.
- **Selezione che sopravvive all'output** (0.8.2, stesso giro): vedi gotcha in CLAUDE.md.

**Ancora da fare** (ereditato + nuovo): drag di tab fra pane (incluso l'edge-drop di bonsplit per
creare split trascinando), drag di workspace fra finestre, zoom del pane, equalize dei divider.

## Più avanti

- Distribuzione firmata: Developer ID + notarizzazione (toglie il bypass quarantena e apre a
  homebrew-cask ufficiale). Il tap brew non firmato c'è gia (vedi Fatto sopra).
- Dashboard: evoluzioni oltre l'MVP (azioni inline resume/chiudi, contatori in header, toggle
  raggruppa-per-workspace, preview ultime righe - richiede surface vive).
- **Generalizzazione multi-agente (Codex / opencode)** - vedi sotto.
- Export timeline; import da config Ghostty.

### Generalizzazione multi-agente

Prevista by design fin dall'inizio (tesi di prodotto: "molti coding agent", non "molte sessioni
Claude"; il protocollo resta aperto, `ARCHITECTURE.md` #Fonti-Stato e #Fuori-Scope-Baseline). Non
ancora pianificata come lavoro: qui il piano.

Stato del codice (misurato): il **core è già agnostico** - il wire ha il campo `agent`, gli stati
sono normalizzati, il reducer e `ResumeBinding` non conoscono Claude. La Claude-centricità è
**confinata** a `HookInstaller/ClaudeHookInstaller.swift`, il comando `relay-cli claude-hook`
(`ClaudeHookCommand`), il comando di resume (`claude --resume <id>`) e alcune stringhe UI
(NotificationCoordinator, AppController, ResumeBar, SettingsView). Il boundary progettuale è già nel
posto giusto.

Cosa espone ogni agente (verificato luglio 2026): **Codex** ha hook con nomi di evento quasi
identici a Claude (`PreToolUse`, `PermissionRequest`, `PostToolUse`, `SessionStart`, `Stop`,
`UserPromptSubmit`, `SubagentStop`) via `hooks.json` o `[hooks]` in `config.toml` - stesso paradigma,
cambia solo il vettore di installazione. **opencode** espone un event bus (`session.created`,
`session.idle`, permission events) consumato da un plugin TS - segnali chiari, vettore diverso (un
plugin che scrive sul socket, non un hook shell).

Piano in tre passi, quando si apre il giro:

1. **Spike di verifica per agente**: cosa espone ognuno e quanto è affidabile il segnale, in
   particolare `needs_input` (le approval mode variano tra agenti). Non solo Codex/opencode: mappare
   il modello reale, non assumerlo.
2. **Refactor `AgentIntegration` + Codex insieme**: estrarre l'astrazione **mentre** si aggiunge il
   secondo agente (regola di due), non prima. Astrarre su un solo esempio ripete la trappola
   "interfaccia modellata troppo intorno a un backend" già nota per `TerminalEngine`. Codex prima
   perché il paradigma hook è quasi identico (mapping quasi copia-incolla, cambia il vettore).
3. **opencode come secondo banco di prova** del boundary (plugin TS -> socket). È il modello più
   diverso: se l'astrazione regge qui, regge.

Rischio da tenere in conto: il differenziatore ("stati affidabili senza parsing output") vale finché
ogni agente dà un segnale altrettanto affidabile; N integrazioni = N pipeline che evolvono e si
rompono. **Resta fuori scope** l'orchestrazione multi-agent nella stessa sessione (cosa diversa dal
supportare più agenti; `ARCHITECTURE.md` #Fuori-Scope-Baseline).

## Fatto - cwd di `Cmd+T` dalla shell viva (0.7.8)

La nuova tab ereditava la cwd solo dall'ultimo OSC 7 noto. Ma zsh in Relay **non emette OSC 7**:
`/etc/zshrc` carica l'integrazione da `/etc/zshrc_$TERM_PROGRAM` e non settiamo `TERM_PROGRAM` di
proposito (maschererebbe il kitty keyboard protocol). La shell senza integrazione non era un caso
limite: era il default, e `Cmd+T` apriva alla radice del workspace.

- La cwd si legge dal processo shell della surface viva (`TerminalSurfaceHandle.currentDirectory()`,
  `proc_pidinfo`), con precedenza **shell viva -> ultimo OSC 7 noto -> root del workspace**, decisa
  dal puro `Core.CurrentDirectory` invece che da cascate `??` sparse fra i layer. L'ordine è la
  parte che conta: col valore memorizzato davanti, la lettura live non verrebbe mai consultata (dopo
  il primo `Cmd+T` la tab ha sempre una cwd nota) e l'ereditarietà resterebbe cieca ai `cd`.
- Il risultato **non** si memoizza su `Tab.currentDirectory`: quel campo è l'ultimo OSC 7 noto e
  alimenta anche titolo, sottotitolo e snapshot, che si congelerebbero alla cwd dell'ultimo `Cmd+T`.
- Coperto fino al pty vero: un test avvia una shell reale, le manda un `cd` e verifica che la
  surface segua; un altro copre la precedenza nell'area (invertendo la cascata, fallisce).

## Prossima azione

Baseline chiuso e app **distribuita via Homebrew tap** (`brew install --cask essedev/relay/relay`),
con dashboard di triage, onboarding di benvenuto, **split v2 sul modello cmux** (pane che ospitano
tab, strip per pane) e **multi-window**. Prossimo giro a scelta: distribuzione **firmata**
(Developer ID + notarizzazione, per homebrew-cask ufficiale), generalizzazione multi-agente
(Codex/opencode), oppure il drag di tab fra pane / workspace fra finestre (vedi Fatto - Split v2).
