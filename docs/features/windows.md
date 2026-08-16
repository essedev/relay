# Finestre, chrome e overlay

Finestre, chrome senza title bar, overlay e le loro trappole AppKit. Il resto della guida sta in `../../CLAUDE.md`.

- Chrome full-size content view: le `NSHostingView` della chrome (title strip, sidebar, overlay)
  devono avere `safeAreaRegions = []`, altrimenti SwiftUI applica la safe area della title bar e
  spinge il contenuto sotto i semafori. Il layout verticale lo gestiamo noi.
- **Finestre di servizio SwiftUI (Settings/About/Runtime Stats): sempre da `makePanelWindow`**
  (`PanelWindow.swift`), mai `NSWindow(contentViewController: NSHostingController)` +
  `preferredContentSize`. Con la safe area attiva, ogni `setFrameSize` fa reinvalidare a
  `NSHostingView` i suoi safe area insets, che chiede un altro "update constraints pass", che
  ridimensiona la finestra: superati i pass rispetto al numero di view, AppKit **abortisce**
  (`NSGenericException`, "more Update Constraints passes than there are views"). `makePanelWindow`
  monta una `NSHostingView` con `safeAreaRegions = []` come `contentView` e fissa la dimensione.
  Nella stessa famiglia: `NSWindow.applyRelayChrome` è **idempotente** e confronta l'appearance per
  **nome** (`NSAppearance(named:)` non torna istanze condivise, quindi `!==` è sempre vero).
  Riassegnare appearance/sfondo identici consuma pass e porta allo stesso abort.
- Drag finestra: **non** `isMovableByWindowBackground` (trascinerebbe anche il terminale). Le due
  strip in alto (`ContextTitleBar` nel right pane, `trafficLightsStrip` nella sidebar) usano
  `WindowDragArea` (NSView pura con `performDrag` + doppio click = zoom secondo la preferenza
  macOS). NSView pura, non un gesture SwiftUI: `mouseDownCanMoveWindow` non si propaga in modo
  affidabile sotto hosting SwiftUI.
- Onboarding: overlay full-window come la dashboard (`AppControllerOnboarding`, wiring identico a
  `AppControllerDashboard`), al primo avvio (`AppSettings.onboardingSeen`, timbrato alla
  presentazione; mai in demo mode) e da Help > Welcome to Relay. Mentre è aperto il monitor si fa
  da parte (`isOnboardingOpen`, i tasti vanno alla vista: frecce/Invio/Esc via `.focusable` +
  first responder deferito). Un solo overlay full-window alla volta: aprire l'uno chiude l'altro
  (`presentOnboarding`/`openDashboard` si chiudono a vicenda, altrimenti gli host resterebbero
  incoerenti). Niente screenshot nelle pagine: componenti veri (`AgentBadge`, keycap dai binding
  correnti, `ThemeSwatch` che seleziona il tema dal vivo, `RelayMarkView` = icona ridisegnata in
  SwiftUI con la geometria di `bundle/make-icon.swift`, usata anche da About - da dev build
  `NSApp.applicationIconImage` darebbe l'icona generica).
- **Pannello di un overlay full-window: clamp + scroll, mai un frame fisso nudo**. I tre pannelli
  (`Dashboard`, `GuideView`, `OnboardingView`) hanno la stessa forma: `GeometryReader` ->
  `panelSize(in:)` che clampa la misura ideale allo spazio finestra meno `Spacing.lg * 2` (il
  minimo finestra è 700x460, un frame fisso verrebbe tagliato ai bordi), e il **contenuto in
  `ScrollView`** con l'eventuale footer fuori. Senza scroll una pagina con altezza intrinseca
  (testi `fixedSize`) trabocca il suo `maxHeight`, si mangia il footer e il `clipShape` taglia
  titolo e bottoni: era il bug dell'onboarding. Corollario: dentro lo scroll niente
  `maxHeight: .infinity` sulle pagine (rideclina l'altezza sbagliata) e niente `Spacer` per
  centrare (collassa) - il riempimento lo fa `minHeight: contentHeight` sul contenuto, il
  centraggio l'allineamento di quel frame.
- Overlay full-window e hit-testing: `presentFullOverlay` avvolge l'overlay in un
  `FullOverlayContainerView` il cui `hitTest` non torna mai `nil` dentro i bounds e consuma il
  mouse nelle zone senza contenuto hit-testable; senza, mouse e cursor update cadevano sul
  terminale sotto (selezione di testo con l'overlay aperto). Le cursor rects della finestra sono
  disattivate finché l'overlay è su (`disableCursorRects`): quelle di SwiftTerm
  (`addCursorRect(bounds, .iBeam)`) non rispettano l'occlusione e terrebbero l'I-beam sopra
  l'overlay.
- **Ciclo di vita di una finestra (due trappole, pagate con un crash)**: (1) `isReleasedWhenClosed`
  è **`true` di default** sulle `NSWindow` costruite a mano, e la finestra è già posseduta dal suo
  `RelayWindowController` (`let window`): il release extra di AppKit alla chiusura la manda sotto
  zero e il pop dell'autorelease pool fa `objc_release` su memoria morta (SIGSEGV). Va spento in
  `RelayWindowController.init`, come già in `PanelWindow`. Sulla finestra **principale** non si
  vedeva (chiuderla termina l'app): il crash arrivava solo chiudendo una **secondaria**.
  (2) Il teardown del controller è **differito di un giro di runloop** (`windowDidClose`): siamo
  dentro `windowWillClose`, e il controller *è* il delegate della finestra oltre a possederla -
  rilasciarlo lì dealloca finestra e delegate mentre AppKit li sta ancora usando. Il delegate si
  stacca subito, il rilascio va su `DispatchQueue.main.async`.
- **Multi-window**: le finestre **partizionano** i workspace (`Workspace.windowID` + `RelayWindow`
  con la **sua** `selectedWorkspaceID`); lo store, il `layout.json`, il receiver e la
  **`SurfaceRegistry` restano unici** (una tab ha una surface sola ovunque sia montata). Nessuna
  finestra è privilegiata: chiuderne una **rimpatria** i suoi workspace in quella attivata più di
  recente (`closeWindow`), l'ultima chiude l'app. `store.selectedWorkspaceID` è una **proiezione**
  della finestra key, così menu e scorciatoie non sanno nulla di finestre. **`isVisible` si lega alla
  finestra non occlusa (`NSWindow.occlusionState`), NON alla key**: con due monitor la finestra che
  fissi spesso non ha il focus, e notificarla sarebbe il bug del caso d'uso. Il monitor chiede il
  pane a **quella da cui l'evento arriva** (`windowController(for:)`), non alla key. Alla
  terminazione il rimpatrio è **sospeso** (`isTerminating`): macOS chiude le finestre una per una, e
  rimpatriare a ogni passaggio collasserebbe il layout multi-window prima del flush. I frame stanno
  nel `LayoutSnapshot` per id (`setFrameAutosaveName` ne gestirebbe una sola).
