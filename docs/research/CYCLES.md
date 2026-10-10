# Cycles

Questo file traccia i cicli di lavoro e le decisioni prese durante l'analisi del terminale
agent-aware.

I cicli 0-8 (analisi engine, V0, agent runtime, primo giro UI/UX) sono in
`cycles-archive/CYCLES-0-8.md`, i cicli 9-11 (persistence, LRU, resume, bundle con notifiche,
distribuzione) in `cycles-archive/CYCLES-9-11.md`, i cicli 12-13 (riordino della sidebar e bump
reale) in `cycles-archive/CYCLES-12-13.md` e i cicli 14-15 (pulizia, CI deterministica, patch
0.7.x) in `cycles-archive/CYCLES-14-15.md`: qui restano gli ultimi ~15, numerazione intatta. Le
decisioni ancora vincolanti dei cicli archiviati stanno in `../DECISIONS.md`.

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

## Cycle 27 - La catena che perdeva in silenzio

### Il problema

Una notifica che non arriva non lascia traccia: nessun errore a schermo, nessuna riga rossa, solo
una tab che resta `running` e un utente che se ne accorge mezz'ora dopo. Il giro parte da qui e
percorre la catena intera - hook -> CLI -> socket -> receiver -> pump -> store -> reducer ->
preferenze -> `UNUserNotificationCenter` - cercando i punti dove un pezzo può sparire senza dirlo.
Ne sono usciti cinque, tutti dello stesso tipo: una perdita che il sistema non sa raccontare.

### Il log non diceva niente (e il runtime nemmeno)

`os_log` redige le stringhe interpolate per default: i tre log di errore del receiver stampavano
`<private>`, quindi l'unica traccia di un evento agente perso non conteneva alcuna informazione.
Un'istanza accesa da 5 giorni ne aveva 27, tutti indiagnosticabili. Ora l'errno si legge **prima**
di qualunque altra chiamata (un'interpolazione può sovrascriverlo) e si stampa in chiaro: non è un
dato dell'utente.

Stessa classe di bug un livello sopra, trovata verificando il fix con un `RELAY_SOCKET` lungo: il
catch che avvolge l'avvio del runtime logava `error.localizedDescription` interpolato, così un
runtime **mai partito** (path oltre `sun_path`, runtime dir non scrivibile) era indistinguibile da
un'app che semplicemente non riceve eventi. Il messaggio adesso dice perché.

### La raffica: 76 eventi persi su 100

Con decine di sessioni gli hook si connettono nello stesso istante. Il backlog del listener era 16
e la read source accettava **una** connessione per risveglio: la coda restava piena e la `connect`
del client veniva rifiutata. La CLI ingoia l'errore per contratto (un hook non deve mai rompere
l'agente), quindi l'evento spariva senza lasciare niente: una tab bloccata su "running", la sua
notifica mai consegnata. Misura prima del fix: **76 eventi persi su 100 connessioni simultanee**.

Tre cose insieme, e vanno tenute insieme: backlog al massimo che il kernel onora
(`kern.ipc.somaxconn`, 128), `accept` che **svuota tutta la coda** a ogni risveglio, e nel client un
retry breve (10 ms, 30 ms) sui soli errori transitori. `ENOENT` - Relay non è in esecuzione - non è
transitorio: lì non c'è niente da aspettare e ogni hook della macchina pagherebbe l'attesa per
nulla.

La trappola BSD costata di più: il loop di accept richiede un listener non bloccante, e su macOS
l'fd accettato **eredita** `O_NONBLOCK` mentre `drain` legge in modo bloccante. Ogni fd va
riportato a bloccante a mano, o la read torna `EAGAIN` ogni volta che i byte del client non sono
ancora arrivati - e l'evento si perde invece di essere atteso.

### Gli hook rimasti indietro

Gli hook si scrivono una volta, ma lo spec cresce con le versioni. `StopFailure` è arrivato nella
0.17.0 e il `settings.json` di chi aveva installato prima non l'ha mai ricevuto: per **18 giorni**
lo stato `error` non ha avuto alcuna fonte su una macchina dove tutto il resto funzionava - nessun
badge rosso, nessun bump, nessuna notifica. L'unico segnale era un booleano dentro un pannello di
Settings che nessuno apre.

`RelayHookState` distingue "mai installati" da "installati e rimasti indietro" e porta con sé gli
eventi mancanti, così `relay-cli hooks status` dice **quali**, non solo che qualcosa manca. Il drift
di Claude lo ripara l'app all'avvio: il setup è idempotente, fa il backup e l'utente ha già
acconsentito a quel path. **Codex no**, ed è una scelta: i suoi hook vanno ri-approvati con `/hooks`
a ogni cambio di definizione, e riscriverli in silenzio rischierebbe di spegnere anche quelli che
funzionano. Il suo drift resta segnalato, e proprio per questo anche il blocco in Settings ha
smesso di essere binario: "Out of date: missing ..." col bottone **Update**, perché per Codex
quello è l'unico posto dove il drift si vede, e "non installato" su una configurazione che
funziona per sei hook su otto manda a cercare nel posto sbagliato.

### Una notifica viva per tab

Ogni notifica usava un UUID nuovo come identifier, quindi una tab che andava in `needs_input`, poi
in errore, poi completava lasciava **tre** voci, e niente le rimuoveva mai. Il centro notifiche
cresceva con ogni transizione di ogni tab mai aperta, e cliccare un banner mezza giornata dopo
riportava in vista una conversazione già letta - o una tab che non esisteva più.

L'identifier è ora la tab (`relay.tab.<id>`): una tab **sostituisce** il proprio banner. Il
`threadIdentifier` è il workspace, così il centro raggruppa per progetto. Il pezzo che mancava è il
ritiro: `WorkspaceStore.onAttentionCleared` è il simmetrico di `onNotifiableTransition` - lo store
lo emette quando la tab non aspetta più niente (mark-read, dismiss, decadenza, `toggleUnread` che
spegne, chiusura della tab) e il composition root fa `removeDeliveredNotifications`. Una notifica
non deve sopravvivere alla cosa che l'ha generata.

### Il filtro che nessun test vedeva

L'ultimo filtro prima del banner - preferenze, soppressione della tab che stai guardando, titolo
per agente - viveva nel composition root, che **non ha un test target**: niente di tutto ciò era
coperto. `NotificationPolicy` prende i toggle come valori e risponde se consegnare; al
`NotificationCoordinator` resta `UNUserNotificationCenter`, cioè solo I/O. Il criterio per la
collocazione non è estetico: ciò che decide sta dove si può testare, e `RelayApp` non lo è.

Nel trasloco la guardia sulla tab in vista è passata da due kind a tutti e tre. Non è un cambio di
comportamento: il reducer non emette mai un completamento per una tab in vista, quindi la regola era
già quella - solo che dipendeva da quale chiamante la usava, e adesso non più.

### Il filo conduttore

Cinque fix, una sola forma: un pezzo della catena perde qualcosa e il sistema non ha modo di dirlo.
Il log redatto, la `connect` rifiutata che la CLI ingoia per contratto, l'hook mancante visibile
solo in un pannello, il banner che nessuno ritira, il filtro fuori da ogni test. Dove la perdita è
silenziosa per costruzione - un hook non può rompere l'agente - la difesa non è un errore in più:
è non perdere, e rendere leggibile la traccia di quando succede lo stesso.

### Doc-pass dello stesso giro

- `CYCLES.md` ha ruotato: i cicli 12-13 in `cycles-archive/CYCLES-12-13.md`, numerazione intatta.
  Le loro decisioni vincolanti erano già assorbite in `sidebar.md` e `attention.md`.
- `ARCHITECTURE.md` allineato in tre punti: la raffica nella Local Control API, il drift e la
  riparazione al boot nell'Hook Installer, `NotificationPolicy` e il ritiro per tab nelle notifiche
  macOS (il testo diceva ancora che il filtro vive nel composition root).
- README (en/it): il paragrafo sull'aggiornamento che aggiunge un hook prometteva un setup da
  rilanciare a mano, mentre per Claude ora è automatico; l'indice dei documenti di area aveva perso
  `session-deactivation.md`.
- `ROADMAP.md`: "Dove siamo" era ferma alla 0.19.0 con il lavoro del Cycle 26 dato per non
  rilasciato, mentre la 0.20.0 lo contiene.
- `STATE_SCHEMA.md`: l'incompletezza di un'installazione vecchia adesso ha un nome
  (`RelayHookState.drifted`), e il file citava ancora solo il booleano.

### Esito

`make check` verde, 549 test (+17 sul ciclo precedente): raffica di 100 connessioni simultanee senza
perdite, retry solo sui transitori, drift distinto da assente con gli eventi mancanti, ritiro della
notifica sui cinque modi in cui l'attenzione si spegne, e la policy di consegna coperta per intero.
Verifica sull'app vera, non solo unit: istanza isolata (socket e layout temporanei), 470 eventi su
470 consegnati a 10, 20, 40, 100 e 300 connessioni simultanee, zero `read failed`; contro
l'istanza viva pre-fix lo stesso test perdeva 8/10, 20/20 e 36/40. Il drift provato end to end:
`out of date, missing StopFailure` diventa `installed` dopo un boot, con
`claude hooks repaired, added: StopFailure` nel log.
Rilasciato nella 0.21.0.

## Cycle 28 - Il titolo della chat come segnale di nomina

### Il problema

Un agente lanciato dalla home non aveva niente da cui prendere un nome: la cwd è la home, che
`WorkspaceNaming.prompt` scarta perché non identifica niente, e il comando `claude` dava "Claude".
Il segnale c'era già: il titolo OSC che Claude Code scrive sulla tab (`✳ <argomento>`), che la
sidebar mostra come sottotitolo.

### La scelta

Il titolo della chat è un quarto segnale, letto **solo** dalle tab con una sessione agente (altrove
il titolo è della shell) e ripulito da `WorkspaceNaming.chatTitle`: via il glifo, scartati
`✳ Claude Code`, `user@host:path` e la riga di comando. **Non vince sulla cartella**: la cartella
nomina il progetto, la chat il task, e un nome preso dalla prima conversazione invecchia alla
seconda. Il prompt usa la chat solo quando la cartella è generica o manca; senza chiave
`localNames` la mette fra cartella e comando.

Il costo è il timing. Claude scrive il titolo dopo il primo prompt, in modo asincrono, e la nomina
è one-shot: `NamingTriggerPolicy` con una sessione senza titolo aspetta fino a
`chatTitleGraceSeconds` (60s) e poi nomina senza. Chi non scrive titoli (versioni vecchie, Codex)
paga solo quel ritardo. Limite noto: in una cartella generica il trigger cwd scatta dopo 10s, di
solito prima che l'agente parta, e lì la chat entra solo col "Regenerate name". Il titolo è
contenuto dell'utente: con la chiave va all'endpoint configurato, ed è detto in Settings e nella
guida. Dettagli in `docs/features/workspace-naming.md`.

### Esito

15 test nuovi su pulizia del titolo, prompt, derivazione locale e attesa della policy. Guida e
`docs/GUIDE.md` rigenerati nello stesso commit. Rilasciato nella 0.22.0.

## Cycle 29 - Quello che sopravviveva all'uscita

### Il problema, misurato

Il Mac di lavoro saturo (load average 31, 252 MB di RAM libera, compressore a 15 GB) e, fra le
cause, **52 sessioni agente orfane**: zsh figlia di `launchd`, `claude` in foreground con il suo
albero MCP, nessuno a tenere il lato primario della pty. Nate fra il 16 e il 27 settembre, vive fino
a 17 giorni, ognuna rimasta indietro da un riavvio di Relay, quasi sempre un aggiornamento
(0.18.1-0.21.0). In tutto **486 processi, ~4 GB di RSS**. Quattro conversazioni giravano due volte,
l'orfana e la copia ripresa dalla barra di resume, sullo stesso transcript.

Il fix della 0.20 (Cycle 26) non c'entrava: `PtySessionTeardown` gira solo quando si chiude una tab.
All'uscita `applicationWillTerminate` fermava il receiver, salvava il layout e lasciava il resto
all'hangup del kernel, e un agente bloccato l'hangup lo ignora. Il codice lo sapeva già: fence di
run ed `eventFloor` scartavano gli eventi degli orfani. Li nascondevano, non li chiudevano.

Chiuderli a mano ha dato la scala che serve. SIGHUP ai gruppi: muoiono i server MCP, ma restano 52
zsh e 52 `claude`, con 216 figli `<defunct>` che nessuno raccoglie. SIGTERM a `claude`: nessun
effetto dopo 5 s. SIGKILL a `claude`: muore, e la zsh sopravvive di nuovo al SIGHUP fino a un
SIGKILL suo. Le issue di Claude Code lo confermano (#89062, #85782): i segnali passano dall'event
loop JS, e se quello è fermo arriva solo SIGKILL. Dopo: load a 4,6, 4 GB liberi, compressore a 8,9
GB. Numeri e metodo in `docs/research/PERF.md`.

### Cosa fanno gli altri

Nessuno di quelli guardati chiude in modo garantito le sessioni quando l'app crasha. Ghostty ripete
SIGHUP alla chiusura di una tab e all'uscita non fa niente; cmux salva e lascia fare al kernel, come
Relay prima di questo ciclo; VS Code manda SIGHUP alla sola shell. iTerm2 e WezTerm fanno l'opposto:
le sessioni vivono in un server separato e l'app ci si ricollega. Il più vicino è t3code, e solo per
i server OpenCode: un registro su disco con pid, istante di avvio e comando, e la pulizia al lancio
successivo che verifica l'identità prima di segnalare.

### La scelta: registro e pulizia al lancio

Ogni shell che una surface avvia entra in un registro per run (`PtySessionLedger`,
`~/.relay/sessions/<runId>.json`, override `RELAY_SESSIONS`) e ne esce solo a escalation del
teardown finita. Al lancio, **prima di qualsiasi restore**, `PtySessionReaper` chiude le sessioni
delle run il cui Relay non c'è più: SIGHUP, un secondo di attesa (finisce prima se muoiono tutti),
SIGKILL ai superstiti. Niente SIGTERM: contro un `claude` bloccato è misurato inutile, e chi
gestisce i segnali ha già avuto il SIGHUP. Copre uscita, crash e force quit con lo stesso codice, e
il resume non parte mai accanto al suo orfano.

L'invariante del Cycle 26 (una tab possiede la sessione POSIX della sua pty) ora vale anche oltre la
vita dell'app, e ne segue una regola d'uso detta in guida e README: un job che deve sopravvivere a
Relay va fuori dalla sessione della tab (tmux, un job launchd). `nohup` non basta, perché il
processo resta nella sessione.

### Anche la chiusura di una tab chiude tutta la sessione

Il reaper chiudeva al lancio i job sotto `nohup` rimasti in una tab, mentre la chiusura della tab li
lasciava vivi: il teardown del Cycle 26 segnalava solo il gruppo in foreground e quello della shell,
e un `nohup ... &` sta in un gruppo suo e ignora l'hangup che la shell gli inoltra. Due semantiche
per la stessa invariante. **Decisione: la tab possiede la sessione, sempre.** `PtySessionTeardown`
ora cattura tutti i membri della sessione con le regole di `PtySessionReaper` (stesso codice, niente
copia), manda SIGHUP a tutti e tiene la sua scala differita (SIGTERM a 2 s, SIGKILL 3 s dopo). Il
SIGTERM resta: chi ignora l'hangup apposta, come un job sotto `nohup`, ha ancora un modo di chiudere
pulito prima del SIGKILL. Ai gradini successivi la shell è spesso già uscita, quindi la prova è la
cattura più i figli vivi dei membri catturati. Si è perso solo il pgid come unità del segnale: ogni
processo è segnalato per identità esatta. Guida, README e `terminal.md` lo dicono all'utente:
chiudere una tab ferma anche i suoi job in background.

### La prova di appartenenza

Il piano iniziale era segnalare tutta la sessione POSIX della shell registrata (`getsid`), con
`RELAY_RUN_ID` come conferma. Due cose l'hanno cambiato:

- **l'ambiente degli altri processi non si legge**: macOS toglie l'env da `KERN_PROCARGS2` anche per
  i processi dello stesso utente (verificato su Darwin 25). `RELAY_RUN_ID` sarebbe stata la prova
  perfetta, e non è disponibile;
- **il leader muore spesso prima dell'agente**: una zsh pulita esce sull'hangup, l'agente no. A quel
  punto l'id di sessione da solo non prova niente, perché il pid della shell può essere stato
  riusato da un'altra sessione.

Un processo si segnala quindi solo con una prova: la shell registrata è ancora viva con lo stesso
istante di avvio (allora la sessione è nostra), oppure il processo è nella fotografia dei membri che
il registro rinfresca ogni 30 s mentre l'app vive (identità esatta), oppure è figlio vivo di un
membro provato. Mai pid <= 1, mai un altro utente, mai Relay stesso. La fotografia costa una lettura
della tabella dei processi, ~0,2 ms su 900 pid.

### L'uscita

All'uscita normale l'app fotografa i membri e manda SIGHUP a ogni processo delle sessioni vive,
**senza attendere**: i server MCP escono subito e liberano la loro memoria, chi ignora resta nel
registro e lo chiude il lancio successivo. Una scala sincrona fino a SIGKILL avrebbe ritardato ogni
uscita per coprire un caso che il lancio copre comunque; la fotografia va presa prima del SIGHUP,
perché è l'unica prova che resta se la shell muore e l'agente no.

### Il socket ereditato

Trovato provando il reaper end to end: dopo un crash simulato il rilancio usciva subito, in
silenzio. Gli fd del receiver (socket in ascolto, watch della dir, connessioni accettate) non
avevano close-on-exec, quindi ogni shell li ereditava dal fork; gli orfani tenevano vivo il socket
in ascolto sul vecchio path, il guard single-instance lo trovava raggiungibile e Relay se ne andava
convinto che un'altra istanza lo possedesse. Finché gli orfani vivevano Relay non poteva ripartire.
Ora ogni fd del receiver è close-on-exec (ARCHITECTURE, Local Control API).

### Scartati

- **Un processo sentinella** che osserva Relay (kqueue `NOTE_EXIT` o una pipe che dà EOF alla morte
  del padre) e chiude le sessioni subito. Coprirebbe solo "Relay crasha e non lo riapri": tutte le
  52 orfane sono nate da riavvii, e dopo un aggiornamento Relay si riapre subito. È un processo in
  più da distribuire per un caso raro.
- **Sessioni che sopravvivono, alla iTerm2/tmux**: un server che possiede le pty e a cui l'app si
  ricollega. Toglierebbe anche il resume, ma sposta la proprietà dei terminali fuori dall'app
  (protocollo, passaggio dei descrittori, scrollback): settimane, e Relay ha già il resume. Se mai,
  è una scelta di prodotto, non la risposta a questo bug.
- **La sessione POSIX intera come perimetro**, senza prova sul singolo processo: vedi sopra.

### Trappole pagate

Un'istanza di sviluppo lanciata con `nohup` passa SIGHUP **ignorato** a tutte le sue shell (le
disposizioni `SIG_IGN` sopravvivono a fork ed exec, e SwiftTerm non le ripristina): qualsiasi prova
di hangup su quell'istanza è falsata. Costata un giro di verifica che sembrava dare torto al codice.
Le altre (voce del registro tolta a fine escalation e non al `teardown()`, fotografia prima del
SIGHUP) sono in `docs/features/terminal.md`.

### Esito

`make check` verde: registro (decode tollerante, scrittura atomica), prova di appartenenza pura,
reaper su pty vere con un agente sordo a HUP e TERM, il pid riciclato di una sessione estranea
lasciato in pace, il SIGHUP dell'uscita, il socket che non passa alle shell, e la chiusura di una
tab che uccide un `nohup sleep 600 &` (anche dal percorso vero di `SwiftTermSurface.teardown()`) e
un job sordo a HUP e TERM al gradino del SIGKILL.
Verifica sull'app vera, istanza isolata con shell e agente finti (`trap '' HUP TERM; sleep 600`):
crash con leader sordo, crash con leader che muore sull'hangup (lì la prova è la fotografia) e
uscita normale finiscono tutti con `survivors 0` al rilancio, che blocca ~1,04 s solo quando ci sono
orfani. Non verificato con Claude Code vero sull'app installata. Al primo aggiornamento le sessioni
aperte dalla 0.22.0 non sono nel registro (la versione vecchia non lo scrive): quelle che
sopravvivono all'hangup restano coperte solo da floor e fence, e vanno chiuse a mano un'ultima
volta. Rilasciato nella 0.23.0.

## Cycle 30 - Chiudere un progetto senza perderlo

### Il problema

Con decine di progetti la sidebar era diventata una lista di segnalibri. L'unico modo di mettere via
un workspace senza rimuoverlo era l'archivio, che però lo tirava fuori dal gruppo e lasciava vive
le sue sessioni: archiviare non liberava memoria, rimuovere perdeva nome, cartella, gruppo e resume.
Risultato: restava tutto aperto, e una sessione agente costa ~200 MB e ~9 processi
(`docs/research/PERF.md`) che il cap LRU per scelta non tocca. In più la dashboard di triage era un
overlay full-window con due viste (kanban e griglia) che contava anche i progetti messi via.

### La scelta: chiudere è il gesto normale

L'archivio diventa **chiusura** (`Workspace.closed`, `76d9d0e`): il progetto tiene gruppo, tab e
`ResumeBinding`, le sue sessioni vengono disattivate col marker della disattivazione e le surface
buttate dopo, nell'ordine di `session-deactivation.md`. Riaprirlo è come un riavvio: le surface
rinascono al primo focus e la barra di resume ripropone le sessioni. Si può chiudere anche l'ultimo
aperto, e la finestra mostra Home. La chiave su disco resta `archived`: i layout di prima si leggono
senza migrazione e un binario precedente non vede i chiusi come aperti. Rimuovere resta il gesto
distruttivo (`Remove Project`). Due regole cambiano rispetto all'archivio: un chiuso **resta nel suo
gruppo** (la card mostra solo gli aperti, e torna quando ne riapri uno) e **ignora gli eventi
agente**, che sono gli ultimi di un agente ucciso alla chiusura.

### Pagine al posto dell'overlay

`RelayWindow.page` (`6f60387`) fa mostrare al right pane una pagina invece dei terminali, senza
smontarli. **Home** (`Cmd+D`) è il triage dei soli progetti aperti: le sessioni che ti aspettano
con l'ultima riga dell'agente a schermo (`Core.TerminalPeek`, solo da una surface già viva), quelle
al lavoro, i progetti fermi da una settimana da chiudere e i chiusi di recente. **Projects**
(`Shift+Cmd+P`) è il catalogo per gruppo, aperti e chiusi. `Workspace.lastActiveAt`, persistito,
tiene sensati il "fermo da una settimana" e l'ordine del catalogo dopo un riavvio. Con Home in
campo l'overlay della dashboard non aveva più un ingresso ed è stato tolto (`24c7859`) con kanban e
preferenza di layout; le regole di triage condivise stanno in `Panels/SessionTriage`. L'azione
rimappabile tiene il rawValue `toggleDashboard`, per non perdere le combinazioni salvate.

### Navigazione e sidebar

La palette (`Cmd+P`, `4d1bed5`) va a un progetto per nome o cartella e riapre un chiuso; ordine:
aperti prima, poi la corrispondenza migliore, poi il più recente. La sidebar (`914ee1c`) apre con
palette, Home e Projects, poi elenca solo i progetti aperti nelle loro card. La sezione Archive e il
suo drop sono spariti: i chiusi vivono nel catalogo. La x su una riga chiude il progetto, non lo
rimuove.

### La cornice

La finestra diventa una cornice un gradino più scura del terminale con sopra due card arrotondate,
sidebar e contenuto (`c9d055e`), coi colori del tema e non col materiale della sidebar nativa di
macOS 26, così un tema chiaro resta chiaro. I semafori li posiziona AppKit con una toolbar
`.unified` vuota (`c8a3cad`): spostati a mano con `setFrameOrigin` tornavano al loro posto a ogni
relayout. Dettagli in `docs/features/windows.md`.

### Scartati

- **Un'entità nuova per i progetti chiusi** (o una chiave rinominata su disco): avrebbe chiesto
  una migrazione, e un binario precedente avrebbe letto i chiusi come aperti.
- **Tenere la dashboard accanto a Home**: due viste di triage sugli stessi dati. Con i chiusi fuori
  dal conto la lista per urgenza basta, e il kanban non aveva più un caso d'uso.
- **Lasciare i chiusi in una sezione in fondo alla sidebar**, come l'archivio: la sidebar torna a
  essere la lista del lavoro aperto, il resto si raggiunge da palette e catalogo.

### Esito

Test nuovi su ciclo di vita dei progetti (`ProjectLifecycleTests`), modelli di Home, Projects e
palette, triage condiviso, `TerminalPeek` e colori della cornice. Guida, `docs/GUIDE.md` e README
aggiornati, screenshot rifatti. Rilasciato nella 0.24.0. Resta indietro la
sezione della guida in-app sulla sidebar, che descrive ancora i chiusi in una sezione in fondo e il
drag su "Closed".
