# Roadmap

Piano forward dell'app Relay: cosa manca e in che ordine. La storia (cicli chiusi, milestone
consegnate, analisi engine e benchmark) vive in `docs/research/CYCLES.md`; i dettagli di design in
`ARCHITECTURE.md` e in `docs/features/*.md`. Qui non si accumula: una milestone chiusa esce da
questo file.

## Dove siamo

Baseline chiuso e app **distribuita via Homebrew tap**
(`brew install --cask essedev/relay/relay-terminal`): agent runtime + badge, attenzione a tre
livelli con dashboard di triage, persistence del layout, cap LRU delle surface, bundle `.app` con
notifiche, gruppi in sidebar, nomina automatica dei workspace, guida in-app, **split v2 sul modello
cmux** (i pane ospitano le tab, una strip per pane), **multi-window** e gli errori API come stato di
prima classe per Claude Code (0.17.0). La 0.19.0 aggiunge Codex tramite hook nativi, con setup,
notifiche e resume dedicati; il limite sugli errori API Codex è descritto sotto. La **0.20.0**
chiude il giro sulle sessioni: il teardown di una tab **termina davvero** la sessione pty (shell,
agente, albero MCP, descrittore) e le sessioni agente si spengono a mano tenendo il resume
(`docs/research/CYCLES.md`, Cycle 26). Dopo la 0.20.0 e non ancora rilasciato: la catena delle
notifiche resa affidabile end-to-end - nessun evento perso sotto raffica di hook, drift degli hook
Claude riparato all'avvio, una sola notifica viva per tab che si ritira quando l'attenzione si
spegne (Cycle 27).

## Disattivazione automatica delle sessioni agente

La disattivazione **a mano** c'è e regge il caso d'uso (`docs/features/session-deactivation.md`):
spegne la sessione, tiene il `ResumeBinding`, la tab torna in piedi dalla barra di resume. Manca
l'automatismo, che è il pezzo delicato e **non va fatto a tempo**. Tre condizioni separate:

- **ammissibilità**: binding coerente con l'istanza viva, nessun lavoro accessorio non
  classificabile. `idle` è un prerequisito, non un'autorizzazione: nella stessa tab può girare un
  dev server;
- **necessità**: pressione di memoria sostenuta, non una soglia istantanea;
- **priorità**: lì sì, tempo dall'ultima interazione, con isteresi.

Il cap LRU resta fuori da questa partita: non sfratta mai una tab con processi vivi (scelta
deliberata, Cycle 9 e 15) ed è tarato sull'unità di misura delle surface, non degli agenti. **Non
va esteso.** Resta scartato anche il salvataggio del transcript al teardown, che sembrava il passo
abilitante: il perché sta in `docs/research/CYCLES.md`, Cycle 26.

## Prossimo giro (a scelta)

Nessuno dei tre è iniziato; si prende quello che serve per primo.

1. **Distribuzione firmata**: Developer ID + notarizzazione. Toglie l'"Apri comunque" e apre a
   homebrew-cask ufficiale. Il tap non firmato regge intanto. Vedi `docs/features/distribution.md`.
2. **Terzo agente** (opencode): il piano è qui sotto.
3. **Drag di tab fra pane** (incluso l'edge-drop stile bonsplit per creare uno split trascinando) e
   **drag di workspace fra finestre**: oggi una tab si sposta col menu contestuale e con lo
   shortcut, il drag riordina solo dentro la strip.

## Più avanti

- Dashboard oltre le due viste attuali: azioni inline (resume/chiudi) sulle card, contatore
  aggregato nell'header del pannello (quelli per corsia nel kanban ci sono già), preview delle
  ultime righe (richiede surface vive).
- PR upstream a SwiftTerm sul teardown: `LocalProcess.terminate()` chiude la `DispatchIO` senza
  `.stop` (la read sul descrittore primario non completa mai) e `childStopped()` cancella il
  `DispatchSourceProcess` che avrebbe fatto `waitpid`. Con la patch mergiata e il pin aggiornato, di
  `PtySessionTeardown` resta utile solo l'escalation, rete di sicurezza per chi ignora SIGHUP.
- Zoom del pane ed equalize dei divider.
- Rename del workspace dalla menu bar (oggi solo dal contestuale della sidebar).
- Altri hook Claude Code non ancora sfruttati: il set è cresciuto molto dal mapping v1
  (`PermissionDenied`, `Notification` con matcher `idle_prompt`, `SubagentStart`, `PostCompact`,
  `PreModelSwitch`, `CwdChanged`). Nessuno urgente, `StopFailure` era l'unico che copriva un buco
  vero, ma la lista va ripassata quando si tocca il mapping. Aggiungerne uno ora costa meno: chi ha
  installato con una versione precedente se lo vede riparare all'avvio (Cycle 27).
- Export della timeline degli eventi agente; import di temi da config Ghostty.

## Generalizzazione multi-agente

Claude Code e Codex sono integrati tramite hook nativi sopra lo stesso wire normalizzato. Gli
installer condividono trasformazioni JSON, backup e scrittura atomica; UI, notifiche e resume
scelgono l'agente della sessione. Rimane un limite upstream: Codex non espone un hook equivalente a
`StopFailure`, quindi Relay non può distinguere un errore API Codex senza interpretare l'output (che
resta deliberatamente fuori dal modello affidabile).

Prossimo banco di prova: **opencode**, che espone un event bus consumato da un plugin TypeScript
anziché hook shell. Se il boundary regge un vettore così diverso, l'astrazione multi-agente è
confermata. Resta fuori scope l'orchestrazione multi-agent nella stessa sessione.
