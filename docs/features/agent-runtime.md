# Runtime degli agenti (hook, eventi, resume)

Come gli eventi degli hook arrivano allo store e restano ordinati. Il resto della guida sta in `../../CLAUDE.md`.

## Installazione e compatibilità

`relay-cli hooks setup|status|uninstall [claude|codex|all]`: senza argomento resta il default
Claude per compatibilità. Settings > Agents e onboarding offrono un controllo per ogni agente.
`JSONHookInstaller` condivide merge, backup rotazionali e scrittura atomica; gli adapter restano
separati. Path: `~/.claude/settings.json` e `~/.codex/hooks.json` (oppure `CODEX_HOME/hooks.json`).
Override di test: `RELAY_CLAUDE_SETTINGS` e `RELAY_CODEX_HOOKS`.

Codex deve supportare gli hook nativi. Dopo il setup e a ogni modifica delle definizioni, l'utente
deve rivedere il trust tramite `/hooks`; Relay verifica solo la presenza degli spec nel file.
Se esistono anche hook inline in `config.toml`, Codex carica entrambi con un avviso: Relay non
migra né modifica quella configurazione. Contratto upstream:
[hook Codex](https://developers.openai.com/codex/hooks).

## Eventi e resume

- Agent binding: `RELAY_TAB_ID` (= `Tab.id`) è iniettato nell'env della surface e torna dall'hook
  come `paneId`; accanto viaggia `RELAY_RUN_ID` (`Core.RelayRunID`, nonce per processo), che torna
  come `runId` e identifica la **run** dell'app che ha creato la surface (vedi fence di run sotto).
  Con loro viaggia anche `RELAY_SOCKET`, il path su cui **questa** istanza ascolta: la shell di una
  surface non eredita l'ambiente dell'app (l'engine ne costruisce uno minimo), quindi senza
  passarlo a mano l'hook ricadrebbe sul default e un'istanza di sviluppo (avviata con un socket
  suo, come fa `scripts/screenshots.sh`) manderebbe i suoi eventi al Relay di tutti i giorni: le
  sue tab non prenderebbero mai uno stato, e quello vero riceverebbe eventi di tab che non ha.
  Il socket è `~/.relay/relay.sock` (override `RELAY_SOCKET`); un socket stantio
  (owner morto) è rimosso da `unlink` prima del `bind`, quindi non blocca il riavvio. **No-stomp**:
  prima di `unlink`+`bind` il receiver fa una `connect` di prova (`UnixSocket.isListening`); se un
  owner **vivo** risponde non lo tocca (`addressInUse`), così una seconda istanza non ruba il
  socket alla prima. **Self-heal**: il receiver osserva la runtime dir (vnode `DispatchSource`, non
  un timer) e **ri-binda** se il socket file sparisce sotto di lui; senza, un socket cancellato da
  fuori orfanava il receiver e **congelava tutti i badge** sull'ultimo stato ricevuto (la causa dei
  badge idle/loading bloccati). Ri-binda solo se il file è davvero assente (se esiste, un'altra
  istanza ne ha uno vivo: no ping-pong).
- **Raffica**: con decine di sessioni gli hook si connettono nello stesso istante, e un evento
  perso non torna più (la CLI ingoia l'errore per contratto, quindi non lo saprebbe nessuno).
  Tre cose lo impediscono, e vanno tenute insieme: backlog a 128 (`kern.ipc.somaxconn`, il massimo
  che il kernel onora), `acceptConnection` che **svuota tutta la coda** a ogni risveglio della
  source (accettarne una sola la lasciava piena), e nel client un retry breve (10 ms, 30 ms) sui
  soli errori transitori. Misura prima: 76 eventi persi su 100 connessioni simultanee; ora zero.
  Il retry **non** scatta su `ENOENT`, cioè quando Relay non è in esecuzione: lì non c'è niente da
  aspettare e rallenterebbe ogni hook della macchina.
  **Trappola BSD**: il listener è non bloccante per poter fare il loop di accept, e su macOS l'fd
  accettato **eredita** `O_NONBLOCK`. `drain` legge in modo bloccante, quindi ogni fd accettato va
  riportato a bloccante a mano: senza, la read torna `EAGAIN` ogni volta che i byte del client non
  sono ancora arrivati e l'evento si perde invece di essere atteso.
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
- `StopFailure -> error` (Claude Code): unica fonte dello stato `error`. Il turno che muore su un errore API
  (rate limit, overloaded, auth, billing, rete giù) **non** emette `Stop`, che copre solo la fine
  normale: senza questo hook la tab resta `running` per sempre, spinner acceso su una sessione
  ferma. Il matcher di `StopFailure` è il tipo di errore e noi lo installiamo **senza matcher**
  (= `"*"`): tutti i tipi collassano in `error`, i dettagli li legge l'utente dal terminale.
  `error` accende anche il marker `unseen` (vedi `attention.md`): è l'unico stato che è anche
  marker, perché senza non avrebbe ring, bump né notifica. `PostToolUseFailure` **non** è mappato:
  un tool che fallisce dentro un turno che prosegue non è un errore di sessione.
- Codex espone lo stesso lifecycle di base tramite `~/.codex/hooks.json`, incluso
  `PermissionRequest`, più `Interrupt`. Quest'ultimo torna `idle` con `resetsAttention`, così non
  sembra un completamento. Non esiste oggi un hook Codex equivalente a `StopFailure`: Relay non
  interpreta l'output e quindi non inventa lo stato `error`; l'errore resta nel terminale.
- **Migrazione**: ogni installer richiede che **tutti** i propri spec siano presenti,
  non almeno uno. Quando `specs` cresce, un'installazione fatta da una versione precedente
  risulterebbe "installata" e l'utente non riceverebbe mai il nuovo hook. Il setup è idempotente,
  quindi rifarlo è gratis.
- Mapping hook -> stato in due metà, entrambe in `HookInstaller`: statico per evento negli spec
  dell'installer e dipendente dal payload nei mapper Claude/Codex. Il `PreToolUse` di un tool che apre un prompt
  bloccante (`AskUserQuestion`, `ExitPlanMode`) diventa `needs_input` - quei tool non passano da
  `PermissionRequest` né producono `Stop` finché non rispondi; senza correzione la tab resterebbe
  `running` per sempre con la domanda aperta.
- Resume agente: `ResumeBinding` (agent/sessionId/label) catturato in `applyAgentState` (viva) e
  azzerato su `unknown`, persistito nel `TabSnapshot`. Al primo focus di una tab `pendingResume`
  (binding + `agentState==unknown`) `RightPaneController` overlaya `ResumeBar` sul terminale;
  `Resume` usa `claude --resume <id>` oppure `codex resume <id>`. Setting `autoResumeAgents` (default off)
  inietta da solo. **Il wiring della barra vive nel composition root (RelayApp), non in
  TerminalHostUI**: il path caldo non dipende da Panels. Il resume è **lazy** (al focus), mai in
  massa al boot.
