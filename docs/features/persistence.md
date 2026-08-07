# Persistence del layout e istanza singola

Il layout su disco: cosa si salva, quando, e come non perderlo. Il resto della guida sta in `../../CLAUDE.md`.

- Persistence layout: `~/.relay/layout.json` (override `RELAY_LAYOUT`; path **iniettato** in
  `LayoutStore`, i test usano una dir temporanea, mai `~/.relay`). Salvataggio via `LayoutAutosave`
  (debounced ~500ms + flush on `applicationWillTerminate`), che osserva `store.snapshot()`: dipende
  solo dai campi persistiti. La gran parte degli eventi agente non scatena scritture; un **bump**
  però riordina `workspaces` (campo persistito), quindi un'attività non vista **sì** (l'ordine è
  dato utente da salvare) - assorbito dal debounce, non a raffica. **Demo mode non
  persiste** (non istanzia l'autosave). Restore al boot ricade sul seed default se file
  mancante/corrotto/versione ignota. Bump `LayoutSnapshot.currentVersion` **solo per cambi
  breaking**: la load scarta le versioni diverse (= butta il layout dell'utente); un campo nuovo
  opzionale (es. `pendingSince`) è additivo e non bumpa. Il sospeso persiste come `pendingSince`
  nel `TabSnapshot` (anche `unseen` degrada a pending al riavvio: il segnale forte sarebbe stantio).
- Robustezza layout (dato utente non ricreabile): `LayoutStore.save` **rifiuta** uno snapshot
  degradato (`degenerateSnapshot`: 0 workspace o un workspace senza tab - a runtime impossibile,
  quindi sintomo di una race) invece di scrivere sopra il buono, tiene un backup `layout.json.bak`
  del primario prima di sovrascrivere, e `load` ricade sul `.bak` se il primario è
  mancante/corrotto/degradato. Non allentare la guardia: è ciò che ha fixato le tab sparite dopo un
  upgrade. La validità è pura (`isValidForPersistence`, testata). **Downgrade**: la compat del
  layout è solo all'indietro - dal primo save post-split-v2 il file è in formato pane e un binario
  <= 0.8.2 non lo decodifica (dal secondo save nemmeno il `.bak`): un downgrade riparte dal seed.
- Single-instance: **due Relay condividono `~/.relay`** (layout + socket) e i loro autosave si
  pesterebbero -> layout corrotto. `LSMultipleInstancesProhibited=true` (bundle/Info.plist) lo
  previene lato LaunchServices; `Relay.main` ha anche un guard runtime (se un'altra istanza dello
  stesso bundle id gira, la attiva ed esce). Quel guard vale solo dal bundle; un lancio senza
  bundle id (`swift run`) lo salta, e sullo stesso `~/.relay` unlinkerebbe il socket dell'app viva
  (badge congelati). Perciò `Relay.main` ha un **secondo guard basato sul path**: se un receiver
  vivo possiede già il nostro socket (`AgentEventClient.isReceiverReachable`) esco. Istanze dev
  legittime usano `RELAY_SOCKET`/`RELAY_LAYOUT` diversi: path diverso, nessun match, partono
  normali. Non elimina la race di due lanci simultanei (per quella servirebbe un lockfile): copre
  il caso reale del lancio dev mentre un'istanza è già viva.
