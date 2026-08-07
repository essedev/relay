# Runtime degli agenti (hook, eventi, resume)

Come gli eventi degli hook arrivano allo store e restano ordinati. Il resto della guida sta in `../../CLAUDE.md`.

- Agent binding: `RELAY_TAB_ID` (= `Tab.id`) è iniettato nell'env della surface e torna dall'hook
  come `paneId`; accanto viaggia `RELAY_RUN_ID` (`Core.RelayRunID`, nonce per processo), che torna
  come `runId` e identifica la **run** dell'app che ha creato la surface (vedi fence di run sotto).
  Il socket è `~/.relay/relay.sock` (override `RELAY_SOCKET`); un socket stantio
  (owner morto) è rimosso da `unlink` prima del `bind`, quindi non blocca il riavvio. **No-stomp**:
  prima di `unlink`+`bind` il receiver fa una `connect` di prova (`UnixSocket.isListening`); se un
  owner **vivo** risponde non lo tocca (`addressInUse`), così una seconda istanza non ruba il
  socket alla prima. **Self-heal**: il receiver osserva la runtime dir (vnode `DispatchSource`, non
  un timer) e **ri-binda** se il socket file sparisce sotto di lui; senza, un socket cancellato da
  fuori orfanava il receiver e **congelava tutti i badge** sull'ultimo stato ricevuto (la causa dei
  badge idle/loading bloccati). Ri-binda solo se il file è davvero assente (se esiste, un'altra
  istanza ne ha uno vivo: no ping-pong).
- Ordine degli eventi agente: ogni hook è un processo effimero con la sua connessione e il
  receiver drena in parallelo (un client bloccato non ferma gli altri), quindi il trasporto NON
  garantisce l'ordine. Lo ristabiliscono il pump FIFO in `AgentCoordinator` (AsyncStream, un solo
  consumer - mai `Task {}` per evento, non preservano l'ordine di enqueue) e la guardia di
  monotonicità sui timestamp nello store (`applyAgentState` scarta gli eventi più vecchi
  dell'ultimo applicato per tab). In più una **soglia anti-stantio** (`WorkspaceStore.eventFloor`,
  timbrata all'avvio dal composition root): scarta ogni evento con timestamp anteriore all'avvio,
  perché non può appartenere a una surface di questa run - è un `SessionEnd`/hook orfano di una
  sessione morta che, col `RELAY_TAB_ID` stabile tra i riavvii, azzererebbe un resume binding
  appena ripristinato (sopprimendo la proposta di resume: era la causa della `ResumeBar` che non
  compariva sempre al riavvio). Il floor però ferma solo gli hook **eseguiti** prima del boot: un
  claude orfano sopravvissuto al riavvio (SIGHUP ignorato, o un `SessionEnd` morente che scavalca
  un relaunch rapido) manda hook con timestamp fresco che passerebbero. Li ferma il **fence di
  run** (`WorkspaceStore.runID` = `RELAY_RUN_ID`): `applyAgentState` scarta gli eventi il cui
  `runId` non è quello della run corrente (compresi i nil), perché uno `Stop` porterebbe la tab
  fuori da `unknown` (barra soppressa a binding intatto) e un `SessionEnd` azzererebbe il binding.
  Alla chiusura, `applicationWillTerminate` ferma il receiver **prima** del flush del layout: i
  `SessionEnd` delle sessioni morenti sono della run corrente e passerebbero il fence proprio
  nello snapshot finale. Il wire codifica le date ISO 8601 **con millisecondi**
  (decode tollerante col vecchio formato a secondi interi e con eventi senza `runId`); un'app
  vecchia però non decodifica gli eventi di un CLI nuovo, e un CLI vecchio (niente `runId`) viene
  scartato dal fence di un'app nuova: dopo un cambio al wire ricompila/reinstalla entrambi.
- Mapping hook -> stato in due metà, entrambe in `HookInstaller`: statico per evento
  (`ClaudeHookInstaller.specs`, finisce nei comandi di settings.json) e dipendente dal payload
  (`ClaudeHookStateMapper`, applicato dal CLI): il `PreToolUse` di un tool che apre un prompt
  bloccante (`AskUserQuestion`, `ExitPlanMode`) diventa `needs_input` - quei tool non passano da
  `PermissionRequest` né producono `Stop` finché non rispondi; senza correzione la tab resterebbe
  `running` per sempre con la domanda aperta.
- Resume Claude: `ResumeBinding` (agent/sessionId/label) catturato in `applyAgentState` (viva) e
  azzerato su `unknown`, persistito nel `TabSnapshot`. Al primo focus di una tab `pendingResume`
  (binding + `agentState==unknown`) `RightPaneController` overlaya `ResumeBar` sul terminale;
  `Resume` -> `surface.sendText("claude --resume <id>\n")`. Setting `autoResumeAgents` (default off)
  inietta da solo. **Il wiring della barra vive nel composition root (RelayApp), non in
  TerminalHostUI**: il path caldo non dipende da Panels. Il resume è **lazy** (al focus), mai in
  massa al boot.
