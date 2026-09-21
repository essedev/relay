# Disattivazione delle sessioni agente

Spegnere l'agente di una tab **tenendo il punto a cui tornare**: la tab resta dov'è, col suo nome e
la sua cwd, e riaprendola la barra di resume rimette in piedi la sessione. È la stessa cosa che
succede dopo un riavvio dell'app, chiesta a mano su una tab o su un workspace intero.

## Perché esiste

Una surface idle costa 0,3-0,5 MB. Una sessione agente costa ~200 MB e ~9 processi, contando
l'albero dei server MCP che si porta dietro (misure in `docs/research/PERF.md`). Il cap LRU non
sfratta mai una tab con processi vivi, per scelta deliberata (Cycle 9 e 15), quindi con decine di
sessioni aperte la memoria è tutta lì e il cap non la tocca. **Il cap non va esteso**: è tarato
sull'unità di misura delle surface, non degli agenti, e sfrattare una sessione senza dirlo sarebbe
una cosa diversa da sfrattare un renderer.

## Le due trappole

**1. L'ordine.** Prima si marca la tab nello store (`WorkspaceStore.deactivate`), poi si butta la
surface (`SurfaceRegistry.release`). Uccidere l'agente fa scattare il suo hook `SessionEnd`, che
Relay mappa su stato `unknown`, e su una tab normale `unknown` azzera il `resume`: se la marcatura
arrivasse dopo, l'evento troverebbe la tab ancora normale e butterebbe via proprio il binding che
serve a tornare indietro. Con il marker, `updateResumeBinding` lascia stare il binding.

**2. Gli hook in ritardo appartengono a una sessione precisa.** Dopo il kill continuano ad arrivare
gli ultimi eventi della sessione morente: uno `Stop` (idle) rimetterebbe la tab in piedi da sola. Il
marker decade solo per un evento con un `sessionId` **diverso** da quello del binding, cioè per una
sessione davvero nuova (l'utente ha lanciato un agente a mano nella tab spenta). Una sessione
ripresa dalla barra passa dallo stesso `sessionId`, e lì è la UI a togliere il marker
(`clearDeactivation`).

## Niente auto-resume su una tab disattivata

`autoResumeAgents` esiste per il riavvio, che è **involontario**: ritrovare le sessioni dov'erano è
quello che vuoi. Una disattivazione è voluta, quindi il suo resume resta deliberato. Senza questa
guardia (`RightPaneController.renderResumeBar`), aprire una tab spenta anche solo per leggerla
rimetterebbe in piedi l'agente appena spento, e il risparmio evaporerebbe proprio durante il triage,
quando apri venti tab di fila per capire quale ti serviva.

## Chi resta fuori

`Tab.deactivationBlock(isOnScreen:)` dà il motivo, non solo un bool, perché la conferma lo mostra:
dire "3 tab su 7" senza dire perché le altre no trasformerebbe un'azione distruttiva in una
scommessa.

- **a schermo** (`WorkspaceStore.isMounted`): buttare la surface da sotto una view lascerebbe un
  terminale morto, stesso criterio con cui la LRU protegge le tab montate. Sul workspace attivo la
  tab che stai guardando è per definizione quella che stai usando, quindi escluderla non è un
  compromesso;
- **agente al lavoro** (`running`): per interrompere c'è la chiusura, che lo dice;
- **nessuna sessione**: spegnerla non lascerebbe niente a cui tornare, e una tab senza agente non
  costa quello che costa una sessione.

Una tab con attenzione fresca (`needs_input`, completamento non visto) **non** è esclusa: il marker
di attenzione sopravvive alla disattivazione, ed è proprio il caso "me ne occupo dopo".

## Dove si trova

- `Workspace > Deactivate Sessions` in menu bar e nel menu contestuale della riga in sidebar:
  agisce su tutto il workspace, con una conferma che conta cosa si spegne e cosa resta fuori. È
  l'azione che serve davvero, perché una per tab imporrebbe decine di decisioni identiche.
- `Deactivate Session` nel menu contestuale di una pill della strip, per la singola tab.

## Persistenza

`deactivated` sta nel `TabSnapshot` con decode tollerante (campo additivo: un layout salvato prima
della feature decodifica a `false` invece di far fallire l'intero decode). Sopravvive al riavvio, o
al primo focus l'auto-resume rimetterebbe in piedi proprio le sessioni spente.

## Cosa non c'è ancora

L'automatismo. Quando si farà, non a tempo: ammissibilità (binding coerente con l'istanza viva,
nessun lavoro accessorio non classificabile), necessità (pressione di memoria sostenuta), priorità
(lì sì, tempo dall'ultima interazione), con isteresi. `idle` è un prerequisito, non
un'autorizzazione: nella stessa tab può girare un dev server. Vedi `docs/ROADMAP.md`.
