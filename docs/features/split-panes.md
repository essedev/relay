# Split panes - modello "pane ospita tab" (stile cmux)

Stato: **implementato** (v2 dello split). Sostituisce il modello v1 "split di tab" (foglie =
`Tab.id`), che aveva un difetto strutturale: la tab bar globale e i pane erano due viste dello
stesso insieme di tab, con la semantica ambigua "montata vs selezionata" e nessun posto naturale
dove aprire "una tab accanto a una porzione".

## Il pattern (da cmux/bonsplit)

Riferimento: `manaflow-ai/bonsplit` (il framework di split di cmux, letto a fondo prima di questo
design). Il pattern che copiamo:

- **Il pane è un'entità che ospita tab**: ogni pane ha la sua lista ordinata di tab e la sua
  selezione. Un quarto di schermo può avere 2 tab; ognuna col suo titolo che si muove col pane.
- **Tab bar per pane**, non globale: la strip vive in cima a ogni pane. Click su una tab =
  selezione nel suo pane **e** focus a quel pane.
- **Action lane** a destra di ogni strip: nuova tab (`plus`), split right (`square.split.2x1`),
  split down (`square.split.1x2`). Compare sul pane focused e in hover.
- **Chiusure**: chiudere l'ultima tab di un pane chiude il pane (il fratello prende lo spazio).
  Chiudere un pane chiude le sue tab.
- **Split**: divide il pane focused a metà (ratio 0.5), la nuova tab/pane prende il focus.

## Data model (WorkspaceModel)

```
SplitPane { id, tabIDs: [UUID], selectedTabID }     // il pane, con le sue tab
SplitNode = pane(SplitPane)
          | split(id, axis, ratio, first, second)    // invariato nella parte branch
Workspace { tabs: [Tab], layout: SplitNode, focusedPaneID }
```

- `Workspace.tabs` resta il **sacco** degli oggetti `Tab` (identità, sessione agente, snapshot):
  l'ordine visivo vive nei pane. Invariante: l'unione dei `tabIDs` dei pane = gli id di `tabs`,
  senza duplicati.
- `layout` è **sempre presente** (prima: `nil` = pane singolo). Pane singolo = un solo nodo
  `.pane` con tutte le tab. Sparisce la doppia rappresentazione dello stesso stato.
- `selectedTabID` diventa **derivato**: la selezione del pane focused. Il vecchio
  "monta o metti a fuoco" diventa `reveal`: seleziona la tab nel suo pane + focus a quel pane.
  Nessuna sostituzione di foglie: selezionare non muta mai la struttura.
- **Visibile** (ex "montata") = selezionata nel suo pane. Guida ring, mark-read, protezione LRU,
  soppressione di notifica/bump. **Focused** = la selezione del pane focused (tastiera, Cmd+K).

## Operazioni

| Azione | Semantica |
| --- | --- |
| `Cmd+T` | nuova tab **nel pane focused**, in fondo alla sua strip, selezionata |
| `Cmd+\` / `Cmd+Shift+\` | split del pane focused con una **nuova tab** (cwd ereditata), focus al nuovo pane |
| "Open in Split Right/Down" (menu tab) | **sposta** la tab esistente in un nuovo pane accanto al focused (sessione viva). No-op se è l'unica tab del suo pane e il target è quel pane |
| `Cmd+W` | chiude la tab selezionata del pane focused; il pane collassa se resta vuoto; l'ultima tab dell'ultimo pane chiude il workspace (cascade) |
| `Opt+Cmd+W` (close pane) | chiude il pane **e le sue tab** (conferma se hanno processi in foreground). Prima "smontava" lasciando la tab viva: nel nuovo modello non esiste un posto fuori dai pane |
| `Cmd+]` / `Cmd+[` | focus al pane successivo/precedente (ordine visivo, ciclico) |
| `Opt+1..9` | seleziona la N-esima tab **del pane focused** |
| Click su tab | seleziona nel suo pane + focus al pane |

## Persistence e migrazione

- `SplitNode` ha un `Codable` **compatibile all'indietro**: il vecchio caso `leaf(UUID)` decodifica
  come pane con quella sola tab. Nessun bump di `LayoutSnapshot.currentVersion`.
- `WorkspaceSnapshot` guadagna `focusedPaneID` (additivo). Restore:
  - layout assente (vecchio pane singolo) -> pane radice con tutte le tab nell'ordine snapshot,
    selezione = `selectedTabID`;
  - layout vecchio (foglie-tab) -> pane da una tab l'uno; le tab non nel layout vengono
    **adottate** dal pane che contiene `selectedTabID` (o dal primo);
  - sanitizzazione: dedup di tab fra pane, scarto id ignoti, pane vuoti collassati, sempre >= 1
    pane.

## Rendering (TerminalHostUI)

- `PaneView` chiavata per **`SplitPane.id`** (prima: `Tab.id`): il pane sopravvive al cambio della
  tab selezionata; si **scambia** solo la view del terminale dentro (le surface restano vive nella
  registry, chiavate per `Tab.id` come oggi).
- La strip è SwiftUI (Panels) ma TerminalHostUI non può dipendere da Panels: il composition root
  inietta una factory `makePaneStrip(paneID) -> NSView` (NSHostingView di `PaneTabBar`).
- `hasSameStructure` confronta id di pane e branch + assi: cambiare selezione o tab dentro un pane
  **non** ricostruisce le view; il reconcile del contenuto (quale surface è attaccata a quale pane)
  gira a ogni render ed è un confronto + swap.
- First responder: si prende solo quando cambia la coppia (pane focused, sua tab selezionata).
- La tab bar globale (`TabBarView` in cima al right pane) **sparisce**: la rimpiazzano le strip
  per pane. `ContextTitleBar` resta (drag della finestra, titolo workspace).

## Cosa NON copiamo (per ora)

- Drag di tab fra pane / edge-drop per creare split col drag (bonsplit lo ha; noi restiamo su
  menu contestuale + shortcut, il drag riordina solo dentro la strip). In ROADMAP.
- Zoom del pane (`togglePaneZoom`), full-width tab mode, pin di tab nelle strip.
- Navigazione direzionale spaziale fra pane (bonsplit usa bounds+overlap; noi cicliamo).
