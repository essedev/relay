# Cycles

Questo file traccia i cicli di lavoro e le decisioni prese durante l'analisi del terminale
agent-aware.

I cicli 0-8 (analisi engine, V0, agent runtime, primo giro UI/UX) sono in
`cycles-archive/CYCLES-0-8.md` e i cicli 9-11 (persistence, LRU, resume, bundle con notifiche,
distribuzione) in `cycles-archive/CYCLES-9-11.md`: qui restano gli ultimi ~15, numerazione intatta.

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

## Cycle 26 - Quello che restava acceso

### Il problema, misurato

Relay acceso da cinque giorni su una macchina di lavoro vera: **51 tab nel layout, 132 shell figlie
dirette** (2 zombie), 125 fd `/dev/ptmx`, 561 processi nell'albero, 33 sessioni `claude` vive per
6,1 GB di RSS. Almeno 81 di quelle shell erano residui di tab che non esistevano più.

Due problemi diversi nello stesso numero: una **perdita** (chiudere non rilasciava niente) e un
**costo legittimo** (le sessioni agente vive, che nessuna politica poteva toccare). Numeri, metodo e
riproduzione in `docs/research/PERF.md`; la riproduzione su istanza isolata mostra la crescita
lineare ed esatta: +10 tab aperte e chiuse = +10 shell, +10 ptmx, zero rilasciati.

### Il teardown non terminava niente

`LocalProcess.terminate()` di SwiftTerm fa `io.close()` senza `.stop`: la read pendente sul
descrittore primario della pty non completa mai (nessun EOF finché un figlio tiene aperto l'altro
capo), il cleanup handler non gira, il descrittore resta aperto e la pty non fa hangup. Il SIGTERM
che manda alla sola shell una zsh interattiva lo ignora. Chiudere una tab, un pane o un workspace
lasciava quindi vivi shell, agente e albero MCP finché Relay non moriva - e la conferma di chiusura
che prometteva "will be terminated" era falsa.

Il teardown ora lo fa Relay (`TerminalEngine.PtySessionTeardown`): SIGHUP al process group in
foreground **e** a quello della shell, poi escalation a SIGTERM e SIGKILL, poi `waitpid` (senza,
ogni shell morta restava zombie: `terminate()` cancella il monitor che l'avrebbe raccolta). I target
portano l'istante di avvio del loro leader e l'escalation salta quelli che non corrispondono più: lo
spazio dei pid gira in mezz'ora su una macchina al lavoro, e un segnale differito indirizzato al solo
pgid può finire sul gruppo di qualcun altro.

Con il fix è stata scritta l'invariante che mancava, in `ARCHITECTURE.md`: **una tab possiede la
sessione POSIX della sua pty**. È lei a dire cosa significa "terminare una tab" e perché un processo
che si è staccato apposta (`setsid`, `nohup` che abbandona la sessione) resta fuori dal perimetro;
senza, il confine del kill sarebbe arbitrario. Le affermazioni nei documenti c'erano già: era il
codice a non onorarle.

I test guidano **pty vere** (`PtySessionTeardownTests`) e verificano fd, processi e zombie a zero:
`FakeEngine` non passa mai di lì, ed è il buco che aveva lasciato passare il leak. Resta aperta la
patch upstream a SwiftTerm (`close(flags: .stop)` + reaping): quando fosse mergiata, di questo
resterebbe utile solo l'escalation.

### Disattivare una sessione tenendo la via del ritorno

Una surface idle costa 0,3-0,5 MB, una sessione agente ~200 MB e ~9 processi contando i server MCP.
Il cap LRU non sfratta mai una tab con processi vivi, per scelta deliberata (Cycle 9 e 15): con
decine di sessioni la memoria è tutta lì e il cap non la raggiunge. **Estendere il cap è la risposta
sbagliata**: è tarato sull'unità di misura delle surface, e sfrattare una sessione in silenzio è un
atto diverso dallo sfrattare un renderer.

`Workspace > Deactivate Sessions` (menu bar e contestuale della riga in sidebar, con una conferma
che conta cosa si spegne e cosa resta fuori) e `Deactivate Session` sulla pill della singola tab
uccidono la sessione e **tengono il `ResumeBinding`**: la tab resta dov'è, e riaprendola la
`ResumeBar` la rimette in piedi esattamente come dopo un riavvio.

Due cose la reggono, e sono entrambe questioni di ordine e di identità:

- **prima si marca, poi si butta la surface.** Uccidere l'agente fa scattare il suo `SessionEnd`,
  che Relay mappa su `unknown`, e su una tab normale `unknown` azzera il `resume`: a ordine invertito
  l'evento troverebbe la tab ancora normale e butterebbe via proprio il binding che serve;
- **il marker decade solo per un `sessionId` diverso** da quello del binding. Dopo il kill continuano
  ad arrivare gli ultimi eventi della sessione morente, e uno `Stop` in ritardo rimetterebbe la tab
  in piedi da sola. Una ripresa dalla barra passa dallo stesso id, e lì è la UI a togliere il marker.

Una tab disattivata **non** si auto-riprende: `autoResumeAgents` esiste per il riavvio, che è
involontario, mentre una disattivazione è voluta; senza la guardia, aprire una tab solo per leggerla
riaccenderebbe l'agente appena spento e il risparmio evaporerebbe durante il triage. Le esclusioni
danno il motivo e non un bool (`Tab.deactivationBlock(isOnScreen:)`), perché la conferma lo mostra:
"3 tab su 7" senza il perché sarebbe una scommessa su un'azione distruttiva. Restano fuori le tab a
schermo, quelle con l'agente `running` e quelle senza sessione; l'attenzione fresca **non** esclude,
che è il caso "me ne occupo dopo". `deactivated` sta nel `TabSnapshot` con decode tollerante, o al
primo focus dopo un riavvio l'auto-resume rimetterebbe in piedi proprio le sessioni spente.

Verifica contro sessioni Claude Code reali: un workspace di tre tab passa da 24 processi a 8, con
una tab lasciata viva perché a schermo, e tutti e tre i binding sopravvivono. Dettagli e trappole in
`docs/features/session-deactivation.md`.

### Gli hook parlavano sempre con lo stesso Relay

La shell di una surface non eredita l'ambiente dell'app: l'engine ne costruisce uno minimo, quindi
tutto ciò che serve all'hook va iniettato. `RELAY_SOCKET` non lo era, e un'istanza avviata con un
socket suo (una run di sviluppo, `scripts/screenshots.sh`) faceva riportare i suoi agenti al Relay
di tutti i giorni: le sue tab non ricevevano mai uno stato, e quello vero riceveva eventi di tab che
non ha. `SurfaceRegistry` riceve ora il path dal composition root - non può leggerlo da sé, perché
non dipende da `AgentRuntime`.

### Scartato: salvare il transcript al teardown

Sembrava il passo abilitante della disattivazione (spegnere senza perdere il verbale), ed è stato
tolto dal piano. La conversazione è già persistita due volte fuori da Relay: il resume la rimostra e
il record completo sta nei file di sessione dell'agente. Le tab senza agente perdono già lo
scrollback a ogni sfratto LRU, quindi la disattivazione non introduce una perdita nuova. In più
scrivere il buffer di un terminale su disco metterebbe a riposo token, dump di env e URL con
credenziali: è una decisione di sicurezza, e qui non la ripaga niente. Del piano resta solo il
vincolo che leggere una tab disattivata non deve riaccenderla, che è il marker.

### Contorno

- `adoptTab` rimosso: aggiunto col rework degli split cmux e mai chiamato, né dall'app né dai test.
- Gli observer del titolo di finestra e della chrome spostati da `AppController` ad
  `AppControllerWindows` (guardano lo store per ri-titolare e ridipingere ogni finestra, che è di
  quell'area; il composition root era al limite di dimensione del body).
- `PaneTabItem` estratto da `PaneTabBar`, stesso limite.
- Guida e README: la disattivazione, e il resume che arriva su un prompt che sta già leggendo stdin
  (il primo carattere diventa la risposta e il resto della riga parte troncato - l'aggiornamento di
  oh-my-zsh è solo l'esempio comune, scritto partendo dal sintomo).

### Doc-pass dello stesso giro

- `CYCLES.md` ha ruotato: i cicli 9-11 in `cycles-archive/CYCLES-9-11.md`, numerazione intatta. Le
  loro decisioni vincolanti erano già assorbite nei documenti di area.
- `ROADMAP.md` potata delle due sezioni chiuse da questo ciclo: restano gli avanzi reali, la patch
  upstream a SwiftTerm e l'automatismo della disattivazione.
- `STATE_SCHEMA.md` allineato: `deactivated` mancava dal `TabSnapshot` e dalla tabella dei campi
  additivi.

### Esito

`make check` verde, 532 test (+30 sul ciclo precedente): teardown su pty vere, iniezione del socket
nell'env della surface, ordine e decadimento del marker di disattivazione. Non rilasciato: la
versione resta 0.19.0.
