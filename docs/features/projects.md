# Progetti aperti e chiusi

Un workspace è un **progetto**: una cartella con le sue tab, il suo gruppo, le sue sessioni. Può
essere **aperto** (terminali vivi, in sidebar) o **chiuso** (nessun processo, nel catalogo). Il resto
della guida sta in `../../CLAUDE.md`.

## Perché

Con decine di progetti la sidebar diventava una lista di segnalibri: chiudere un workspace voleva
dire perderne nome, cartella, gruppo e sessioni da riprendere, quindi restava tutto aperto. Una
sessione agente costa ~200 MB e ~9 processi (`docs/research/PERF.md`) e il cap LRU per scelta non la
tocca: la memoria era tutta lì. Chiudere deve essere il gesto **normale** e sicuro, non una perdita.

## Modello

Nessuna entità nuova: `Workspace.closed` (sul disco è il vecchio campo `archived`, vedi
`WorkspaceSnapshot.CodingKeys`), quindi un layout di prima si legge senza migrazione e gli
archiviati di prima diventano progetti chiusi.

- **Chiudere** (`WorkspaceStore.setClosed(id, true)`): marca tutte le tab con il marker della
  disattivazione (`deactivate`), spegne i marker di attenzione, de-pinna, e ritorna gli id delle
  tab. Il chiamante (`AppController.requestCloseProject`) butta le surface **dopo**: è l'ordine
  della disattivazione (`session-deactivation.md`), senza il quale il `SessionEnd` dell'agente
  che muore azzererebbe il binding. Con un comando in foreground chiede conferma.
- **Il gruppo resta.** Un chiuso è ancora membro (`groupID` intatto, anche al restore): la card
  mostra solo i membri aperti (`members(of:)`, `sidebarItems`) e torna quando ne riapri uno.
  `pruneEmptyGroups` conta anche i chiusi, quindi un gruppo coi membri tutti chiusi esiste.
- **Riaprire** (`openProject`): toglie il flag, apre la card del gruppo, seleziona. Le surface
  rinascono al primo focus e la barra di resume ripropone le sessioni, come dopo un riavvio: il
  resume resta deliberato (niente `autoResumeAgents` su una tab disattivata).
- **Si può chiudere l'ultimo aperto.** La finestra resta senza selezione e mostra Home
  (`RelayWindow.page`). Vale anche per `closeWorkspace`, il restore e il rimpatrio di una finestra:
  la selezione punta solo a un aperto, mai a un chiuso.
- **Rimuovere** (`Remove Project`, `closeWorkspace`) resta il gesto distruttivo: il progetto esce
  da Relay con le sue sessioni.

## Pagina della finestra

`RelayWindow.page` (`.workspace`, `.home`, `.projects`, volatile) dice cosa mostra il right pane.
Le pagine coprono i terminali senza smontarli, quindi:

- per gli eventi agente una tab sotto una pagina **non è in vista** (`applyAgentState`): un
  completamento resta `unseen` e la notifica parte;
- per la disattivazione e la LRU la surface resta **montata** (`isMounted`): c'è una view
  attaccata, buttarla lascerebbe un terminale morto al ritorno.

`selectWorkspace` riporta sempre a `.workspace`: scegliere un progetto è andarci. Le pagine le monta
`RightPaneController+Pages` (un solo `NSHostingView` sopra tutto il right pane, `WindowPageView`
sceglie quale); Esc torna ai terminali.

- **Home** (`Cmd+D`, l'azione rimappabile `toggleDashboard` col vecchio rawValue per non perdere le
  combo salvate): triage dei soli progetti aperti, logica pura in `Panels/HomeModel`. Il titolo dice
  la situazione; ogni sessione che ti aspetta porta l'ultima riga dell'agente a schermo
  (`Core.TerminalPeek` sceglie la domanda o l'errore fra le righe di `screenLines()`, solo da una
  surface viva: non se ne crea una per leggerla). "Quiet for a week" propone di chiudere gli aperti
  fermi da 7 giorni, mai uno con un agente vivo o di cui non si sa niente.
- **Projects** (`⇧⌘P`): il catalogo per gruppo, aperti prima e poi il più recente
  (`Panels/ProjectsModel`), filtro per nome o cartella. Una griglia di card adattiva (minimo 280
  punti): la larghezza diventa più progetti a vista, non righe più lunghe.
- **Layout di Home**: sopra 860 punti utili va su due colonne, la coda di ciò che ti aspetta a
  sinistra e una colonna fissa di 320 (Working, Quiet, Recently closed) a destra; sotto, una colonna.
- **Palette** (`⌘P`, azione `goToProject`): overlay full-window (`FullOverlayPresenter`, slot
  `.palette`) per andare a un progetto per nome o cartella; un chiuso si riapre. Ordine in
  `Panels/PaletteModel`: aperti prima, poi la corrispondenza migliore, poi il più recente. Mentre è
  su il monitor si fa da parte, salvo `⌘P` che la richiude.
- **`Workspace.lastActiveAt`** (persistito, additivo): ultimo evento agente o ultima volta che ci sei
  entrato. Senza, dopo un riavvio ogni progetto sembrerebbe senza storia.

## Invarianti e trappole

- Mai selezionare un chiuso: una finestra che lo mostra creerebbe le surface e farebbe ripartire le
  shell di un progetto che risulta chiuso. Dalla sidebar un click su un chiuso è `openProject`.
- `setClosed` marca, non uccide: chi chiude deve buttare le surface ritornate. Chiudere dallo store
  senza passare dal composition root lascia processi vivi con la tab marcata.
- Un progetto chiuso **ignora gli eventi agente** (`applyAgentState`): sono gli ultimi di un
  agente ucciso alla chiusura, e applicarli accenderebbe un'attenzione su un progetto messo via.
- La chiave su disco resta `archived`: non rinominarla, o un binario precedente leggerebbe tutti i
  chiusi come aperti.
