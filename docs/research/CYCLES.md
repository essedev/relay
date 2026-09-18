# Cycles

Questo file traccia i cicli di lavoro e le decisioni prese durante l'analisi del terminale
agent-aware.

I cicli 0-8 (analisi engine, V0, agent runtime, primo giro UI/UX) sono in
`cycles-archive/CYCLES-0-8.md`: qui restano gli ultimi ~15, numerazione intatta.

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

**Padding del ring**: due leve indipendenti in `WorkspaceAreaController` - `AttentionRingView.strokeInset`
(gap ring ↔ bordo esterno) e `terminalInset` (contenuto ↔ bordo); l'aria contenuto-ring è la loro
differenza. Il ring copre l'intera zona, il terminale è inset di più. Tarato a 6 + 6.

**Ritocco icona** (`bundle/make-icon.swift`): chevron `>` a ~80% dell'altezza del cursore (accento,
più sottile) con gap ampio dal cursore, cursore più alto e slanciato; il cursore resta l'elemento
dominante. Verifica visiva rigenerando il PNG di preview prima dell'`.icns` (`make icon`).

### Scorciatoie rimappabili + gap hotkey

Valutata la completezza degli hotkey (mancavano cicla tab/workspace, chiudi workspace, find
next/prev, jump indietro) e chiesto lo scope della sezione impostazioni: scelta la rimappatura
completa (non solo il cheat-sheet). Architettura a **un solo punto di dispatch**: invece dei
`keyEquivalent` di menu (che non gestiscono ogni combo e li avevo già dovuti aggirare per i numeri),
tutte le azioni rimappabili passano dallo stesso `NSEvent` local monitor, che matcha la `KeyCombo`
dell'evento contro i binding ed esegue `perform(action)`. Vantaggio: rimappare è solo aggiornare un
dizionario; gestisce qualsiasi combinazione. I menu mostrano la combo nel titolo (`keyEquivalent`
vuoto, niente doppio trigger), ricostruiti al cambio.

- Modello puro in `WorkspaceModel` (`ShortcutAction`, `KeyCombo`), persistenza + conflitti in
  `AppSettings` (JSON in UserDefaults, default per azione). Nuove azioni cicliche nello store
  (`selectAdjacentTab/Workspace`, `focusPrevAttention`), testate.
- `KeyEventBridge` (NSEvent -> KeyCombo) in Panels, così lo usano sia il recorder sia il monitor
  (relay sta sopra Panels). Tasti speciali per keyCode, caratteri via `charactersIgnoringModifiers`.
- Recorder in impostazioni (`ShortcutsList`): clic su una combo -> monitor temporaneo cattura la
  nuova (Esc annulla), con `settings.isCapturingShortcut` che fa da parte il monitor globale.
  Conflitti segnalati, combo di sistema rifiutate, reset per azione o globale. Categoria "Shortcuts"
  con sezione fissa read-only per i select-by-number.

Gotcha: `keyDown`/`mouseDown` di SwiftTerm sono `public` non `open` (già scoperto per il ring), per
questo l'intercettazione è tutta nel monitor, non in override della view.

`make check` verde (125 test). Prossimo giro a scelta: distribuzione firmata (Developer ID +
notarizzazione), dashboard overview, oppure split.

## Cycle 11 - Distribuzione (brew tap + firma) e rifiniture terminale

### Obiettivo

Rendere Relay installabile e aggiornabile da altri con un comando, senza pipeline pesanti; e chiudere
due attriti d'uso emersi: larghezza sidebar troppo stretta e non persistita, e Shift+Invio che non va
a capo in Claude Code. Metodo di questo ciclo: **misurare, non dedurre** - ogni pezzo validato dal
vivo prima di consolidarlo.

### Distribuzione via Homebrew tap

Scelta: tap personale (`essedev/homebrew-relay`, pubblico) con cask che scarica il `.dmg` dalle
Release di `essedev/relay` (repo reso pubblico dopo scan segreti su tutta la history). Niente
homebrew-cask ufficiale (richiederebbe notarizzazione + review): per pochi utenti il tap basta e
l'update è `brew upgrade`. Versione = `./VERSION` (semver, source of truth), iniettata nel bundle al
build via PlistBuddy. `scripts/release.sh` (via `make release`) è la routine ripetibile: check
working tree pulito + branch main + account gh, blocca se il tag esiste, build dmg -> sha256 ->
push branch+tag -> `gh release create` con l'asset -> aggiorna `version`+`sha256` nel cask del tap.

### Firma: self-signed stabile, non ad-hoc, non notarizzata

La firma ad-hoc cambia identita a ogni build (il collega rifa "Apri comunque" a ogni upgrade, le
notifiche decadono). Notarizzazione = Developer ID a pagamento, fuori scope ora. Via di mezzo:
**certificato self-signed stabile** in un keychain dedicato (`~/.relay/codesign`, non tocca il login
keychain). Trabocchetto scoperto per prova: `codesign` rifiuta un cert non-trusted ("no identity
found") e risolve l'identita dalla **search list** dei keychain, non dal flag `--keychain`. Quindi
`setup-signing.sh` (idempotente) crea cert+keychain, aggiunge il keychain alla search list, e il
trust richiede **un** `sudo` una tantum (macOS non lo concede senza password: unico passo non
automatizzabile). Verificato: bundle firmato `Authority=Relay Self-Signed`, `verify --deep --strict`
ok.

Quarantena: `quarantine false` non esiste piu nel DSL di Homebrew 6. Si ottiene lo stesso effetto con
un `postflight` che fa `xattr -cr` sull'app (stesso pattern del cask `portsage`): niente prompt
Gatekeeper "app non verificata" all'apertura. È un bypass consapevole del gate, per software nostro.

### Shift+Invio in Claude Code: kitty keyboard protocol (indagine empirica)

Il caso da manuale del "misurare invece di dedurre". Ipotesi iniziali (encoder scollegato, opzione da
abilitare) **smentite dal codice**: SwiftTerm implementa il kitty keyboard protocol completo su macOS
(risponde a `CSI ? u`, gestisce push/pop, encoda l'input via `KittyKeyboardEncoder` nel `keyDown`).
Test dal vivo (`printf '\e[>1u'; cat -v` + Shift+Invio) -> `^[[13;2u`: il terminale encoda
perfettamente. Quindi il gap non era in Relay.

Dal binario di Claude Code: ha il supporto kitty e il binding Shift+Invio, ma **attiva il protocollo
solo per terminali in una allowlist su `TERM_PROGRAM`** (`iTerm.app`/`kitty`/`WezTerm`/`ghostty`) -
non usa la query dinamica che pure saprebbe parsare. Relay (`xterm-256color`, nessun `TERM_PROGRAM`)
non è riconosciuto, quindi non attiva. Primo fix: annunciarsi `TERM_PROGRAM=ghostty` (funziona), ma
è uno spoof di identita globale (ogni app crede di girare in Ghostty; rischio feature ghostty-only,
es. notifiche desktop via OSC che SwiftTerm non gestisce). Ricerca -> issue
`anthropics/claude-code#27868`: il modo raccomandato per un terminale custom è dichiarare il
supporto con `KITTY_WINDOW_ID` **senza** spoofare `TERM_PROGRAM` (che Claude Code prioritizza e che
altrimenti maschera il segnale). Validato dal vivo (`env -u TERM_PROGRAM KITTY_WINDOW_ID=1 claude`),
adottato `KITTY_WINDOW_ID=1` nell'env della surface: kitty nativo (Shift+Invio, Ctrl+Invio, ...) senza
intercettare l'input e senza fingere un'altra identita.

### Sidebar width persistita

La larghezza sidebar non era in `LayoutSnapshot` (a ogni avvio ripartiva dal minimo ~200). Spostata
in `AppSettings` (preferenza UI globale, UserDefaults), default 250, clamp 200-340;
`MainSplitViewController` la applica alla prima passata di layout e la salva sul resize.

### Esito

Relay installabile con `brew install --cask essedev/relay/relay`, aggiornabile con `brew upgrade`,
primo avvio senza prompt Gatekeeper. Release ripetibile con `make release`. Shift+Invio nativo in
Claude Code. `make check` verde. Non ancora fatto: distribuzione firmata Developer ID + notarizzazione
(toglierebbe il bypass quarantena e permetterebbe homebrew-cask ufficiale), split.

## Cycle 12 - Riordino libero di workspace e tab (drag gesture)

### Obiettivo

Poter spostare i workspace nella sidebar e le tab dentro un workspace **dove si vuole**, con un drag
& drop fluido e un indicatore di dove cadrà la riga.

### Il punto di partenza (e perché non bastava)

Il drag dei workspace c'era già (`.draggable`/`.dropDestination` -> `moveWorkspace(_:onto:)`), ma
"non teneva": due cause sommate. **Uno**, la sidebar mostra `orderedWorkspaces` (partizione derivata:
pinned -> con attenzione -> resto), quindi dopo il drop il float rimescolava comunque - un non-pinned
non poteva andare sopra un pinned, e un workspace che prendeva attenzione saltava in cima da solo.
**Due**, il target del drop arrivava dall'ordine *visivo* ma l'insert avveniva sull'indice *canonico*:
quando i due ordini divergevano, la riga finiva in un punto diverso da dove la lasciavi. Le tab, invece,
non erano proprio riordinabili (nessun `moveTab`, nessun drag nella tab bar).

### Decisioni

- **Float invariato, drag reso onesto** (scelta dell'utente: tenere il float pin/attenzione). L'ordine
  manuale ha effetto *dentro* il segmento di float; fra segmenti il float vince. Per non mentire,
  l'indicatore di inserimento è **vincolato al segmento** del workspace trascinato (`segmentIndex(for:)`
  in `WorkspaceStore`): la linea si muove solo tra le righe dello stesso gruppo. Quello che vedi è
  quello che ottieni.
- **Store puro e posizionale.** Rimpiazzato `moveWorkspace(_:onto:)` con `moveWorkspace(_:before:)`
  (inserisce prima del target, `nil` = in fondo); aggiunti `moveTab(_:before:in:)` e
  `Workspace.moveTab`. Le tab hanno un ordine unico, nessun float, quindi lì il riordino è pieno e
  l'indicatore sempre affidabile. Tutto testato (logica pura).

### La svolta sulla fluidità: via il drag di sistema

Prima iterazione con `.onDrag`/`.onDrop` di SwiftUI: funzionava ma al rilascio la preview
semitrasparente faceva **snap-back** (volava alla posizione originale prima di sparire), poi partiva
lo scambio - a scatti. Causa: `onDrag` genera una drag image gestita dal sistema, su cui il controllo
è minimo. Non è un bug da tunare, è il modello sbagliato per un reorder *in-app*.

Seconda iterazione (adottata): niente drag di sistema. Trasciniamo la **riga vera** con un
`DragGesture` + `.offset` (sollevata: opacity ridotta, zIndex alto) che segue il puntatore; una linea
segnala l'inserimento; al rilascio lo scambio parte in `withAnimation` mentre l'offset torna a zero,
così la riga si posa senza salti. Chiave tecnica: l'`.offset` è un trasform di *rendering*, non tocca
il frame di *layout* - quindi i frame raccolti via `PreferenceKey` (in un coordinate space nominato)
restano stabili durante il gesto e il calcolo dell'indice di inserimento non si sballa. Bonus:
l'identità del trascinato vive in `@State`, niente pasteboard condivisa e niente drop incrociati
sidebar/tab. Su macOS lo `ScrollView` non fa drag-scroll, quindi il `DragGesture` non confligge con
lo scroll.

Il meccanismo è generico (asse verticale/orizzontale) in `Panels/Reorderable`: `reorderableRow`,
`reorderableContainer`, `ReorderInsertionLine`, condivisi da sidebar e tab bar.

### Esito

Riordino libero e fluido di workspace (dentro il segmento di float) e tab (pieno). Persistence gratis:
lo snapshot serializza già l'ordine di `workspaces`/`tabs`, l'autosave scatta da sé. `Cmd+1..9` e
`Cmd+J` leggono `orderedWorkspaces`, quindi restano coerenti. `make check` verde (150 test). Verifica
del gesto a video con `make run`.

## Cycle 13 - Ordine sidebar "lista chat" (bump reale, via il float)

### Il problema

Prendere un workspace salito in cima per un completamento e scriverci lo faceva **scivolare giù**
sotto le mani: appena parte `running` il marker di attenzione si spegne (l'hai ripreso) e, siccome
la posizione era un **float derivato** dall'attenzione (`orderedWorkspaces` partizionava per
`needsAttention`), la riga usciva dal gruppo alto e cadeva. Fastidioso: la riga su cui lavori non
deve muoversi.

### La diagnosi

Nella sidebar convivono due movimenti distinti, e il float li accoppiava sbagliando:

- **In background** (una chat completa mentre guardi altrove -> sale): lo vuoi, è il senso del float.
- **Sotto le mani** (interagisci con una chat -> si sposta): non lo vuoi.

Il modello mentale giusto dell'utente non era "float" ma **lista chat** (Slack/WhatsApp): l'attività
porta la riga in cima e *quello diventa il suo posto*; ci resta finché non la scavalca altra attività
o non la sposti a mano; il pin è per fissarla. La ripresa non è un evento che deve riordinare.

### La decisione (ribalta la scelta del Cycle 12)

Il Cycle 12 aveva tenuto il "float invariato". Qui lo si smonta: **la posizione diventa un ordine
reale e persistente**, non una proiezione dello stato.

- `orderedWorkspaces` torna a `pinned + resto` in ordine **canonico**, niente partizione per
  attenzione.
- Un'attività **non vista** (completamento o entrata in `needs_input`) fa un **bump** reale:
  `WorkspaceStore.bumpWorkspaceToTop` porta il workspace in cima ai non-pinned, mutando l'ordine
  canonico (persistito). Gate su `!isVisible`, **simmetrico** al segnale forte (`unseen`) e alla
  notifica: un solo criterio governa segnale, notifica e posizione.
- La **ripresa** (`running`) e ogni evento sulla tab in vista **non** muovono nulla. `attention`
  resta solo un segnale (badge/ring), scollegato dall'ordine; declassamento, dismiss e decadenza
  spengono il segnale ma non fanno scendere la riga (scende solo col drag).
- `SidebarDrop` scende da tre segmenti (pinned/attenzione/resto) a **due** (pinned/resto): il
  segmento float non esiste più.

### Il caso "mentre la guardi"

Deciso oggettivamente che un completamento **sulla tab in vista non bumpa**: il bump è un richiamo
verso qualcosa che non hai visto, e se lo stai già guardando è rumore (oltre a essere di nuovo un
movimento sotto le mani). Stessa logica del segnale (`unseen` non visto / `pending` visto): un solo
`isVisible` decide tutto. Il risultato netto: **la sidebar si muove solo per ciò che accade fuori
dalla tua vista**.

### Esito

La riga su cui lavori sta ferma; il resto sale in background e ci resta. `make check` verde (226
test), incluso `resumeDoesNotDropFromTop` (il caso esatto del bug: riprendi una riga in cima, ci
scrivi, resta su).

## Cycle 14 - Pulizia codebase, CI deterministica, move-tab

### Obiettivo

Un giro di pulizia sistematica del codice (duplicazione, componenti UI, dead code) a comportamento
invariato, la messa in sicurezza della CI (rossa da due release) e una piccola funzione: spostare
una tab in un nuovo workspace.

### Pulizia (refactor a comportamento invariato)

Revisione sistematica, poi undici commit atomici, ognuno verificato (build + lint + test) e passato
a una **verifica adversariale commit per commit** (un agente scettico per commit):

- **Panels**: estratti i componenti condivisi `StatusDot`/`CommandChip`/`CloseButton` (prima
  duplicati a mano con dimensioni divergenti) e tokenizzati i font/tint ricorrenti nel design system.
- **Model**: `RelayTheme.copy` unico dietro i tre `withX`, helper `update`/`toggle` per i setter di
  `AppSettings` (via keypath, compatibile con Observation), `Array.move` generico, lookup `tab(id:)`
  condiviso.
- **Composition root**: `FullOverlayPresenter` unico per gli overlay full-window (mutua esclusione
  per costruzione, prima cablata a mano), `reveal(workspaceID:tabID:)` centralizzato, dead code
  rimosso.
- **Core/Engine**: trigger-policy della nomina estratta pura in `Core.NamingTriggerPolicy` (testata),
  conversione `NSColor(relay:)` unica in `TerminalEngine` (prima triplicata).
- **I/O**: errori di trasporto/backup non più inghiottiti (drain, LayoutStore), path hook
  shell-escaped, exit code del CLI.

La verifica adversariale ha intercettato due regressioni visive sfuggite (larghezza della pill del
recorder di shortcut e colore del comando nel popover update), poi corrette prima del push.

### CI deterministica (il version skew di SwiftFormat)

La CI era **rossa da 0.7.0**: falliva in ~15s sul lint. Causa: il workflow faceva `brew install
swiftformat` (sempre l'ultima), e una regola nuova (`redundantParens`, poi `wrapIfStatementBodies`)
bocciava codice invariato che la SwiftFormat locale, più vecchia, non vedeva. Ogni versione vede
errori diversi: `brew install` flottante rende la CI non-deterministica. Soluzione: strumenti
**pinnati** a versione fissa, scaricati come binari dai release GitHub in `.build/tools` (`make
tools`, stamp versionato per il bump); CI e locale girano la stessa versione. Il fix di codice vero
era di 3 righe (le parentesi che la versione pinnata vuole).

### Move to New Workspace

Dal menu contestuale di una tab (solo con >=2 tab) la si estrae in un nuovo workspace placeholder
**senza toccare la sessione viva**: lo store sposta lo stesso oggetto `Tab` (stesso `Tab.id`),
quindi la surface/pty resta intatta. Chiave: append del nuovo workspace + remove dall'origine nella
stessa mutazione sincrona, così il reconcile delle surface non sfratta la tab. Il nuovo workspace
eredita la cwd come `rootPath` e nasce `.default` (nominabile). Testato (stesso oggetto, no-op sui
casi limite).

### Esito

`make check` verde (279 test), CI di nuovo verde e **deterministica**. Undici commit di pulizia + il
fix CI + la funzione, rilasciati come patch 0.7.2.

## Cycle 15 - Rifiniture: input internazionale, LRU, osservabilità

### Obiettivo

Il giro di patch dopo il baseline delle milestone (0.7.3 -> 0.7.6): tre difetti emersi dall'uso
reale (tastiera italiana, contesto perso dalla LRU, nessuna visibilità sui consumi) più le note di
release. Nessuna feature grossa: correggere ciò che si rompe sotto le dita.

### Testo da `Option` vs scorciatoie (il giro completo)

Sui layout internazionali `Option` è anche AltGr: `Option+ò` compone `@`, `Option+è` compone `[`.
Relay intercettava quelle combinazioni come scorciatoie, quindi **i simboli non si potevano
digitare** nel terminale. Il primo fix (`924aee8`, 0.7.4) ha introdotto la policy pura
`Core.KeyboardTextInput`: se macOS produce testo stampabile da `Option` senza `Cmd/Ctrl`, quel testo
vince; il monitor non consuma l'evento e `OptionTextInterceptor` lo scrive UTF-8 nel PTY prima che il
kitty keyboard protocol lo codifichi come tasto modificato.

Ma la regola era **troppo larga**: sull'italiano anche `Option+1..9` compone simboli tipografici
(`Option+1` = `«`, `Option+2` = `™`), quindi la policy classificava come digitazione anche il
select-tab fisso e **`Option+1..9` smetteva di cambiare tab**. Un difetto tipico da regola universale
su un dominio con eccezioni.

Fix (`ec28342`): l'eccezione vive **dentro la policy**, non nei chiamanti. `Option`+cifra 1..9 senza
Shift non è mai testo. Così i tre consumatori (monitor di navigazione, interceptor verso il PTY,
recorder delle impostazioni) restano coerenti **per costruzione**, senza dipendere dall'ordine in cui
i local monitor vedono l'evento - la stessa logica che tiene il resto dell'input in un punto solo.
Tutto il resto continua a essere digitazione: `Option+ò`, `Option+Shift+cifra`, `Option+0`. Tradeoff
accettato ed esplicito: i simboli su `Option+cifra` non sono digitabili finché la scorciatoia esiste.
I flag dei modificatori sono passati come `OptionSet` puro (`KeyboardTextInput.Modifiers`), non come
quattro `Bool`.

Costo di non aver messo l'eccezione subito: una release (0.7.4) in cui le tab non si cambiavano da
tastiera su ogni layout non-US.

### LRU: proteggere il contesto recente

Il cap LRU sfrattava surface idle appena sopra il cap, anche quelle usate un minuto prima: lo
sfratto è un teardown SwiftTerm (scrollback perso, shell ricreata). `678ff3b` (0.7.5) aggiunge alla
policy pura (`SurfaceEvictionPolicy`) il concetto di tab **protetta** oltre a quello di tab con
lavoro vivo: mai la visibile, le tab del workspace attivo, quelle con attenzione fresca, quelle
toccate negli ultimi ~30 minuti. Il cap resta un **soft cap**: se i candidati non bastano si sfora,
perché sforare costa memoria mentre sfrattare costa contesto dell'utente.

### Runtime Stats

`2cf55ee` (0.7.6): pannello read-only da `View > Runtime Stats…` con RSS, CPU del processo,
workspace/tab e surface vive rispetto al cap. Il campionamento (`RuntimeStatsSampler`, ~2s) gira
**solo finché il pannello è aperto** e il timer muore in `windowWillClose`: è osservabilità a
richiesta, non polling permanente. Resta distinto da `PerfSampler`, che è dev tooling
(`RELAY_PERF`) e misura anche la latenza di input.

### Note di release dai conventional commit

`gh release create --generate-notes` produceva un body vuoto: genera dalle PR, e il repo è
trunk-based. `9cb3b61` lo sostituisce con `release-notes.sh`, che raggruppa per tipo i conventional
commit tra due tag, più `backfill-release-notes.sh` per riscrivere il body delle release già
pubblicate senza toccare tag, asset o cask.

### Esito

`make check` verde (291 test, inclusi i casi della policy: cifre riservate, `Option+Shift+cifra` e
`Option+0` restano testo). Su tastiera italiana funzionano **entrambi**: `Option+1..9` cambia tab e
`Option+ò` scrive `@`.

## Cycle 16 - Gruppi nella sidebar e drag cross-container

### Il problema

Con qualche decina di workspace la sidebar è un elenco piatto: pin e archivio bastano per gli
estremi (quello che uso sempre, quello che non uso più), non per il mezzo - i cinque workspace dello
stesso cliente, i tre di un progetto. Modello di riferimento: i tab group di Brave/Chrome.

### La forma decisa (prima di scrivere codice)

Il giro è partito da una discussione, non da un'implementazione. I punti che hanno cambiato il
disegno:

- **Un gruppo fisso affonda.** Se il bump di un workspace libero inserisce sempre in cima ai
  non-pinned, ogni completamento scavalca la card: dopo un giorno i gruppi sono in fondo. Da qui il
  **pin del blocco** (`WorkspaceGroup.pinned`), che è il modo di dire "questa resta in alto".
- **Un gruppo collassato è un buco nero.** Un membro che chiede attenzione dentro una card chiusa
  sparirebbe: la card chiusa porta il **conteggio dei membri da vedere** nella sua tinta.
- **Tre assi di stato sono troppi.** `pinned`, `archived` e `groupID` si escludono a vicenda:
  entrare in una card azzera pin e archivio, e dentro una card a pinnare è il gruppo. Senza questa
  regola il resolver del drop avrebbe tre dimensioni e nessuno saprebbe più dire cosa fa un drop.
- **Il drag dentro/fuori l'archivio mancava** (in sospeso da M4), e sarebbe stato incoerente avere
  il drag verso i gruppi ma non verso l'archivio: sono la stessa primitiva - un drop che, oltre a
  riordinare, cambia un campo del workspace. Decisione dell'utente: farli insieme.

### Modello: l'appartenenza sta sul workspace

`WorkspaceGroup` porta **solo l'aspetto** (nome, colore, collasso, pin); i membri sono
`Workspace.groupID`. È la scelta che tiene semplice tutto il resto: nessun secondo ordinamento da
tenere in sync col riordino, col bump, col restore o col rimpatrio alla chiusura di una finestra; la
posizione della card è quella del suo primo membro; la contiguità è una comodità (`compact`,
`place`) e non un invariante da cui dipende la correttezza. Corollario accettato volentieri: **un
gruppo senza membri non esiste**, come l'ultima tab chiude il workspace.

Il bump diventa **per contenitore**: un membro sale in cima alla sua card, un libero in cima alla
lista (quindi sopra la card). La card si muove solo con pin o drag.

### Righe e slot: il confine che nessuna euristica scioglie

Il drop non può dedurre il contenitore dai vicini, perché "in fondo alla card" e "sotto la card"
sono **lo stesso pixel** con due significati. La soluzione non è un'euristica migliore ma più
informazione: la sidebar viene srotolata in un piano di righe e **slot** (`SidebarLayout`), dove
ogni slot porta scritto il proprio contenitore, deciso alla costruzione; e la card ha una **riga di
coda** (`groupTail`) che è insieme il suo padding inferiore e lo slot con un solo significato. Da lì
`SidebarDrop` fa solo lavoro posizionale, resta puro e si testa senza UI.

### Il costo vero: la meccanica del drag

Il drag esistente (`Reorderable`) funziona **dentro una sola ScrollView**: frame via `PreferenceKey`
e riga vera spostata con `.offset`. Nessuna delle due cose regge il cross-container:

- le preference **non attraversano** il bridge `NSScrollView` (stessa trappola che teneva la sezione
  Archive alta 1px), quindi i frame delle righe archiviate non arriverebbero mai al registro comune
  -> coordinate space unico a livello sidebar + `onGeometryChange`;
- la riga in volo dentro la sua ScrollView viene **clippata al bordo**, cioè sparisce esattamente
  quando esci dal contenitore -> copia disegnata in overlay sopra tutta la sidebar, originale
  sbiadito al suo posto.

Da cui `SidebarReorder`, separato da `Reorderable` (che resta per la strip dei pane, contenitore
unico): due meccaniche per due problemi diversi, con in comune le parti pure. Effetto collaterale
voluto: la lista principale non è più `LazyVStack` - una riga smontata non misura il frame.

### Esito

`make check` verde (430 test, di cui ~25 nuovi fra piano/slot, resolver e store dei gruppi). Il
resolver è coperto dai test puri; il **gesto** no (nessun test copre un `DragGesture` reale), quindi
la parte a mano è stata provata dal vivo con `relay --demo`, che ora semina una card di esempio:
riga dentro e fuori da una card, riga dentro e fuori dall'archivio, card intera trascinata e
pinnata, collasso col contatore. Restano fuori: drag di una card fra finestre, archiviazione di un
gruppo in blocco, annidamento.

## Cycle 17 - Dove nasce una cosa nuova

### Il problema

`Cmd+T` e `Cmd+N` creavano sempre **in fondo**: la tab nuova a fine strip, il workspace nuovo in
coda alla sidebar. Nessuna delle due posizioni ha a che vedere con il punto da cui hai premuto il
tasto, e con la sidebar "lista chat" (Cycle 13) il fondo è per giunta il posto che il primo bump
altrui scavalca.

### La diagnosi

Chiedere "dopo il selezionato" sembra la stessa cosa per le due liste, ma non lo è: la strip di un
pane è un ordine unico e piatto, mentre `store.workspaces` non è l'ordine visivo, ne è la sorgente.
La proiezione (`sidebarItems`) rompe l'adiacenza in tre punti:

- il **pin** partiziona (un non-pinned infilato dopo un pinned finisce a capo del segmento libero);
- una **card** viene emessa alla posizione del suo *primo* membro, quindi un non-membro incastrato
  fra due membri compare sotto tutta la card, non sotto la riga;
- un **archiviato** sta fuori da `orderedWorkspaces`: ancorarcisi dà una posizione che nella lista
  non esiste.

### La decisione

L'ancora è la selezione **della finestra di destinazione**, con eredità del `groupID`: creare dentro
una card crea dentro quella card, uscirne è un drag come entrarci (`insertionAnchor`). Non è
neutralità sul contenitore, è la scelta opposta: l'appartenenza segue il contesto, non aspetta un
gesto separato.

Delle tre rotture, due si risolvono accettandole invece di combatterle. L'**archiviato** è l'unico
caso in cui l'ancora salta del tutto (fallback al fondo, il vecchio comportamento). Il **pin** non
si eredita: il nuovo apre il segmento non pinned, la riga più vicina che gli è concessa. La **card**
non è più una rottura, perché l'eredità del gruppo la trasforma nel caso normale.

Effetto collaterale voluto: creazioni in sequenza conservano l'ordine di creazione, perché ognuna
diventa l'ancora della successiva (demo mode e restore invariati).

### Esito

`make check` verde (439 test, 9 nuovi in `InsertionOrderTests`: tab, pane focused, gruppo, card
chiusa, pin, archivio, finestra non key, sequenza, move-tab). Il codice posizionale esce in
`WorkspaceStore+Ordering` perché il file principale aveva sforato il budget di 400 righe.

Un caso emerso scrivendo i test: nascere dentro una card **collassata** rendeva selezionato un
workspace la cui riga non è a schermo. `createWorkspace` scrive `selectedWorkspaceID` diretto, non
passa da `reveal`, quindi l'apertura della card va ripetuta lì.

## Cycle 18 - Una guida sola, letta in due posti

### Il problema

Nessuno sapeva cosa Relay sapesse fare, documentazione compresa. Il censimento della superficie
utente - 23 aree, contate su menu bar, contestuali, `ShortcutAction` e preferenze - contro quello
che era scritto da qualche parte ha dato **9 aree spiegate in nessun posto**: il drag di una tab su
un altro workspace, "Move Tab to New Workspace", il riordino nella strip, "Open in Split
Right/Down", rename/ungroup/remove from group, la nomina automatica, i tre livelli di attenzione con
Mark as Read e la decadenza, il check aggiornamenti, Runtime Stats.

E `README.it.md` era fermo a ~0.11: gli mancava un'intera sezione (gruppi e archivio) e ogni
menzione di finestre, drag e naming. Non per trascuratezza: perché era una **seconda prosa**, e una
seconda prosa diverge sempre.

### La diagnosi

La domanda giusta non era "dove scriviamo il manuale" ma "quante copie della verità ci teniamo".
L'onboarding aveva già trovato la risposta per sé: le sue pagine mostrano i **componenti veri**
invece di screenshot, e leggono le combo dai binding (`OnboardingPages.swift`), quindi non
invecchiano. Il README fa l'opposto - una lista di scorciatoie a mano e un hero PNG - ed era
infatti la parte più stantia del repo, con un'immagine di sei release prima.

Un manuale in-app scritto come prosa in SwiftUI avrebbe solo aggiunto una terza copia da tenere
allineata a README e onboarding.

### La decisione

Il contenuto è un **dato** (`Guide.sections`), non un testo: sezioni fatte di blocchi tipizzati.
Due rese lo leggono - il pannello `Help > Relay Guide` e `GuideMarkdown` -> `docs/GUIDE.md` - e
nessuna delle due possiede il contenuto.

Tre conseguenze che valgono più della struttura in sé:

- **La tabella delle scorciatoie non si scrive.** Il blocco `.allShortcuts` la genera da
  `ShortcutAction.allCases`: un'azione nuova compare da sola in entrambe le rese, e un test fallisce
  se qualcuna resta fuori. Era la parte del README destinata a divergere per prima.
- **I tasti dipendono da chi legge.** Nel pannello vengono dai binding vivi (se rimappi, la guida
  mostra la tua combo), nel markdown dai default di fabbrica: un file committato non può dipendere
  dalle preferenze di chi lo genera.
- **Il file generato è verificato**, non raccomandato: `committedGuideMatchesTheGeneratedOne`
  fallisce in CI se `docs/GUIDE.md` non è quello che la fonte produce.

Sta nel menu Help, non nelle impostazioni: quelle sono dove si **cambia** qualcosa, la guida dove si
**legge**, e `Cmd+?` è il posto canonico dell'aiuto su macOS. Il README smette di essere un manuale
e torna vetrina: cosa fa, come si installa, e un link.

Fuori tema ma nello stesso giro, due decisioni piccole: il default della nomina passa a OpenRouter
(`deepseek/deepseek-v4-flash-latest`) **senza** ramo di compatibilità con l'endpoint OpenAI
precedente - la feature è opt-in e inerte senza chiave, un ramo per un default costa più di quanto
salva; e gli screenshot diventano ripetibili (`scripts/screenshots.sh`) invece che scattati a mano.

### Esito

`make check` verde (464 test). La guida copre le 23 aree in 9 sezioni; `README.it.md` e `README.md`
hanno le stesse otto sezioni, una per una.

Sugli screenshot, tre cose imparate a caro prezzo. La cattura **per regione** (`screencapture -R`)
prende un rettangolo di schermo, quindi il primo tentativo aveva dentro il Relay vero con i nomi dei
progetti clienti: si cattura per **window id**, filtrato sul pid del processo che lo script ha
lanciato (il nome non basta, c'è anche il Relay installato). La demo va **isolata**
(`RELAY_SOCKET`/`RELAY_LAYOUT` temporanei, tema via `NSArgumentDomain`) o tocca il layout vero. E
una demo con tre shell mute non è uno screenshot di niente: ora i pane a schermo recitano
`relay-cli simulate`, con scenari diversi e il titolo della finestra fissato al nome della chat -
che è anche il modo di tenere fuori dalle immagini il nome del Mac.

Coda del giro: i `UserDefaults` dei test creavano un plist vero in `~/Library/Preferences` per ogni
test e non lo cancellavano mai. Ne erano rimasti **3282**, 13 MB. Servono tre passi per toglierlo
(`removePersistentDomain` lascia un plist vuoto che cfprefsd riscrive, poi `removeSuite`, poi il
file), e un test che guarda il disco perché la prossima regressione non torni silenziosa.

## Cycle 19 - La nomina si regge da sola

### Il problema

Un check sulla nomina automatica, chiesto senza un sintomo in mano. La logica pura era coperta bene
(37 test fra `WorkspaceNamingTests` e `NamingTriggerPolicyTests`); il wiring - `NamingController`,
in `RelayApp`, senza un test target - non ne aveva **nessuno**. È lì che stavano i due difetti.

Il primo, vero: `regenerate` chiamava `store.markNameRegenerable` **prima** delle guardie di
configurazione e contesto. Un Regenerate che falliva - feature spenta, nessun contesto - lasciava
comunque il workspace a `.default`, e da lì la prima nomina automatica utile si prendeva un nome
scelto a mano. L'invariante dichiarata (`.user` intoccabile) saltava per un'azione che non era
nemmeno partita.

Il secondo, lo stesso sintomo già pagato in 0.11.1 per un'altra strada: `fire` usciva in silenzio
quando trovava una richiesta in volo, anche per l'azione manuale. Se il poll era partito un secondo
prima, il Regenerate non faceva e non diceva niente, e il nome che arrivava era quello del poll,
calcolato senza `avoiding`, cioè - a `temperature` 0 - identico a quello che c'era già.

### La domanda vera

"Secondo me la nomina potrebbe funzionare anche senza LLM, verifica." Verificato guardando cosa
arriva davvero al modello: tre righe scarne (`Directory: hub`, `Command: brew update`,
`Agent: claude`), perché `directoryHint` manda il **basename**, non il path. Su un input così povero
la trasformazione è quasi tutta meccanica.

| contesto | modello | regola |
| --- | --- | --- |
| cartella `yellow-hub` | Yellow Hub | Yellow Hub |
| Claude in `hub` | Hub | Hub |
| `brew update` | Homebrew Update | Brew Update |
| `npm run dev` in `acme-web` | Acme Web Dev | Acme Web |

Le prime due righe sono il grosso dei casi reali, e sono identiche. Il modello aggiunge espansione
di sigle e la fusione di cartella e comando in una frase: la coda della distribuzione. Nel frattempo
la chiave era un **requisito**, quindi la feature era inerte per chiunque non ne incollasse una: un
workspace nuovo restava "Workspace 3" per sempre, per non fare Title Case.

### La decisione

Due fonti, stessi trigger. `Core.WorkspaceNaming.localNames` deriva i candidati (cartella prima, poi
comando) e passa dalla **stessa** `sanitize` della risposta del modello, così i due percorsi non
producono nomi di qualità diversa. Senza chiave si nomina in locale, con la chiave scrive il
modello, e il locale fa da ripiego quando i tentativi si esauriscono - meglio "Yellow Hub" che
arrendersi in silenzio.

Il Regenerate senza modello prende il primo candidato diverso dal nome attuale; se non c'è
alternativa lo **dice** (`.noAlternative`) invece di riapplicare lo stesso nome e sembrare rotto. È
l'unico posto dove la mancanza del modello si sente davvero: una regola deterministica non ha un
secondo parere. `.notConfigured` torna a voler dire una cosa sola, "nomina spenta".

Aggiunto anche il feedback che mancava: il nome **pulsa** finché la richiesta è in volo
(`Workspace.isNaming`, volatile). Un'azione che parte, tace per un giro di rete e poi cambia una
riga della sidebar era indistinguibile da una che non fa niente - che è esattamente il bug di
0.11.1, ma dal lato dell'utente.

### Esito

`make check` verde, 483 test (+19: 11 sulla derivazione locale, 8 sullo store della nomina, che non
ne aveva). Tolto anche l'I/O inutile: la API key stava in un file riletto **a ogni tick** del poll,
e `armEligibilityObserver` lasciava dietro un osservatore vivo per ogni `reconfigure`/`regenerate`
(ora una generazione li estingue). `NamingController` ha superato il budget di file: poll ed
eleggibilità stanno in `NamingControllerPoll.swift`.

Coda del giro: la guida in-app diceva il falso - "a workspace named after its folder is left alone",
mentre un nome-cartella è `.default`, quindi eleggibile e sostituito al primo segnale. Riscritta la
sezione, `docs/GUIDE.md` rigenerato.

## Cycle 20 - Quello che vede chi arriva da fuori

### Il problema

L'app era distribuita via brew da sei versioni, ma tutto il perimetro che incontra chi non l'ha
scritta era sbagliato o assente. Il repo era pubblico **senza licenza**, cioè per default tutti i
diritti riservati: nessuno poteva legalmente forkarlo o ridistribuirlo. La MIT di SwiftTerm chiede
in più che copyright e permission notice viaggino con **ogni** distribuzione, e il dmg non li
conteneva. Nessuna security policy, quindi nessun canale privato per una segnalazione. E la doc
interna si era staccata dal codice in tre punti.

Nessuno di questi è un bug dell'app. Sono tutti bug del pacchetto attorno.

### Licenza e notice

MIT (`LICENSE`) con le notice delle dipendenze in `NOTICE`, e `make bundle` li copia in
`Relay.app/Contents/Resources`: averli nel repo non basta, l'obbligo è sulla distribuzione. About
dichiara la licenza. Aggiunte anche le stanze `binary` del cask su **entrambi** gli eseguibili
(`relay` e `relay-cli`), altrimenti i comandi che il README documenta non esistono in shell dopo un
`brew install`; vivono solo nel repo del tap, e `scripts/release.sh` tocca `version` e `sha256`,
quindi non le sovrascrive.

### Il README diceva sei cose non vere

Non stale in blocco: sei affermazioni puntuali, ognuna fuorviante per chi arriva da fuori. L'"Apri
comunque" di Gatekeeper serve solo all'installazione manuale del dmg (il cask toglie la quarantena);
la nomina non richiede un LLM da Cycle 19; `Cmd+?` e i tasti di controllo del terminale non sono
rimappabili; `--demo` è un no-op contro un'istanza già viva; la dashboard ha quattro corsie solo nel
layout kanban; `guide.md` mancava dall'elenco delle feature. Aggiunti i numeri misurati di memoria e
latenza e una sezione License. Le stesse due affermazioni sulla rimappabilità e sul costo stavano
anche nella guida in-app: sorgente e `docs/GUIDE.md` si sono mossi nello stesso commit, che è
esattamente il motivo per cui in Cycle 18 la guida è diventata una fonte sola.

### SECURITY.md

Dove segnalare (private reporting di GitHub o email, prima risposta attesa entro una settimana da un
progetto a un manutentore solo) e, soprattutto, **cosa tocca Relay sulla macchina**: gli hook
appesi a `~/.claude/settings.json` e marcati `RELAY_MANAGED_HOOK=1`, `~/.relay/` col socket che non
ha autenticazione oltre ai permessi del filesystem (un evento muove un badge e registra un resume
id, non esegue mai un comando), la API key della nomina `0600` e mai loggata, due sole chiamate di
rete entrambe opzionali, nessun parsing dell'output del terminale. La firma self-signed è dichiarata
lì invece di essere una sorpresa al primo avvio.

### La doc che si era staccata

- `STATE_SCHEMA.md` non aveva mai preso i gruppi (`groups`, `GroupSnapshot`, `groupID`), arrivati in
  Cycle 16. La convenzione dice "schema e migrazione nello stesso commit", ma non ha un test dietro,
  e infatti ha ceduto in silenzio.
- `ARCHITECTURE.md` aveva una data stale, le dipendenze sbagliate di `relay-cli`, una lista di
  decisioni chiusa che chiedeva ancora di scegliere il nome del prodotto, e la nomina descritta come
  solo-LLM.
- `CONVENTIONS.md` non citava `make tools` né `guide-md`, e dava `ShortcutRuntime` per tipo estratto
  quando è ancora un'extension di `AppController`.
- `docs/research/` ora dichiara quali due file sono vivi, i superati portano un banner in testa, e
  la nota di licensing dell'era GPL (quando l'engine candidato era libghostty) è marcata come non
  descrittiva di Relay. Via i path personali dagli spike.

### Esito

Pubblicata 0.16.1 (`v0.16.1`). Nell'app cambia una riga sola, quella della licenza in About: il
resto del giro è il pacchetto. La lezione da tenere è la prima del blocco sopra: una regola di
accoppiamento doc-codice senza un test che la verifichi si rompe senza fare rumore, e i gruppi
hanno passato quattro cicli fuori dallo schema documentato.

## Cycle 21 - Il benvenuto tagliato a metà

### Il problema

Le pagine dell'onboarding traboccavano il loro pannello: titolo mangiato in cima, footer con Skip e
Continue tagliato a metà dal `clipShape`. Cioè la prima schermata che vede chi installa l'app era
rotta, ed era rotta da quando le pagine hanno smesso di essere corte.

La causa è un frame fisso nudo (`maxWidth: 660, maxHeight: 440`) attorno a contenuto con altezza
intrinseca: i testi sono `fixedSize`, SwiftUI non li comprime, il VStack sfora il frame e il clip
taglia quello che avanza. Nessun test poteva vederlo: è geometria di layout, e le pagine crescono
un testo alla volta.

### Il fix, e perché non era una scelta fra overlay e finestra

Dashboard e guida hanno la stessa forma ma non il bug, perché fanno due cose che all'onboarding
mancavano: clampano il pannello allo spazio finestra (`panelSize(in:)`) e tengono il contenuto in
una `ScrollView`. L'onboarding ora fa entrambe, col footer fuori dallo scroll.

Valutata e scartata la strada "farne finestre vere come Settings": `makePanelWindow` produce
finestre **non ridimensionabili** a dimensione fissa, quindi lo stesso contenuto sforerebbe
identico. Il tipo di contenitore non c'entrava. Per la guida resta un argomento d'uso valido
(leggerla mentre si digita nel terminale), che è un'altra decisione.

Corollari, ora scritti in `docs/features/windows.md`: dentro uno scroll niente
`maxHeight: .infinity` sulle pagine e niente `Spacer` per centrare, perché il primo ridichiara
l'altezza sbagliata e il secondo collassa.

### Il taglio

Lo scroll deve restare una rete, non l'esperienza normale: otto scorciatoie invece di dieci (le due
tolte, Option-come-testo e clear, vivono già nella guida), cinque bullet invece di sei, copy più
corta sulle pagine dense. Le pagine più alte passano da ~400px a ~330 su 403 disponibili.

### Esito

Pubblicata 0.16.2. La lezione: un pannello a dimensione fissa che ospita contenuto redazionale è un
bug in attesa del paragrafo che lo supera, e il paragrafo arriva sempre.

## Cycle 22 - Lo stato che c'era e non arrivava mai

### Il problema

`AgentState.error` esisteva dal primo giorno del runtime: cablato nel badge (pallino rosso), nel
ring (bordo rosso pulsante), nella severità dell'aggregato workspace, nella corsia **Needs You**
della dashboard, nell'alert di chiusura tab. Tutto pronto. Solo che **nessuno lo produceva**: gli
hook installati si fermavano a `Stop`, e `Stop` scatta solo alla fine normale di un turno.

Un turno ucciso da un errore API - rate limit, overloaded, auth scaduta, billing, rete giù - non
emetteva nulla. La tab restava `running` per sempre, spinner acceso su una sessione ferma, badge
del workspace che diceva "sta lavorando", card in corsia Running. Zero notifiche, zero marker,
zero bump. Il caso d'uso per cui Relay esiste - la sessione che si pianta mentre guardi altrove -
era esattamente quello che non funzionava.

L'unico modo di vedere `error` era digitare a mano `relay-cli claude-hook error`. Nemmeno il
simulatore lo produceva.

### La fonte: `StopFailure`

Claude Code ha l'hook giusto: `StopFailure`, "when the turn ends due to an API error", col matcher
sul tipo (`rate_limit`, `overloaded`, `authentication_failed`, `billing_error`, `server_error`,
`max_output_tokens`, ...). Lo installiamo **senza matcher**, che equivale a `"*"`: tutti i tipi
collassano in `error`. La distinzione la legge l'utente dal terminale; la tab deve solo dire "qui
si è fermato, serve la tua mano". Un badge che distingue nove tipi di errore è un badge che non si
legge a colpo d'occhio, e a colpo d'occhio è l'unico modo in cui un badge viene letto.

`PostToolUseFailure` valutato e scartato: un tool che fallisce dentro un turno che prosegue non è
un errore di sessione, è rumore dentro il lavoro normale.

### `error` è l'unico stato che è anche marker

La distinzione stato/marker regge da sempre: `running`/`needs_input`/`error` sono stati (il badge
li legge da `agentState` finché lo stato cambia), `attention` è il marker post-completamento.
L'errore la rompe, e va bene così: senza marker non avrebbe **ring, bump in sidebar né notifica**,
cioè resterebbe un pallino rosso su una riga in fondo alla lista - il segnale più debole per
l'evento più urgente.

Quindi `error` alza `unseen` come un completamento. I due canali restano indipendenti: il
declassamento (flash o interazione) spegne il segnale forte ma **non** il badge rosso, che segue lo
stato finché non riprendi.

### Due guardie che erano sbagliate anche prima

- `attentionBorn = previousAttention == .none` misurava l'uscita da "niente", non il salto a
  `unseen`. Un errore (o un completamento) che atterra su un `pending` già declassato alzava il
  marker **senza bump e senza flash**, e restava `unseen` per sempre senza aver chiamato nessuno.
  Ora è `attentionRose = attention == .unseen && previous != .unseen`. Il buco c'era già sul
  completamento: l'errore l'ha solo reso visibile.
- `isInstalled` rispondeva "installato" se trovava **almeno un** hook nostro. Con `specs` che
  cresce, ogni installazione fatta da una versione precedente sarebbe rimasta verde senza mai
  ricevere il nuovo hook. Ora richiede tutti gli spec; il setup è idempotente, rifarlo è gratis.

### Le notifiche: perché non tutti gli stati

La richiesta era "come tutti i cambi di stato, mi aspetterei una notifica". Alla lettera non si
può: `running` lo generano `UserPromptSubmit` e **ogni** `PreToolUse`/`PostToolUse`, decine di
eventi per turno, tutti conseguenza del prompt appena mandato; `unknown` è `SessionEnd`, cioè
`/clear`, `exit`, logout. Sono azioni dell'utente, e notificarle seppellirebbe le altre.

La regola scritta è quindi: **notifichiamo ogni transizione che porta informazione che l'utente non
ha già**, cioè i tre stati che nascono da Claude e non da te - `needs_input`, `error`,
completamento non visto. Che dopo questo giro sono anche tutti gli stati "di Claude" esistenti.
Toggle per tipo in Settings (`notifyOnError`, default on).

### Esito

Pubblicata 0.17.0. Otto hook invece di sette, 492 test (+9), `make check` verde. Chi aggiorna vede
Settings > Agents segnalare gli hook come non installati: è voluto, un click di Setup aggiunge
`StopFailure`.

Verificato end-to-end su un'app isolata (socket e layout temporanei), mandando il payload
`StopFailure` con `relay-cli claude-hook error` e l'env letto dalla shell della tab: è lo stesso
comando che sta in `settings.json`. Il ciclo running -> error -> retry si vede negli screenshot:
ring rosso, bollino sulla tab, bollino sul workspace, poi tutto spento al retry.

Due cose restano non verificate. La **notifica macOS**, perché richiede il bundle e il guard
single-instance (bundle id) fa uscire ogni istanza mentre il Relay installato è aperto: coperta
solo dai test sul classificatore. E il fatto che Claude emetta davvero `StopFailure` con quel nome
e quel payload, che viene dalla doc di settembre 2026 e non da una sessione rotta davvero.

## Cycle 23 - Il gesto che non avevi chiesto

### Il problema

"Quando premo due volte sulla sezione delle tab in alto apre una tab, è una funzionalità voluta?"
Sì: `PaneTabBar` monta un `onTapGesture(count: 2)` sull'area vuota della strip, la convenzione di
Safari, Terminal e iTerm. Ma la domanda è già la risposta utile: un gesto che sorprende chi lo
scopre per sbaglio non è un difetto da togliere a tutti, è un default da rendere spegnibile.

### La scelta

Setting `newTabOnStripDoubleClick` (default on) in Settings > Terminal, accanto al blink del
cursore. Terminal e non Appearance: Appearance tiene tema e font (l'aspetto), Terminal i
comportamenti della superficie.

Il gesto **resta montato** anche col setting off, con la guardia dentro la closure. Staccare il
modificatore avrebbe cambiato l'identità della view a ogni toggle, e col setting off il secondo
click cade comunque su un focus già dato dal primo: non si perde niente.

`SettingsBlocks.fixedBlocks` era a 55 righe con il blocco nuovo, oltre il budget di 50: spezzata in
`chromeBlocks` (aspetto + terminale) e `agentBlocks` (agenti, notifiche, scorciatoie).

### Doc-pass dello stesso giro

- `ROADMAP.md` era diventata un archivio (666 righe, venti sezioni "Fatto" che ripetevano CYCLES).
  Potata a 77: dove siamo, il prossimo giro a scelta fra tre, il piano multi-agente, cosa c'è più
  avanti. La storia sta in questo file, che è il suo posto.
- `CYCLES.md` ha ruotato: i cicli 0-8 in `cycles-archive/CYCLES-0-8.md`, numerazione intatta.
- Corretti due puntatori: le categorie del pannello impostazioni in `ARCHITECTURE.md` (mancavano
  Updates e Shortcuts) e la "storia" dei gruppi, che indicava ROADMAP invece di questo file.

### Esito

493 test (+1), `make check` verde. Pubblicata 0.18.0.

## Cycle 24 - Il nome che apparteneva a qualcun altro

### Il problema

Il cask del tap si chiamava `relay`, e un token non qualificato Homebrew lo risolve sul core prima
che sul tap di terze parti. Ma `homebrew/cask` ha già un `relay` suo (`msllrs/relay`, un'altra app),
quindi `brew upgrade --cask relay` non aggiornava Relay: sostituiva Relay.app con quell'altra.

L'installazione qualificata (`essedev/relay/relay`) funzionava, il che è il motivo per cui il
problema è rimasto invisibile fino a un aggiornamento: l'install si scrive col tap davanti, l'upgrade
no. E il comando di upgrade era pubblicato ovunque - i due README, la pill di aggiornamento in
sidebar, l'output di `make release` - tutti col token nudo.

### La scelta

Token `relay-terminal`: un nome non collidibile vale più di un nome corto, e il nome corto non era
disponibile comunque. Cambiato in un colpo solo `CASK_PATH` in `scripts/release.sh`,
`UpdateController.upgradeCommand` (che è la stringa che l'utente copia o esegue dalla pill), i due
README, `ARCHITECTURE.md` e `ROADMAP.md`. Il binario in shell resta `relay`: il token del cask e il
nome dell'eseguibile sono cose diverse, e il secondo non collide con niente.

Il rename non è tutto nel repo. `update_tap` clona il tap e fallisce se `$CASK_PATH` non esiste, per
scelta (un cask mancante è un bootstrap rotto, non una cosa da creare al volo): finché il `.rb` non
è rinominato **nel repo del tap**, la prossima `make release` esce senza pubblicare. E chi ha già
installato col token vecchio non migra da solo: va disinstallato col token qualificato e
reinstallato con quello nuovo.

### Esito

Nessun test tocca il token: è una stringa di distribuzione, e la verità sta nel tap. Registrato in
`docs/features/distribution.md` come vincolo della routine di release, non come nota storica.

## Cycle 25 - Codex parla la stessa lingua

### La scelta

Codex entra in Relay tramite i suoi hook nativi, non tramite parsing del terminale e non obbligando
la TUI a passare da un client App Server gestito. Il core era già multi-agente; il secondo backend
ha portato l'estrazione concreta di `JSONHookInstaller`, condiviso fra `~/.claude/settings.json` e
`~/.codex/hooks.json`, lasciando mapper e comandi CLI separati dove i payload differiscono.

`relay-cli hooks setup|status|uninstall` accetta `claude`, `codex` o `all`; senza argomento resta
compatibile con Claude. Settings e onboarding mostrano entrambi gli agenti, le notifiche usano il
nome dell'agente e il resume sceglie `claude --resume` o `codex resume`.

### Il confine reale

Codex espone start, prompt, tool, permessi, stop, interrupt e fine sessione, ma non un hook
equivalente a `StopFailure`. Relay non trasforma testo terminale in stato: gli errori API Codex
restano quindi visibili nella TUI ma non accendono il badge rosso. `Interrupt` torna `idle` con
`resetsAttention`, così non viene scambiato per un completamento. Gli hook utente Codex richiedono
inoltre una revisione con `/hooks` dopo l'installazione e quando cambiano le definizioni.

### Verifica per la 0.19.0

`make check` verde: 502 test, incluso il mapping Codex, l'installer e il comando di resume.
Setup/status/uninstall del CLI verificati su file temporanei. Allineati README inglese/italiano,
guida generata, onboarding (setup, attenzione e resume), Settings e documenti di comportamento.
La verifica automatica non sostituisce una sessione Codex interattiva con hook autorizzati: il
trust dell'utente e le notifiche macOS dal bundle non sono stati provati end-to-end dal vivo.
