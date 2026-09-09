# Gruppi di workspace nella sidebar

Card colorate che raccolgono workspace affini, sul modello dei tab group di Brave/Chrome. Con
qualche decina di workspace la sidebar diventa un elenco indifferenziato: i gruppi le danno una
struttura che l'utente decide, senza toccare il modello di attenzione.

Riferimenti: modello dati in `docs/ARCHITECTURE.md` #Data-Model, ordine della sidebar in
#Chrome-E-Finestra, storia in `docs/research/CYCLES.md` (Cycle 16).

## Cosa fa

- **Card**: bordo e fondo tenue in una tinta presa dai colori ANSI del tema (sei slot), header a una
  riga con titolo, chevron, contatore e menu, membri rientrati dentro la card.
- **Collasso**: la card chiusa è alta come una riga normale e mostra **un solo numero** - quanti
  membri chiedono attenzione (nella tinta del gruppo) o, se nessuno, quanti membri ha (in grigio).
- **Pin del blocco**: il gruppo intero sale in testa alla sidebar, sopra le righe libere.
- **Comandi**: menu contestuale della riga (`New Group with This`, `Move to Group`,
  `Remove from Group`), header della card (`Rename Group`, `Collapse`, `Pin Group`, `Color`,
  `Ungroup`), menu bar Workspace (`New Group with This`/`Ungroup` con scorciatoia rimappabile
  `⌃⌘G`, `Remove from Group`), drag & drop.

## Modello

`WorkspaceGroup` porta **solo identità e aspetto** (nome, colore, collasso, pin). L'appartenenza
vive sul workspace (`Workspace.groupID`).

Non è un dettaglio: è la decisione che tiene semplice tutto il resto.

- **Nessun secondo ordinamento.** L'ordine vero resta l'unico array canonico `store.workspaces`. La
  posizione di una card è quella del suo primo membro, quindi non c'è una lista di gruppi da tenere
  in sync col riordino, col bump, col restore o col rimpatrio alla chiusura di una finestra.
- **Contiguità non necessaria alla correttezza.** Le operazioni compattano i membri (`compact`,
  `place`) perché drag e bump lavorino su un ordine che somiglia a quello a schermo, ma la
  proiezione `sidebarItems` raccoglie comunque **tutti** i membri alla posizione del primo: un file
  di layout toccato a mano che li sparpaglia produce una card sola, non righe orfane.
- **Un gruppo senza membri non esiste.** Uscita, archiviazione, cambio finestra o chiusura
  dell'ultimo membro lo cancellano (`pruneEmptyGroups`), come chiudere l'ultima tab chiude il
  workspace. Un `groupID` che punta a un gruppo inesistente degrada a riga libera.
- **Esclusività.** `pinned`, `archived` e `groupID` non convivono: entrare in una card azzera pin e
  archivio, archiviare o spostare in un'altra finestra tira fuori dalla card. Il pin del singolo
  membro sarebbe ambiguo (la card lo terrebbe comunque in mezzo agli altri), quindi `togglePin` è un
  no-op dentro un gruppo e la voce di menu sparisce.

Proiezioni: `sidebarItems(in:)` (righe libere + gruppi coi membri, pinned in testa) è l'unica fonte;
`orderedWorkspaces` ne è il flatten **logico** (include i membri di card chiuse: serve a `Cmd+J`,
agli eredi di selezione, al restore) e `navigableWorkspaces` il flatten **visibile** (esclude i
membri nascosti: `Cmd+1..9` e menu Go, perché una scorciatoia che seleziona una riga invisibile non
è una scorciatoia). `reveal` apre la card del workspace che rivela, come già de-archiviava.

## Ordine: chi si muove e chi no

Il modello "lista chat" resta, ma diventa **per contenitore** (`bumpWorkspaceToTop`):

- un membro con attività **non vista** sale in cima **alla sua card**; la card non si muove;
- un workspace libero sale in cima alla lista e si ancora al primo membro del primo elemento non
  pinnato: se quello è una card, la riga finisce **sopra** di lei;
- **la card sta dove la metti.** A spostarla sono solo il pin, un drag o l'essere scavalcata.

Stessa logica per **dove nasce** un workspace nuovo (`insertionAnchor`, in `WorkspaceStore+Ordering`):
subito dopo il selezionato della sua finestra, ereditandone il `groupID`. Creare mentre sei dentro
una card crea **dentro quella card**; per farlo nascere fuori si esce col drag, come ci si entra.
Vale anche per "Move to New Workspace", che si ancora al workspace d'origine.

Da qui il pin di gruppo: senza, la prima attività di una riga libera scavalcherebbe la card e da lì
in poi i gruppi affonderebbero per sempre. Il pin è il modo di dire "questa resta in alto".

## Righe e slot: come è risolto il drag

La sidebar viene srotolata in un piano piatto (`SidebarLayout.plan`): `rows` (cosa si vede e si
trascina) e `slots` (gli spazi *fra* le righe, `rows.count + 1`), dove **ogni slot porta scritto in
quale contenitore si rilascia** - `.root(pinned:)`, `.group(id)`, `.archive`.

Il contenitore è deciso alla costruzione, non da euristiche sui vicini al momento del drop, perché
c'è un confine che nessuna euristica può sciogliere: "in fondo alla card" e "sotto la card" sono lo
stesso pixel con due significati diversi. Lo separa una **riga di coda** (`groupTail`), che è al
tempo stesso il padding inferiore della card e uno slot con un significato solo: sopra di lei si
entra nel gruppo, sotto si è nella lista.

`SidebarDrop.resolve` fa poi il solo lavoro posizionale: dallo slot ricava il contenitore e l'ancora
canonica (`before`/`after` un workspace), preferendo il vicino dello stesso contenitore e
ripiegando sul vicino grezzo. Le righe che appartengono al trascinato sono escluse (per una card:
header, membri e coda), e un rilascio negli slot che già occupa è un no-op. Una card si può posare
solo nella lista: `normalized` riporta il suo slot al più vicino di primo livello, così non si
annida in un'altra card e non finisce in archivio. Tutto puro e testato in
`Tests/PanelsTests/SidebarDropTests.swift`.

Il chiamante (`SidebarView+Drop`) traduce: contenitore -> cambi di campo (`assignGroup`,
`setPinned`, `setArchived`, `setGroupPinned`), poi `moveWorkspace`/`moveGroup` per la posizione.

## Drag cross-container (e perché la meccanica è nuova)

`Reorderable` resta com'è per la strip dei pane, che è un contenitore unico dentro una sola
`ScrollView`. La sidebar ha bisogno di due cose che lì sarebbero peso morto, e vivono in
`SidebarReorder`:

1. **Un coordinate space solo**, a livello sidebar, coi frame raccolti da `onGeometryChange` e non
   da un `PreferenceKey`: su macOS le preference non attraversano il confine di una `ScrollView`
   (bridge `NSScrollView`), quindi i frame delle righe archiviate non arriverebbero mai al registro
   comune. È la stessa trappola che teneva la sezione Archive alta 1px.
2. **La riga in volo disegnata in overlay fuori dalle ScrollView**, invece della riga vera spostata
   con `.offset`: dentro la sua ScrollView verrebbe clippata al bordo e sparirebbe a metà gesto,
   proprio mentre esci dal contenitore. L'originale resta al suo posto, sbiadito.

Da qui arriva gratis il drag dentro/fuori l'**archivio**, che era in sospeso da M4.

Nota: la lista principale non usa più `LazyVStack`. Una riga smontata non misura il proprio frame, e
il calcolo degli slot ha bisogno del frame di tutte le righe, comprese quelle fuori vista.

## Persistence

Campi additivi, nessun bump di `LayoutSnapshot.currentVersion`: `groups: [GroupSnapshot]` e
`WorkspaceSnapshot.groupID`. Un layout salvato prima dei gruppi si ricarica con tutte righe libere;
un binario più vecchio ignora i campi e mostra i membri come righe normali, nell'ordine giusto (la
compat resta solo all'indietro, come per lo split v2). Al restore un `groupID` su un archiviato
viene lasciato cadere e i gruppi senza membri vengono potati.

## Limiti noti

- Il drag di una card **fra finestre** non c'è (le finestre partizionano i workspace e un membro che
  cambia finestra lascia il gruppo).
- Un gruppo non si archivia in blocco: si archiviano i membri, e la card muore con l'ultimo.
- Niente annidamento: le card non contengono card.

## Invarianti e trappole

- **Gruppi nella sidebar** (dettagli in `docs/features/workspace-groups.md`): card colorate attorno
  a dei workspace. **L'appartenenza vive sul workspace** (`Workspace.groupID`), il `WorkspaceGroup`
  porta solo l'aspetto (nome, colore ANSI del tema, collasso, pin del blocco): così non esiste una
  lista di membri che diverga dall'ordine canonico, la posizione della card è quella del suo primo
  membro e **un gruppo senza membri non esiste** (`pruneEmptyGroups` dopo ogni operazione che può
  svuotarlo: uscita, archiviazione, cambio finestra, chiusura). Non introdurre una lista di membri
  sul gruppo né un ordinamento separato dei gruppi: la contiguità dei membri è una comodità che
  `compact`/`place` mantengono, non un invariante da cui dipende la correttezza (`sidebarItems`
  raccoglie i membri sparsi in una card sola). `pinned`/`archived`/`groupID` sono mutuamente
  esclusivi: `togglePin` è **no-op** dentro una card (lì pinna il gruppo, `setGroupPinned`) e la
  voce di menu sparisce. Il **bump** è per contenitore (vedi `attention.md`): un membro sale
  in cima alla **sua card**, un libero sale in cima alla lista e finisce **sopra** la card; la card
  si muove solo con pin o drag - senza il pin di gruppo il primo bump di una riga libera la farebbe
  affondare per sempre. `Cmd+1..9` e il menu Go usano `navigableWorkspaces` (esclude i membri delle
  card **chiuse**: una scorciatoia su una riga invisibile non è una scorciatoia), mentre `Cmd+J`,
  gli eredi di selezione e il restore usano `orderedWorkspaces` (ordine logico, li include);
  `reveal` **apre** la card come già de-archiviava. Snapshot additivo (`groups` +
  `WorkspaceSnapshot.groupID`, nessun bump di versione).
