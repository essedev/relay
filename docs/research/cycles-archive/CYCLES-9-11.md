# Cycles 9-11 (archivio)

Il giro che porta dall'app dogfood-abile alla prima distribuzione: persistence del layout, cap LRU
delle surface, resume assistito, bundle `.app` con notifiche, temi e font, attention ring,
scorciatoie rimappabili e tap Homebrew. Spostati qui dalla rotazione di `../CYCLES.md` (che tiene
gli ultimi ~15). Numerazione intatta: `Cycle 9` resta `Cycle 9`.

Le decisioni ancora vincolanti che nascono qui non vivono solo in questo storico: cap LRU e kitty
keyboard in `docs/features/terminal.md`, ring e mark-read per interazione in
`docs/features/attention.md`, il monitor unico delle scorciatoie in `docs/features/keyboard.md`,
tap, firma e quarantena in `docs/features/distribution.md`, snapshot e guardie in
`docs/features/persistence.md`.

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

