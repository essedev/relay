# Workspace, sidebar e ordinamento

La lista dei workspace: ordine, nascita, archivio, drag, chiusura. Il resto della guida sta in `../../CLAUDE.md`.

- Toggle sidebar: è un overlay a livello finestra (`RootOverlayController`), **non** un
  `NSTitlebarAccessoryViewController` - quello non viene renderizzato con `titleVisibility = .hidden`
  su macOS 26. L'overlay insegue il bordo della sidebar via `splitViewDidResizeSubviews`.
- Sidebar: `NSSplitViewItem(viewController:)` normale, non `sidebarWithViewController:` (macOS 26 lo
  stila come pannello glass flottante). Lo `NSScroller` interno di SwiftTerm è nascosto a mano.
- Sidebar width: `AppSettings.sidebarWidth` (UserDefaults, default 250, clamp 200-340), non nel
  `LayoutSnapshot`. `MainSplitViewController` la applica alla prima passata di layout (una volta) e
  la salva sul resize (`splitViewDidResizeSubviews`, solo quando espansa).
- Lista workspace: `ScrollView` + `LazyVStack` custom, **non** `List`. La `List` disegna un highlight
  full-size di sistema sotto la riga bersaglio del menu contestuale (fuori dal tema flat). Con la
  VStack gestiamo noi selezione/hover/menu; il riordino è drag & drop (vedi gotcha "Riordino drag
  & drop" sotto), non `onMove`. La sidebar itera `store.orderedWorkspaces` (solo i pinned salgono in
  testa, il resto è l'ordine **canonico** di `store.workspaces`: niente float derivato). L'ordine
  canonico è quello vero e persistente, mutato dal drag **e** dal bump di attività
  (`bumpWorkspaceToTop`); `orderedWorkspaces` è display-only (proietta i pinned). Rename inline del
  workspace dal menu contestuale (`WorkspaceStore.renameWorkspace`).
- **Dove nasce una cosa nuova** (`WorkspaceStore+Ordering`): accanto a quella su cui lavori, non in
  fondo. Una tab entra nel pane focused **subito dopo la sua tab selezionata**
  (`Workspace.insertTab`, che passa l'indice a `SplitPane.insert`; `tabs` resta il sacco degli
  oggetti, l'ordine visivo è del pane). Un workspace entra **subito dopo il selezionato della sua
  finestra** (`insertionAnchor`, usata da `createWorkspace` **e** da `moveTabToNewWorkspace`, che si
  ancora al workspace d'origine) e ne **eredita il `groupID`**: creare dentro una card crea dentro
  quella card, uscirne è un drag come entrarci. Se la card è **chiusa**, `createWorkspace` la apre
  (non passa da `reveal`, che lo farebbe: senza, il selezionato sarebbe una riga invisibile). L'ancora è la selezione della **finestra di
  destinazione**, non della key (`createWorkspace(in:)`). Due sole eccezioni: se il selezionato è
  **archiviato** si torna in fondo (sta fuori da `orderedWorkspaces`: ancorarcisi darebbe una
  posizione che nella lista non esiste), e il pin **non** si eredita (il nuovo apre il segmento non
  pinned, la riga più vicina possibile a quella da cui è nato). Creazioni in sequenza conservano
  l'ordine di creazione, perché ognuna diventa l'ancora della successiva. Il workspace transitorio
  di `newWindow` eredita il gruppo per un istante e lo perde subito nella stessa mutazione
  (`leaveGroupOnWindowChange` + `pruneEmptyGroups`): un membro in un'altra finestra farebbe
  comparire la card in due sidebar.
- Archive: i workspace archiviati (`Workspace.archived`, persistito, additivo) escono da
  `orderedWorkspaces` e vivono in una sezione collassabile ancorata **in fondo** alla sidebar
  (`archiveSection`, header **sempre presente** anche a zero archiviati = drop zone e affordance
  permanente; il conteggio accanto a "Archive" compare solo se > 0; aperta e vuota mostra un empty
  state discreto "No archived workspaces"; lista archiviati con tetto ~metà sidebar,
  poi scroll interno; espansa/collassata in `AppSettings.archiveExpanded`). L'altezza del contenuto
  si misura con **`onGeometryChange` sul contenuto dentro lo ScrollView, mai con una preference**:
  su macOS le preference non attraversano il confine dello `ScrollView` (bridge NSScrollView) - a
  `onPreferenceChange` fuori arrivava solo lo 0 iniziale e la lista restava alta 1px (freccia sì,
  contenuto no: il bug dell'archivio che "non si apriva"). La lista è un **`VStack`, non
  `LazyVStack`**: dentro lo `ScrollView` alto `min(archivedHeight, ...)` che parte da 1px, il lazy
  non realizzerebbe le righe e la misura resterebbe 0.
  L'header è ancorato, non nel flusso scrollabile, perché su macOS
  lo `ScrollView` non fa drag-scroll: sotto la piega non ci potresti trascinare sopra. `archived`
  è mutuamente esclusivo con `pinned` (archiviare de-pinna) e col bump (un archiviato esce da
  `orderedWorkspaces`, quindi l'attività non lo riporta in cima). `setArchived`/`toggleArchive`: non archivia l'ultimo visibile e sposta la selezione
  fuori dall'archiviato; un archiviato con attenzione fresca accende un pallino discreto
  sull'header (non un buco nero). Archivia/ripristina dal menu contestuale (`Archive`/`Unarchive`) o **trascinando** dentro/fuori
  la sezione.
- **Righe e slot della sidebar** (`SidebarLayout`): la sidebar è srotolata in un piano piatto di
  righe (cosa si vede) e **slot** (gli spazi fra le righe, `rows+1`), e ogni slot porta scritto **in
  quale contenitore** si rilascia (`.root(pinned:)`/`.group`/`.archive`). Deciso alla costruzione,
  **mai** da euristiche sui vicini al drop: "in fondo alla card" e "sotto la card" sono lo stesso
  pixel con due significati, e li separa la riga di coda della card (`groupTail`, che è insieme il
  padding inferiore e uno slot con un solo significato). Da chiusa la card non ha coda: il padding
  inferiore lo mette il contenitore (`GroupCard(collapsed:)`), altrimenti l'header resta appoggiato
  al bordo. `SidebarDrop` fa il solo lavoro posizionale (slot -> contenitore + ancora canonica) ed è
  puro e testato; una card si posa solo nella lista (`normalized` la riporta al più vicino slot di
  primo livello: niente card annidate né archiviate in blocco).
- **Drag della sidebar** (`SidebarReorder`, separato da `Reorderable` che resta per la strip dei
  pane): il gesto attraversa due `ScrollView`, quindi (1) **un solo coordinate space** a livello
  sidebar coi frame raccolti da `onGeometryChange` e **non** da un `PreferenceKey` (le preference
  non attraversano il bridge `NSScrollView`: dall'archivio non arriverebbero mai, stessa trappola
  della sezione alta 1px) e (2) la **riga in volo disegnata in overlay fuori dalle ScrollView**, non
  la riga vera con `.offset` (dentro verrebbe clippata al bordo e sparirebbe a metà gesto, proprio
  mentre esci dal contenitore). Per lo stesso motivo la lista principale non è più `LazyVStack`: una
  riga smontata non misura il frame, e il calcolo degli slot li vuole tutti.
- Riordino drag & drop (sidebar e strip dei pane): meccanismo in `Panels/Reorderable` (`reorderableRow` +
  `reorderableContainer` + `ReorderInsertionLine`). **Non** `onDrag`/`onDrop` di sistema (generano
  una preview con snap-back al rilascio): la riga *vera* si solleva con un `DragGesture` + `.offset`
  (semitrasparente, zIndex alto) seguendo il puntatore, una linea segnala l'inserimento, e al
  rilascio lo scambio parte in `withAnimation` mentre l'offset torna a zero (nessun salto).
  L'indice di inserimento viene dalla **geometria proiettata della riga in volo** (frame originale +
  traslazione), **non** dal puntatore grezzo: così la linea segue il corpo della riga ed è
  **indipendente dal punto di presa** (afferrarla in cima o in fondo dà lo stesso risultato; col
  puntatore la decisione sfasava di quanto eri lontano dal suo centro). *Quale* punto della riga si
  confronta coi centri dei vicini lo decide `ReorderProbe`: la **sidebar** usa il centro (righe
  tutte uguali, è la scelta più prevedibile), la **strip** il **bordo che avanza** nella direzione
  del gesto. Motivo: le tab vestono il loro titolo, quindi hanno larghezze molto diverse, e col
  centro la soglia di scambio è la distanza fra i due centri, cioè metà larghezza di **entrambe**
  (due tab da 200pt: 204pt di traslazione). Su titoli lunghi il puntatore finiva fuori dalla strip
  prima che scattasse, e la riga di inserimento non compariva mai - specie afferrando la tab dal
  bordo sinistro, dove la corsa residua è già poca. Col bordo la soglia è metà del **solo vicino**
  (105pt nello stesso esempio), quindi il puntatore non esce dalla strip per un riordino di una
  posizione. Numeri fissati da `ReorderableTests`. I frame
  di layout li raccoglie un `PreferenceKey` in un coordinate space nominato, misurato **dopo**
  l'`.offset` del drag (dentro `reorderableRow`, mai con un GeometryReader sotto l'offset):
  l'offset è un GeometryEffect e si propaga alla geometria dei discendenti anche nello space
  nominato - con la misura dentro, il frame della riga in volo seguiva il gesto, il centro
  proiettato raddoppiava la traslazione e la linea di inserimento derivava proporzionalmente alla
  distanza (il bug del drop impreciso). Lo stato del gesto (`ReorderDragState`) vive in un **`@GestureState`** con
  `resetTransaction` animata: si azzera da solo anche a gesto annullato (menu contestuale, perdita
  focus) - con `@State` manuale un drag interrotto lasciava la riga sollevata e rompeva i drag
  successivi. Store puro e posizionale: `WorkspaceStore.moveWorkspace(_:before:/after:)` e
  `moveTab(_:before:in:)` (inserisce prima/dopo il target, `nil` = in fondo). **Sidebar**: meccanica e resolver
  suoi (vedi i due gotcha sopra); il drag edita direttamente l'ordine canonico, attraversare il
  blocco pinned pinna/spinna, e l'ancora preferisce il vicino dello stesso contenitore ripiegando
  sul vicino grezzo. Durante il gesto l'ordine visivo è **congelato**
  (`frozenOrder`): senza, un evento agente che bumpa un workspace riordinerebbe le righe sotto il
  puntatore. **Strip dei pane**: nessun segmento, ordine unico, il riordino resta **dentro** la
  strip (`Workspace.moveTab` è no-op cross-pane: il drag di tab fra pane è lavoro futuro). Su
  macOS lo `ScrollView` non fa drag-scroll, quindi il `DragGesture` non confligge con lo scroll;
  niente pasteboard, niente drop incrociati.
- Chiusura tab/workspace: passa da `AppController.requestCloseTab/requestCloseWorkspace` (Cmd+W e le
  x dei pannelli), che chiedono conferma via `NSAlert` sheet se nel pty gira un comando in foreground
  (`TerminalSurfaceHandle.foregroundProcessName()` = `tcgetpgrp` vs `shellPid` + safe-list shell; solo
  foreground, i job in background non contano). Chiudere l'ultima tab chiude il workspace (cascade in
  `WorkspaceStore.closeTab`). Il messaggio (`closeInfo`) nomina Claude per **ogni** stato di
  sessione viva (running/needsInput/idle/error: il proc_name del binario claude è la versione,
  es. "2.1.200", inutilizzabile); solo `.unknown` mostra il nome grezzo del processo. Non usare
  `tab.resume` come criterio: persiste oltre il riavvio e dopo un restore nel pty può girare
  tutt'altro.
- Sposta tab in nuovo workspace ("Move to New Workspace", menu contestuale della tab, visibile
  solo con **>=2 tab**): `WorkspaceStore.moveTabToNewWorkspace` sposta lo **stesso** oggetto `Tab`
  (stesso `Tab.id`), così la surface legata per id resta **viva** - niente teardown del pty, il
  lavoro dentro la tab non si tocca. L'append del nuovo workspace e il `removeTab` dall'origine
  avvengono nella **stessa mutazione sincrona**: la tab è sempre presente in `store.workspaces` a
  ogni istante osservabile, quindi il reconcile delle surface (`retain` su tutti gli id, vedi
  TerminalHostUI) non la sfratta mai. Il nuovo workspace eredita la cwd della tab come `rootPath`,
  nasce `.default` (eleggibile alla nomina automatica: il nome è un placeholder), nasce **accanto
  al workspace d'origine e nel suo gruppo** (vedi "Dove nasce una cosa nuova") e diventa il
  selezionato con la tab spostata attiva. **No-op se la tab è l'unica del suo workspace**
  (svuoterebbe l'origine) o se l'id non esiste lì. Il nome placeholder ("Workspace N") lo assegna
  il composition root (`AppController.moveTabToNewWorkspace`), non lo store, come per `newWorkspace`.
- **Trascina una tab in un altro workspace** (dalla strip di un pane a una riga della sidebar):
  `TabDragSession` (Panels) + `WorkspaceStore.moveTab(_:from:to:)`. Come "Move to New Workspace"
  viaggia lo **stesso** oggetto `Tab` con inserimento prima della rimozione, quindi il pty non si
  tocca; la tab entra nel pane focused della destinazione **subito dopo la sua tab selezionata** e
  la destinazione viene rivelata (de-archiviata, card aperta). Spostare l'**ultima** tab è
  legittimo e chiude il workspace d'origine (cascade): qui, a differenza di "Move to New
  Workspace", non sarebbe un rename mascherato.
  **Perché serve un intermediario**: strip e sidebar sono due `NSHostingView` **sorelle**, quindi
  nessun coordinate space SwiftUI le attraversa e la riga sollevata con `.offset` verrebbe clippata
  al bordo della strip proprio mentre esci. La lingua comune sono le **coordinate finestra con
  origine in alto a sinistra**, prodotte da `WindowRectReader` (un `NSViewRepresentable`: `.global`
  di SwiftUI è relativo alla propria hosting view, e il punto è uscirne). Si convertono **due
  origini** (l'area delle tab e la sidebar), non il frame di ogni riga: i frame restano nello space
  della sidebar e la conversione avviene nel solo `target`.
  Il gesto resta **uno**: `Reorderable` ha un aggancio opzionale (`ReorderCrossDrag`) che la strip
  usa per pubblicare il puntatore; finché il puntatore è dentro la strip (`isOutside == false`)
  vale il riordino orizzontale di sempre, fuori si spegne la linea di inserimento, la riga vera
  torna al suo posto e a seguire il puntatore è il **fantasma** (`TabDragGhost`), montato dal
  composition root a livello finestra (`RootOverlayController.setDragGhost`, `hitTest` sempre
  `nil`: il gesto vivo è quello della strip sotto). Non si può promuovere un `DragGesture` SwiftUI
  già partito a `NSDraggingSession`: con la pasteboard servirebbero due meccaniche diverse nella
  stessa strip, decise all'inizio del gesto.
  **Costo sul gesto**, due trappole pagate: (1) le misure di geometria della strip stanno in una
  classe (`DragGeometryBox`), non in due `@State`, perché lo scroll orizzontale sposta il contenuto
  e quindi ne cambia il rettangolo in finestra a ogni frame - in uno `@State` avrebbe invalidato la
  strip per tutta la durata dello scroll; (2) `TabDragSession.target` è **stored**, non computed:
  da computed dipenderebbe da `location`, che cambia a ogni evento del mouse, e la sidebar (che lo
  legge per evidenziare la riga) si sarebbe ridisegnata a ogni pixel anche durante un riordino
  orizzontale che non la riguarda. `location` resta osservata ma il suo unico lettore è il
  fantasma, che esiste solo fuori dalla strip.
  Guardie contro i bersagli fantasma: il frame di ogni riga è **ritagliato al viewport** del suo
  ScrollView e scartato sotto metà altezza visibile (una riga scrollata via conserva il frame, che
  cadrebbe sull'area dell'archivio); `sidebarRect` fa da guardia esterna, quindi una sidebar
  collassata (larghezza ~0) non accetta niente; `pruneTargets` scarta le righe che il piano non
  mostra più. La struttura della sidebar è **congelata** anche durante questo drag, come per quello
  interno: un bump da attività non vista sposterebbe la riga bersaglio sotto le mani. Hit test e
  ciclo di vita della sessione sono puri e testati (`TabDropTargetTests`).
  **Limiti noti**: niente autoscroll della sidebar (un workspace fuori vista va raggiunto
  scrollando prima), i bersagli sono solo righe di workspace (non gli header di gruppo), e il drop
  non sceglie una posizione dentro la strip di destinazione (le sue tab non sono visibili).
