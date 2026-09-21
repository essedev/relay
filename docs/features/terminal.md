# Terminale (SwiftTerm): gotcha e integrazioni

Cosa SwiftTerm non fa da solo, e come lo compensiamo. Il resto della guida sta in `../../CLAUDE.md`.

- Shift+Invio / kitty keyboard: la surface inietta `KITTY_WINDOW_ID=1` nell'env
  (`SwiftTermEngine.start`), che dichiara il supporto al kitty keyboard protocol (SwiftTerm lo
  implementa: query + encoding). Claude Code attiva il protocollo solo per terminali noti; **non**
  settare `TERM_PROGRAM` (lo prioritizza e maschererebbe il segnale, claude-code#27868). Cosi
  Shift+Invio/Ctrl+Invio arrivano distinti all'app, senza intercettare l'input nel path caldo.
- Cwd di `Cmd+T`: non fidarti dell'OSC 7 da solo. Conseguenza del gotcha sopra: `/etc/zshrc` carica
  l'integrazione da `/etc/zshrc_$TERM_PROGRAM`, e noi non settiamo `TERM_PROGRAM`, quindi **zsh in
  Relay non emette OSC 7** (la shell senza integrazione è il caso di default, non un caso limite); e
  quando arriva è comunque ferma all'ultimo prompt. La precedenza è **shell viva
  (`TerminalSurfaceHandle.currentDirectory()`, `proc_pidinfo`) -> ultimo OSC 7 noto
  (`Tab.currentDirectory`) -> root del workspace**, decisa dal puro `Core.CurrentDirectory` (testato)
  e applicata in `WorkspaceAreaController.currentDirectory(for:)`. Non invertirla: col valore
  memorizzato davanti, la lettura live non viene mai consultata (dopo il primo `Cmd+T` la tab ha
  sempre una cwd nota) e l'ereditarietà torna cieca ai `cd`. E non memoizzare il risultato su
  `Tab.currentDirectory`: quel campo è l'ultimo OSC 7 noto e alimenta anche titolo, sottotitolo e
  snapshot, che si congelerebbero alla cwd dell'ultimo `Cmd+T`.
- Selezione durante l'output: di suo SwiftTerm azzera la selezione a **ogni** feed
  (`feedPrepare`), quindi con uno spinner attivo (`railway login`, `npm install`) copiare era
  impossibile. `RelayTerminalView.dataReceived` sincronizza `allowMouseReporting` con lo stato
  reale del mouse tracking (`terminal.mouseMode != .off`, la guardia proposta in SwiftTerm#560):
  con mouse mode spento la selezione sopravvive all'output, con mouse mode attivo (es. Claude
  Code) resta dell'app come prima. Due guardie in più perché le coordinate della selezione sono
  assolute e SwiftTerm non le compensa: la selezione si azzera se lo scrollback **trimma**
  (`totalLinesTrimmed`) o al cambio di buffer primary/alternate (`bufferActivated`), altrimenti
  Cmd+C copierebbe righe mai evidenziate. Semantica bloccata da `SelectionPersistenceTests`
  (passano dal percorso pty vero, `dataReceived`): se un bump di SwiftTerm cambia le regole
  sotto, i test diventano rossi invece di rompersi in silenzio. Quando la #560 (o equivalente)
  verrà mergiata, il toggle diventa ridondante e cancellabile.
- Scroll fluido: SwiftTerm quantizza lo scroll (`event.deltaY` -> salti di 1/3/10/20+ righe,
  delta precisi del trackpad ignorati). `RelayTerminalView.handleSmoothScroll` converte
  `scrollingDeltaY` in righe (1:1 col gesto, momentum incluso) accumulando il residuo sub-riga
  (`PreciseScrollAccumulator`, puro e testato). Le righe diventano scroll dello scrollback oppure,
  con mouse reporting attivo (es. Claude Code), eventi rotella SGR verso l'app (`sendWheelReports`,
  un evento per riga di gesto). **Non si può fare override di `scrollWheel`**: in SwiftTerm è
  `public override`, non `open` - l'evento arriva via `SmoothScrollInterceptor` (local monitor
  `.scrollWheel` + hitTest, stesso pattern del monitor tastiera). Unico passthrough a SwiftTerm:
  alternate buffer senza reporting (less/vim senza mouse, frecce sintetiche - logica interna, non
  replicarla). Granularità resta la riga intera (il renderer disegna a offset di riga, `yDisp`
  Int): smoothness sub-riga richiederebbe un fork dell'engine.
- Find/Clear/Jump: `Cmd+F` (find bar flottante sul terminale), `Cmd+K` (clear = `ESC[3J` + Ctrl+L
  al pty), `Cmd+J` (`WorkspaceStore.focusNextAttention`, ciclico sull'ordine visivo). Sono **azioni
  rimappabili** (`ShortcutAction.find/findNext/findPrevious/clear/nextAttention`), quindi passano
  dallo **stesso local monitor** delle altre, non da keyEquivalent di menu; il monitor consuma
  l'evento anche col terminale in focus. Search/clear passano dal protocollo `TerminalSurfaceHandle`
  (niente tipi SwiftTerm fuori dall'engine).
- Ricerca (Cmd+F) - due metà **coerenti per opzioni ma con sorgenti diverse**: (1) **navigazione,
  contatore e match corrente** li fa il motore di SwiftTerm (`findNext`/`findPrevious`/
  `searchMatchSummary`), autorevole su **tutto** il buffer, col match corrente evidenziato dalla
  **selezione nativa** (colore selezione del tema); (2) **l'evidenziazione di tutti i match** la
  disegna Relay perché SwiftTerm **non espone le posizioni dei match** (`findAll` è internal). È una
  **subview** (`SearchHighlightOverlay`, in `RelayTerminalView+Search`), non un override di `draw`
  (SwiftTerm dichiara `draw` `public`, non `open`); legge la sola **viewport** (`getLine`), cerca col
  matcher puro `Core.TerminalSearchMatcher` (case/word/regex, testato) e mappa gli indici di
  carattere alle **colonne-cella** (celle wide comprese). Geometria allineata al `draw` nativo: view
  non flipped, righe ancorate a `bounds.maxY`, **cella esatta da `caretFrame.size`** (non
  `cellSizeInPixels`, arrotondato). Si riallinea su output (`dataReceived`), scroll (`scrolled`) e
  resize (`setFrameSize`) - questi tre override stanno nel **corpo** della classe, non in extension.
  **Limite noto**: `isWrapped` è internal in SwiftTerm, quindi l'overlay cerca riga fisica per riga
  (niente unione dei blocchi wrapped): un match esattamente a cavallo di un a-capo automatico non
  viene evidenziato (il contatore/navigazione, che vedono il wrap, lo trovano comunque). Cercare per
  riga fisica evita i falsi positivi da righe concatenate. **Scrollback 10k** (`changeHistorySize` in
  `SwiftTermSurface.start`, non 500 di default: la ricerca deve vedere lo storico di una sessione
  agente). **Robustezza streaming**: a ricerca attiva `allowMouseReporting` è forzato **spento**
  (`setSearchState` + `dataReceived`), così `feedPrepare` non azzera la selezione a ogni feed e la
  posizione da cui `findNext` riparte sopravvive all'output (senza, con un agente che streamma Invio
  tornava sempre al primo match). **Stato legato alla tab**: la find bar ricorda la tab su cui è
  aperta (`RightPaneController.findTabID`) e opera su **quella** anche se il focus si sposta;
  `observeFindTarget` la chiude se la tab focused cambia (niente find bar orfana col contatore
  stantio). `Cmd+F` a barra aperta **rifocalizza** il campo (`FindModel.requestFocus` +
  `makeFirstResponder` sull'host se il first responder è altrove), non chiude (chiude Esc/x).
  **Focus all'apertura**: mai `makeFirstResponder(host)` sincrono dopo l'`addSubview` - la hosting
  view non ha ancora montato il TextField e fallisce in silenzio (tasti al terminale). Il pattern
  è quello di `FullOverlayPresenter`: deferral sul runloop successivo + guardia "non rubare se un
  discendente ha già il focus", più un retry del `@FocusState` nella view (`.task`, il set in
  `onAppear` può cadere). Colore evidenziazione dal giallo ANSI del tema (`ansiColor(3)`, coerente con
  badge/ring).
- **Teardown di una surface**: `SwiftTermSurface.teardown()` non si limita a `terminate()` di
  SwiftTerm, che non chiude niente. `LocalProcess.terminate()` fa `io.close()` senza `.stop`: la
  read pendente sul descrittore primario della pty non completa mai (nessun EOF finché un figlio
  tiene aperto l'altro capo), il cleanup handler non gira, il descrittore resta aperto e la pty non
  fa hangup; il SIGTERM che manda alla sola shell una zsh interattiva lo ignora. Il teardown vero lo
  fa `PtySessionTeardown`: SIGHUP al process group in foreground e a quello della shell, poi
  escalation a SIGTERM e SIGKILL, poi `waitpid` (senza, ogni shell morta resta zombie: `terminate()`
  cancella il monitor che l'avrebbe raccolta). I target portano l'istante di avvio del loro leader e
  l'escalation salta quelli che non corrispondono più: lo spazio pid gira in mezz'ora, e un segnale
  differito indirizzato al solo pgid può finire sul gruppo di qualcun altro. Se un giorno SwiftTerm
  accetta la patch upstream (`close(flags: .stop)` + reaping), di questo resta utile solo
  l'escalation. Misure in `docs/research/PERF.md`, test su pty vere in
  `PtySessionTeardownTests`.
- Cap LRU surface: `SurfaceRegistry.enforceLRU` è un **soft cap**. Sfratta le meno recenti **solo se
  idle** (`hasRunningChildren == false`: shell senza figli, copre foreground/background/agente) e
  non protette: mai la visibile, le tab del workspace attivo, le tab con attenzione fresca
  (`needs_input`/`error`/`unseen`) o quelle usate negli ultimi ~30 minuti. Eviction = teardown
  SwiftTerm (scrollback perso, shell ricreata alla cwd al re-focus). Cap in
  `WorkspaceAreaController` (12, knob `RELAY_SURFACE_CAP`). Se cambi il criterio, tienilo
  conservativo: meglio sforare il cap che resettare contesto utile o uccidere un processo.
