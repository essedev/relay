# Roadmap

Piano forward dell'app Relay: cosa manca e in che ordine. La storia (cicli chiusi, milestone
consegnate, analisi engine e benchmark) vive in `docs/research/CYCLES.md`; i dettagli di design in
`ARCHITECTURE.md` e in `docs/features/*.md`. Qui non si accumula: una milestone chiusa esce da
questo file.

## Dove siamo

Baseline chiuso e app **distribuita via Homebrew tap**
(`brew install --cask essedev/relay/relay-terminal`), ultima release **0.23.0**. Ci sono: agent
runtime per Claude Code e Codex con badge, notifiche e resume; attenzione a tre livelli;
persistence del layout; cap LRU delle surface; split sul modello cmux e multi-window; gruppi in
sidebar; nomina automatica; guida in-app; sessioni pty possedute dalla tab anche oltre la vita
dell'app. Dopo la 0.23.0, non ancora rilasciati: **progetti aperti e chiusi** (chiudere tiene tutto
e libera la memoria), **Home** e **Projects** come pagine del right pane al posto della dashboard,
palette `Cmd+P` e la finestra a card (Cycle 30, `docs/features/projects.md`). La storia per
release sta in `docs/research/CYCLES.md`.

## Disattivazione automatica delle sessioni agente

La disattivazione **a mano** c'è e regge il caso d'uso (`docs/features/session-deactivation.md`):
spegne la sessione, tiene il `ResumeBinding`, la tab torna in piedi dalla barra di resume; chiudere
un progetto lo fa per tutte le sue tab insieme (`docs/features/projects.md`). Manca
l'automatismo, che è il pezzo delicato e **non va fatto a tempo**. Tre condizioni separate:

- **ammissibilità**: binding coerente con l'istanza viva, nessun lavoro accessorio non
  classificabile. `idle` è un prerequisito, non un'autorizzazione: nella stessa tab può girare un
  dev server;
- **necessità**: pressione di memoria sostenuta, non una soglia istantanea;
- **priorità**: lì sì, tempo dall'ultima interazione, con isteresi.

Il cap LRU resta fuori da questa partita: non sfratta mai una tab con processi vivi (scelta
deliberata, per DECISIONS #3) ed è tarato sull'unità di misura delle surface, non degli agenti. **Non
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

- Home: l'ultima riga dell'agente anche per le tab senza surface viva (oggi `TerminalPeek` legge
  solo da una surface già montata, e non se ne crea una per leggerla).
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
