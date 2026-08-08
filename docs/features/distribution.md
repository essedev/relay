# Bundle, distribuzione e aggiornamenti

Dal sorgente al `.app` installato: bundle, firma, release, aggiornamenti. Il resto della guida sta in `../../CLAUDE.md`.

- `make bundle` assembla `.build/Relay.app` (release + `relay` **e `relay-cli`** in `Contents/MacOS`,
  entrambi firmati - il nested prima dell'outer - + `bundle/Info.plist` + `AppIcon.icns` + firma
  `SIGN_IDENTITY`, default `-` ad-hoc, bundle id `dev.relay.app`; versione iniettata da `./VERSION`
  via PlistBuddy; `LICENSE` e `NOTICE` copiati in `Contents/Resources`, che è un obbligo della MIT
  di SwiftTerm: la notice va riprodotta in ogni distribuzione, non basta averla nel repo).
  `relay-cli` nel bundle serve agli utenti brew: Settings > Agents ha un'azione che installa gli
  hook usando il cli accanto all'eseguibile (`makeHookControls`), quindi funziona anche se il PATH
  non è a posto. **In più il cask fa `binary` su entrambi gli eseguibili**
  (`Relay.app/Contents/MacOS/relay-cli` e `/relay`), così i comandi documentati nel README
  (`relay-cli hooks setup`, `relay --demo`) esistono davvero in shell dopo un'installazione brew.
  Le stanze `binary` stanno solo nel cask, nel repo del tap: `scripts/release.sh` tocca unicamente
  `version` e `sha256`, quindi non le sovrascrive. `make run-app` lo avvia, `make install-app` lo copia in `/Applications`,
  `make dmg` fa `.build/Relay-<version>.dmg` (installer **non firmato Developer ID**: primo avvio con
  "Apri comunque"). Serve per le notifiche: `UNUserNotificationCenter` richiede un bundle id, da bare
  executable (`swift run`) crasha; in sviluppo `make run` va bene (niente notifiche).
- **Distribuzione (brew tap)**: Relay è distribuito via `brew install --cask essedev/relay/relay`.
  Il tap è il repo pubblico `essedev/homebrew-relay` (cask `Casks/relay.rb`), il cask scarica il
  `.dmg` dalle Release di `essedev/relay`. La routine `scripts/release.sh` (via `make release`):
  check working tree pulito + branch main + account gh `essedev`; blocca se il tag `vX` esiste già
  (idempotente per versione); `make dmg` -> sha256 -> `git tag vX` + push -> `gh release create` con
  l'asset -> clona il tap, aggiorna `version`+`sha256` nel cask (l'URL li interpola) e pusha. Per
  rilasciare: bumpa `./VERSION`, commit, **poi** `make release`. **Firma**: `make release` usa il
  **self-signed stabile** `Relay Self-Signed` (default in `scripts/release.sh`, preparato in modo
  idempotente da `scripts/setup-signing.sh`: cert + keychain + trust, esce non-zero con le istruzioni
  se il trust manca), così l'identità non cambia a ogni build. L'ad-hoc (`-`) è l'opt-out esplicito
  (`SIGN_IDENTITY=- make release`) ed è invece il **default di `make bundle`/`make dmg`** lanciati a
  mano: con l'ad-hoc l'identità cambia a ogni build, quindi "Apri comunque" si ripete a ogni upgrade
  e il permesso notifiche può decadere. Developer ID + notarizzazione non ancora in piedi
  (toglierebbe l'"Apri comunque" del tutto).
- Icona: `bundle/make-icon.swift` (Core Graphics puro, headless) la disegna; `make icon` rigenera
  `bundle/AppIcon.icns` (committato). Cambi al disegno -> `make icon` poi `make bundle`.
- Check aggiornamenti (canale brew): `UpdateController` (RelayApp) al lancio confronta la versione
  installata (`CFBundleShortVersionString`) con l'ultima GitHub Release
  (`/repos/essedev/relay/releases/latest`), e se più recente accende una pill transitoria in fondo
  alla sidebar, **sopra la sezione Archive** (l'ancora Archive resta fissa, la pill si inserisce nel
  flusso sopra di lei). La logica è pura in `Core` (`SemanticVersion` compara, `ReleaseCheck` parsa
  e decide se l'update è azionabile rispettando lo skip), testata; rete/clipboard/apertura URL
  stanno nel controller. **Non scarica**: la pill offre solo il comando `brew update && brew upgrade
  --cask relay` da copiare, le release notes e "Skip this version" (persistito in
  `skippedUpdateVersion`, si ripropone solo a una versione ancora più nuova). Nessun conflitto con
  brew, che resta l'updater. Oltre a "copia", la pill ha un **play** che esegue il comando in una
  tab dedicata "Relay Update" (`AppController.runUpdateInTab`, iniettato via
  `makeSidebarConfig(onRunUpdate:)`): sempre una tab fresca, il testo va nel pty col solito ritardo
  del resume; `brew` sostituisce il bundle mentre l'app gira (safe su APFS, riparte alla
  riapertura). Come le notifiche gira **solo dal bundle** (`swift run` non ha
  `CFBundleShortVersionString`: `makeSidebarConfig()` -> `nil`, niente pill, check no-op). Preferenza
  in Settings > Updates (default on) + voce menu "Check for Updates…" (check manuale, dà sempre un
  feedback, anche "yoùre up to date"). **Rete non pronta**: il check al lancio può cadere su un DNS
  ancora freddo (`-1003 cannotFindHost`, tipico dopo boot/risveglio/switch VPN). Due difese:
  `fetchLatest` ritenta **una sola volta** dopo 3s sui codici che falliscono subito
  (`retriableCodes`; `.timedOut` è **escluso** di proposito, ritentarlo porterebbe il check manuale
  a 30s prima dell'alert), e il check **automatico** usa una `URLSession` dedicata con
  `waitsForConnectivity` (proprietà della configuration, non della richiesta: da qui le due
  sessioni), così un lancio da offline aspetta la rete invece di fallire. Il manuale resta su una
  sessione che fallisce in fretta, e il testo grezzo di URLSession non arriva più all'utente:
  `userFacingMessage` mappa gli errori di rete su "check your internet connection".
- CI deterministica: gli strumenti di lint sono **pinnati** (SwiftFormat/SwiftLint, versioni nel
  Makefile), scaricati come binari dai release GitHub in `.build/tools` da `make tools` (uno stamp
  versionato forza il riscarico al bump). `make lint`/`format`/`check` li usano; il workflow CI non
  fa più `brew install` (prendeva l'ultima: una regola nuova upstream rompeva il lint su codice
  invariato, la causa della CI rossa da 0.7.0). CI e locale girano la stessa identica versione.
