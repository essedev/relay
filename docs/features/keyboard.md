# Tastiera: scorciatoie e testo

Chi vede un tasto per primo, e perché è sempre lo stesso monitor. Il resto della guida sta in `../../CLAUDE.md`.

- Shortcut numerici (Cmd/Option + 1..9): gestiti da un `NSEvent` local monitor in
  `AppController`, non dai keyEquivalent di menu. Motivo: i menu con solo Option non matchano (il
  carattere è trasformato, es. Option+1 = "¡"). Le voci numerate del menu "Go" mostrano i **nomi
  reali** di workspace e tab, ripopolate all'apertura (`menuNeedsUpdate` in `AppControllerMenus`:
  il menu si ricostruisce solo al cambio keybinding, quindi non possono essere statiche).
  **Cmd+N segue l'ordine visivo della sidebar** (`navigableWorkspaces`: pinned in testa, membri
  delle card chiuse esclusi), non quello canonico:
  Cmd+1 apre sempre la riga in cima, anche dopo un bump da attività non vista; Option+N naviga la
  strip del
  pane focused.
- Shortcut rimappabili: **tutte** le azioni rimappabili passano dallo **stesso** local monitor.
  Il monitor converte l'evento in `KeyCombo` (`KeyEventBridge`) e cerca l'azione in
  `settings.keybindings`, poi `perform(action)` (`ShortcutRuntime`). Le voci di menu portano la
  combo come **keyEquivalent vero** (colonna nativa delle scorciatoie), ma il trigger resta il
  monitor, che consuma l'evento **prima** che arrivi al menu: niente doppio trigger. Quando il
  monitor si fa da parte (dashboard/onboarding aperti) i keyEquivalent tornerebbero vivi:
  `validateMenuItem` (`AppControllerMenus`) disabilita lì tutte le voci dell'AppController tranne
  il toggle della dashboard, e a overlay chiuso disabilita le azioni no-op (pane senza split,
  move con una tab sola). Il menu si ricostruisce al cambio binding (`observeKeybindings`).
  Fissi: Copy/Paste/Select All (responder SwiftTerm), Quit, Settings, Hide/Minimize/Full Screen
  (in `KeyCombo.systemReserved`: il recorder li rifiuta) e i select 1..9. Il recorder in
  impostazioni alza `settings.isCapturingShortcut` e consuma ogni keyDown nel suo monitor: né il
  monitor di navigazione né i keyEquivalent vedono la combo. Default e conflitti in `AppSettings`.
- Testo da `Option`/AltGr: sui layout internazionali `Option` è anche composizione di testo
 (`Option+ò` = `@`, `Option+digit` = simboli). `Core.KeyboardTextInput` è la policy unica: se
 macOS produce testo stampabile da `Option` senza `Cmd/Ctrl`, quel testo vince sulle shortcut.
 Il monitor delle shortcut lo lascia passare e `OptionTextInterceptor` chiama
 `RelayTerminalView.handleOptionText`, che lo scrive UTF-8 nel PTY prima che il kitty keyboard
 protocol lo codifichi come tasto modificato. **Eccezione: `Option+1..9` (senza Shift) è il
 select-tab fisso e vince sempre sul testo** - il simbolo che il layout comporrebbe (es.
 `Option+1` = `«` sull'italiano) non è digitabile; l'eccezione sta dentro la policy, così monitor,
 surface e recorder restano coerenti senza dipendere dall'ordine dei local monitor. Il recorder
 rifiuta le combo che digitano caratteri sul layout attivo (e `⌘/⌥ 1..9` come `fixedSelect`).
