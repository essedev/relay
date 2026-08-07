# Guida utente (in-app + docs/GUIDE.md)

Il manuale di Relay ha **una fonte e due rese**. La fonte è dato, non prosa: `Guide.sections`
(`Sources/WorkspaceModel/Guide*.swift`), una lista di sezioni fatte di blocchi tipizzati. Le rese
sono `Panels/GuideView` (Help > Relay Guide, `Cmd+?`) e `docs/GUIDE.md` (`GuideMarkdown`, generato
da `make guide-md`).

Il motivo è la lezione di `README.it.md`, rimasto indietro di tre release rispetto all'inglese:
due prose parallele divergono sempre, una resa generata no.

## Invarianti

- **Il contenuto non conosce la sua resa.** Niente "clicca qui sotto" né riferimenti a cosa c'è a
  schermo: la stessa frase deve funzionare in un pannello e in un file markdown.
- **Le scorciatoie non si scrivono a mano.** Nel contenuto si cita una `ShortcutAction`
  (`GuideShortcut.action`); i tasti li mette la resa - i binding vivi nel pannello (se l'utente
  rimappa, la guida mostra la sua combinazione), i default di fabbrica nel markdown, perché un file
  committato non può dipendere da chi lo genera. Il blocco `.allShortcuts` genera la tabella
  completa da `ShortcutAction.allCases`: **un'azione nuova compare da sola in entrambe le rese**, e
  `GuideMarkdownTests` fallisce se qualcuna resta fuori.
- **`docs/GUIDE.md` è generato.** Non editarlo: `make guide-md` lo riscrive. Un test
  (`committedGuideMatchesTheGeneratedOne`) fallisce se il file committato è disallineato dalla
  fonte, quindi la dimenticanza si vede in CI e non in produzione.
- **Gli slug delle sezioni sono stabili** (`GuideSection.id`): finiscono nelle ancore del markdown
  e nei link del README (`docs/GUIDE.md#keyboard`). Cambiare un titolo è gratis, cambiare uno slug
  rompe dei link.
- **La ricerca del pannello non ha keyword.** `GuideSection.searchText` concatena tutto il testo
  della sezione: a differenza di `SettingsView`, che ha una lista di keyword per blocco da tenere
  allineata a mano, qui non c'è niente da aggiornare. Il filtro richiede **tutte** le parole
  ("drag tab" non pesca ogni sezione che dice drag).

## Dove sta cosa

- `WorkspaceModel/Guide.swift` - i tipi (`GuideSection`, `GuideBlock`, `GuideTopic`,
  `GuideShortcut`) e l'ordine delle sezioni.
- `WorkspaceModel/GuideLayoutSections.swift` - workspace/tab, pane/finestre, sidebar.
- `WorkspaceModel/GuideAgentSections.swift` - stato agente, dashboard, nomina automatica.
- `WorkspaceModel/GuideSystemSections.swift` - tastiera, aspetto, aggiornamenti, più
  `Guide.shortcutNotes` (le glosse delle poche azioni la cui label non basta).
- `WorkspaceModel/GuideMarkdown.swift` - la resa markdown, a capo a 100 colonne come il resto del
  repo.
- `Panels/GuideView.swift` + `GuideBlockView.swift` - il pannello (master-detail con ricerca, sul
  modello di `SettingsView`) e la resa dei blocchi col design system.
- `relay/AppControllerGuide.swift` - wiring: overlay full-window (stesso presenter di dashboard e
  onboarding, quindi la mutua esclusione è gratis) e voce di menu.
- `relay-cli guide-md` - il generatore, comando di sviluppo fuori dall'usage del CLI.

## Perché nel menu Help e non nelle impostazioni

Le impostazioni sono il posto dove si **cambia** qualcosa, la guida quello dove si **legge**:
mescolarle allunga liste di `Cmd+,` che oggi si scorrono bene. `Cmd+?` è per giunta il posto
canonico dell'aiuto su macOS, e non è fra le azioni rimappabili, quindi non collide col recorder.

Con la guida aperta il monitor si fa da parte come per gli altri overlay
(`AppControllerNavigation.isOverlayOpen`), ma `validateMenuItem` tiene viva la sua voce di menu:
serve a chiuderla.

## Screenshot

`scripts/screenshots.sh` rigenera le immagini del README pilotando una demo **isolata**
(`RELAY_SOCKET`/`RELAY_LAYOUT` in una cartella temporanea, tema via `NSArgumentDomain`): non tocca
`~/.relay` né le preferenze, e convive con un Relay già aperto. Gli overlay li apre la demo stessa
(`--demo --show dashboard|guide`), perché uno script non può premere `Cmd+D`. Serve il permesso
Screen Recording per il terminale che lo lancia.
