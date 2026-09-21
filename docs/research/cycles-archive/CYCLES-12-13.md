# Cycles 12-13 (archivio)

Il giro sull'ordine della sidebar: prima il riordino libero con un drag fluido, poi il ribaltamento
che manda via il float e fa della posizione un ordine reale. Spostati qui dalla rotazione di
`../CYCLES.md` (che tiene gli ultimi ~15). Numerazione intatta: `Cycle 12` resta `Cycle 12`.

Le decisioni ancora vincolanti che nascono qui non vivono solo in questo storico: il meccanismo di
riordino (`Panels/Reorderable`, la riga vera trascinata con `DragGesture` + `.offset` invece del
drag di sistema) e i due segmenti di drop stanno in `docs/features/sidebar.md`; il bump reale
(`bumpWorkspaceToTop`), il gate su `!isVisible` e lo scollegamento fra posizione in sidebar e
segnale di attenzione stanno in `docs/features/attention.md`.

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

