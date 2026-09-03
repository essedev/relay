# Attenzione, notifiche e dashboard

Come Relay dice che una sessione ti aspetta: livelli, notifiche, ring, dashboard. Il resto della guida sta in `../../CLAUDE.md`.

- **L'errore accende il marker**: `error` (da `StopFailure`, vedi `agent-runtime.md`) è l'unico
  stato che è **anche** marker: il reducer gli fa alzare `unseen` come a un completamento, e nasce
  forte anche sopra un `pending` già declassato (un errore nuovo è un fatto nuovo). Senza marker un
  turno morto per errore non avrebbe ring, bump né notifica: resterebbe un pallino rosso su una
  riga in fondo alla sidebar. I due canali restano indipendenti: il declassamento (flash o
  interazione) spegne il segnale forte ma **non** il badge rosso, che segue `agentState` finché non
  riprendi. La guardia del bump è `attention == .unseen && previousAttention != .unseen`, non
  "usciva da `none`": con la vecchia forma un errore (o un completamento) sopra un `pending` alzava
  il marker senza bump né flash, e restava `unseen` per sempre senza aver chiamato nessuno.
- Notifiche: tre tipi, uno per stato che nasce da Claude - entrata in `needs_input`, entrata in
  `error`, completamento non visto - ognuno col suo toggle in Settings (`notifyOnNeedsInput`,
  `notifyOnError`, `notifyOnCompleted`, tutti default on) sotto il master `notificationsEnabled`.
  `running` e `unknown` non notificano di proposito: il primo lo generano `UserPromptSubmit` e ogni
  `PreToolUse`/`PostToolUse` (decine di eventi per turno, causati dal tuo prompt), il secondo è
  `SessionEnd` (`/clear`, `exit`, logout). Sono azioni tue: notificarle seppellirebbe le altre.
  `needs_input` ed `error` notificano solo alla **entrata** nello stato, quindi una raffica di
  retry falliti riaccende il badge ogni volta ma suona una volta sola.
  Il trigger è puro (`AgentStateReducer.notification`), lo store emette via
  `onNotifiableTransition` e il `NotificationCoordinator` (solo se `Bundle.main.bundleIdentifier !=
  nil`) filtra per preferenze e consegna. `isVisible = tab selezionata && NSApp.isActive`: se Relay è
  in background notifica anche sulla tab selezionata. Il marker "completato" (`attention`, enum
  `AttentionLevel`) **non** si spegne al semplice ritorno in foreground né alla selezione della tab
  (altrimenti sparirebbe prima che tu lo veda; aprire una tab completata mostra il ring verde +
  flash): l'interazione col terminale in vista **declassa** `unseen` -> `pending` ("in sospeso":
  visto ma mai ripreso), non spegne. **Posizione e segnale sono scollegati** (modello "lista chat"):
  la posizione in sidebar è un ordine **reale e persistente**, non un float derivato. A muoverla è
  solo un **bump** (`WorkspaceStore.bumpWorkspaceToTop`, da `applyAgentState`), che porta il
  workspace in cima al **proprio contenitore** (la lista, o la sua card di gruppo) quando
  un'attività arriva **non vista** - completamento, **errore API** o entrata
  in `needs_input` con `!isVisible` (simmetrico al segnale forte e alla notifica: un completamento
  sulla tab **in vista** **non** bumpa, così la riga non salta sotto le mani). La
  ripresa (`running`) non muove niente: la riga su cui lavori resta ferma, la scavalca solo un altro
  bump o il tuo drag. Il segnale (`attention`: ring/badge) vive a parte: declassamento (mark-read),
  dismiss e decadenza lo spengono ma **non** fanno scendere la riga (scende solo col drag).
  "Interazione col terminale" è filtrata (`owningPane`,
  `WorkspaceAreaController`, via il monitor in `AppControllerNavigation`): un tasto col terminale
  in focus o un click **dentro la sua view**, non un click di navigazione nella chrome (cambio tab
  nella strip, cambio workspace nella sidebar) né un tasto in un campo di rename - quelli non
  consumano il marker. Risolve solo un'azione **attiva** sulla conversazione - la ripresa vera
  (prompt -> running) o una ri-presa attiva (`/clear`, `/resume`: SessionStart `source` clear/resume
  -> `resetsAttention`, letto dal CLI, spegne il sospeso mantenendo `state` idle) - più il dismiss
  (card della dashboard), la chiusura tab e la decadenza (`pendingDecayHours`, default **12h**: il
  sospeso è il segnale quieto e già visto, tenerlo per sempre è banner blindness; `unseen` invece
  non scade mai da solo). Override manuale dal **menu contestuale** (sidebar sulla tab selezionata
  del workspace, strip per-tab) e dal menu Workspace: `store.toggleUnread` è chiavato su `unseen`,
  non su "attenzione
  accesa". Solo `unseen` è "unread": lì il menu mostra **"Mark as Read"** e spegne a `none`. Un
  `pending` è **già visto** (segnale quieto), quindi non lo si "legge": come da `none` il menu mostra
  **"Mark as Unread"** -> `Tab.markUnread` che lo ri-alza a `unseen` (riusa il segnale forte
  esistente: ring e badge; **non** bumpa la riga in sidebar - il bump nasce da un evento agente, non
  da un flag manuale - e niente notifica, che nasce solo da eventi reali). Il pending si
  spegne altrove (resume, dismiss, decadenza), non da questo toggle. Al riavvio degrada a pending
  come ogni `unseen`. Il clock del marker è `Tab.attentionSince` (timbrato alla nascita e al
  declassamento), **distinto** da `lastEventAt` (che avanza a ogni evento per la monotonicità): il
  decay e l'età del sospeso misurano da `attentionSince`, così un no-op (SessionEnd, idle->idle) non
  li falsifica, e al restore il clock riparte dal boot (un completamento vecchio mai visto non viene
  spazzato al primo avvio). Un completamento sulla tab **in vista** nasce comunque col segnale
  forte (`unseen`: ring verde + flash + badge pieno) e dopo un breve **flash** (~4s) il composition
  root lo declassa a `pending` (mark-read differito: `store.onVisibleCompletion` ->
  `AppController.scheduleCompletionFlashDecay` -> `store.markSeen(id)`; no-op se nel frattempo
  interagisci/riprendi/dismetti). Prima nasceva già `pending`, niente flash. Il reducer non guarda
  più la visibilità (`reduce` senza `isVisible`): il completamento nasce sempre `unseen`, il
  declassamento in vista è un effetto del composition root. Al ritorno in foreground un flash del
  ring richiama l'occhio, senza spegnere. Modello ispirato a cmux
  (vedi CYCLES),
  esteso col livello quieto. Il coordinatore è
  `UNUserNotificationCenterDelegate` e forza `willPresent -> [.banner,.sound,.list]`: **senza, i
  banner sono soppressi quando Relay è frontmost**. Al primo avvio dal bundle macOS chiede il
  permesso una volta; una firma ad-hoc che cambia a ogni reinstall può farlo decadere (log
  `auth status` al boot: 2 = authorized). **Click sulla notifica**: riporta in vista la tab che
  l'ha generata. `AgentNotification` porta `tabID`/`workspaceID`, che il coordinatore mette nel
  `userInfo` del contenuto; alla ricezione (`didReceive response`, azione di default) legge gli id
  e delega a `AppController.activateTab` (seleziona workspace+tab, de-archivia se serve, porta la
  finestra in primo piano). Senza l'handler il click non faceva nulla.
- Ring di attenzione (`AttentionRingView`): bordo colorato attorno al terminale della tab in vista
  che ne segnala lo stato (verde = completato non visto, statico + flash; giallo/rosso pulsante =
  aspetta input/errore). Giallo e rosso vengono da `agentState` (`needs_input`/`error`) e restano
  finché lo stato cambia, anche dopo che il marker è stato declassato; il **verde** risponde solo a
  `unseen`, perché un sospeso (`pending`) non accende il bordo (segnale quieto: badge ad anello vuoto + dashboard), altrimenti useresti la shell con un
  ring verde permanente. Colori dai colori ANSI del tema, coerenti coi badge. Overlay con `hitTest`
  nil (non intercetta eventi); i terminali si inseriscono `positioned: .below` così resta in cima.
  L'observer del ring (`observeRing`) è **separato** da `render()` e **non** scrive `attention`:
  altrimenti un completamento sulla tab in vista si spegnerebbe da solo (loop col reset della
  visita). Il declassamento (mark-read) lo fa solo l'interazione col terminale (monitor key/mouse).
- Dashboard (`Cmd+D`, azione rimappabile `toggleDashboard`): overlay full-window
  (`RootOverlayController.presentFullOverlay`, wiring in `AppControllerDashboard`). **Due viste**
  scambiabili da un toggle in header (preferenza persistita `AppSettings.dashboardLayout`, default
  **kanban**): kanban per stato su quattro corsie di triage (Needs You = needs_input/error, Running,
  Done = completati non visti, Idle = pending/idle/resume) e la **griglia flat** storica per
  urgenza. **Il pannello è identico nelle due viste** (stessa barra di ricerca, stessa dimensione
  fissa 820x580 ma **clampata alla finestra** via `panelSize(in:)` - il minimo finestra è 700x460,
  un frame fisso puro verrebbe tagliato; le colonne kanban sono flessibili, il toggle scambia solo
  il contenuto - non ridimensiona). Il focus del filtro all'apertura ha un retry (`.task`): il set
  in `onAppear` è una race col primo layout e, se cade, il presenter mette il first responder
  sull'host e il campo resta sordo (Esc/frecce mute). Esc chiude anche dal contenitore
  (`onExitCommand` sulla root oltre che sul campo).
  Card con età e dismiss, filtro type-to-search, frecce + Invio (nav flat nella griglia, 2D nel
  kanban), Esc chiude. Logica pura in `Panels/DashboardModel` (raggruppamento `Lane`/`Column`/
  `columns` testato); rendering board + `SessionCard` in `Dashboard+Board.swift` (estratti dal
  corpo di `DashboardView` per i limiti file/tipo). Solo dati del model, funziona anche per tab
  sfrattate dal cap LRU (niente preview del terminale: richiederebbe surface vive). **Mentre è
  aperta il monitor si fa da parte**: i tasti vanno al filtro (niente nav 1..9, niente mark-read),
  resta attivo solo il toggle per chiuderla; Esc lo gestisce la vista (`onExitCommand`). La
  decadenza dei sospesi si applica a boot/foreground/apertura dashboard (niente timer). Il set
  differito del first responder in `FullOverlayPresenter` **non ruba** il focus al campo che l'ha
  già preso via `@FocusState` (salta se il first responder è già un discendente dell'host).
