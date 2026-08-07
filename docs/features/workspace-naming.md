# Nomina automatica dei workspace

Come un workspace prende un nome da solo. Il resto della guida sta in `../../CLAUDE.md`.

- Nomina automatica workspace (LLM OpenAI-compatible): un workspace nato come placeholder o da
  cartella (`NameOrigin.default`) viene rinominato al primo segnale utile da quello che ci fai. La
  logica pura sta in `Core.WorkspaceNaming` (costruzione prompt dai segnali cwd/comando/agente,
  parsing, sanitizzazione: strip virgolette/markdown, cap ~28 char al confine di parola, reject dei
  generici; testata) e in `Core.NamingTriggerPolicy` (la state-machine pura che decide *quando* il
  segnale è abbastanza forte: streak del comando + stabilizzazione cwd, con soglie; testata). Il
  `NamingController` (RelayApp, **unico punto che tocca la rete** per questa
  feature) osserva l'eleggibilità (`settings.workspaceNamingEnabled` + esiste un `.default` +
  `credentials.hasKey()`) e, quando serve, fa girare un **poll** (timer ~3s) sui workspace
  `.default`. Il contesto si raccoglie su **tutte le tab** del workspace, non sulla selezionata: la
  tab in vista è spesso una shell ferma mentre l'agente gira in quella accanto, ed è il workspace
  che si nomina. `Core.WorkspaceNaming.signals` (puro, testato) sceglie **una** tab - la più
  informativa (agente > comando > cwd, a parità vince quella a schermo) - e ne prende i segnali
  **interi**: mescolare il comando di una tab con la cwd di un'altra descriverebbe un'attività che
  non esiste. Se la tab scelta non ha cwd (mai realizzata: restore, sfratto LRU) si ricade sul
  `rootPath` del workspace. Tre trigger, dal più forte: agente attivo (`running`/`needs_input`) ->
  subito; comando in foreground stabile per 2 tick (argv via `TerminalSurfaceHandle
  .foregroundCommandLine`, letta con `KERN_PROCARGS2`) -> es. "Homebrew Update"; cwd stabile fuori
  dalla home per ~10s -> es. "Yellow Hub". **La cwd è quella della shell viva**
  (`WorkspaceAreaController.currentDirectory`, precedenza `Core.CurrentDirectory` = viva -> OSC 7 ->
  root, iniettata nel controller), **non** `tab.currentDirectory`: quello è il solo OSC 7, che zsh
  in Relay non emette (vedi `terminal.md`), quindi il segnale cwd sarebbe sempre nil e la nomina da
  directory non scatterebbe (era la causa del "Regenerate name" muto su un workspace fermo).
  **Single-flight per workspace**, max 2 tentativi **distanziati da un cooldown di 60s** poi si
  arrende in silenzio (senza il cooldown la policy, che ha già deciso "nomina", ridecideva a ogni
  tick: un blip di rete bruciava i due tentativi in sei secondi e spegneva la nomina per sempre).
  La nomina **automatica** resta silenziosa (mai un alert per un nome che non hai chiesto); quella
  **manuale** no, vedi sotto. Il poll gira **solo** finché c'è un `.default`
  (osservazione su `nameOrigin`): quando tutti sono nominati il timer si ferma. Alla risposta,
  `store.applyGeneratedName` applica **solo** se il workspace è ancora `.default` (l'utente può aver
  rinominato nel frattempo: `renameWorkspace` marca `.user`, intoccabile). `NameOrigin`: `.default`
  (eleggibile) -> `.generated` (one-shot) / `.user` (a mano). Snapshot **additivo** (assente ->
  `.user`: i nomi pre-feature sono conosciuti dall'utente, non rigenerare). **"Regenerate name"**
  (menu contestuale della sidebar **e** menu Workspace) passa da
  `AppController.regenerateWorkspaceName` -> `NamingController.regenerate`: torna `.default`, azzera
  abbandono/tentativi/cooldown, nomina **subito** col contesto corrente (salta le soglie della
  policy) e chiede un nome **diverso** da quello attuale (`prompt(avoiding:)`, solo se l'attuale
  l'ha generato il modello: `temperature` è 0, quindi a contesto invariato ridarebbe lo stesso
  identico nome e sembrerebbe non aver fatto niente). **Non cablarlo su `store.markNameRegenerable`
  da solo**: quello rimette solo il workspace in coda al poll passivo, che su un workspace fermo
  resta muto - era il bug del "Regenerate name che non fa niente" (`regenerate` era codice morto,
  mai chiamato da nessuna delle due voci). A differenza del poll, l'azione manuale **non tace mai**:
  ogni ramo che non produce un nome torna un `NamingFailure` (`notConfigured`/`noContext`/
  `requestFailed`) che il composition root mostra come sheet (`presentNamingFailure`, con "Open
  Settings…" sul primo). La
  API key è un segreto: **file 0600** `~/.relay/naming-credentials.json` (`NamingCredentialStore`),
  **non** UserDefaults; base URL + model in `AppSettings`. Config in Settings > Agents > Workspace
  naming. Gira anche da `swift run` (non è bundle-gated come notifiche/update), ma è inerte senza
  chiave. Mai in demo mode (nomi fissi).
- **Endpoint di default: OpenRouter** (`openrouter.ai/api/v1`) con `deepseek/deepseek-v4-flash-latest`
  (0,09$/M token in ingresso, 0,18$/M in uscita: una nomina costa un millesimo di centesimo). Prima
  era OpenAI + `gpt-4o-mini`; il cambio è secco, **senza migrazione**: chi aveva configurato l'altro
  endpoint senza toccare i campi si ritrova il default nuovo e rimette base URL e modello a mano in
  Settings > Agents. Deciso così di proposito - la feature è opt-in e inerte senza chiave, e un
  ramo di compatibilità per un default vale meno del codice che costa.
- **Modelli di reasoning nella nomina** (`ChatCompletionClient`, il client HTTP estratto dal
  `NamingController`): il tetto `max_tokens` deve coprire anche il *pensiero*, non solo il nome.
  Con 16 token un modello di reasoning (es. `deepseek/deepseek-v4-flash` su OpenRouter) torna
  `finish_reason: length` e **`content: null`**, quindi non nomina **mai** - e con `content: String`
  non opzionale il decode dell'intera risposta falliva, mascherando tutto come generico "richiesta
  fallita". Ora il tetto è **512** (è un massimale, non una spesa: i modelli normali si fermano al
  nome) e `content` è opzionale, con log dedicato che cita il `finish_reason`. I messaggi d'errore
  del client sono `privacy: .public` (sono stringhe di URLSession/JSONDecoder, non payload utente):
  con la redazione di default in console si leggeva `<private>` e la diagnosi andava fatta a mano
  con `curl`.
