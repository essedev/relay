import AppKit
import Panels
import SwiftUI

/// Wiring del manuale in-app (Help > Relay Guide, `Cmd+?`): stesso overlay full-window di dashboard
/// e onboarding, quindi la mutua esclusione fra i tre è gratis (il presenter ha un solo slot).
/// Extension per tenere il corpo di `AppController` sul solo bootstrap.
extension AppController {
    var isGuideOpen: Bool {
        overlayPresenter?.isPresenting(.guide) ?? false
    }

    /// Voce di menu Help > Relay Guide. Toggle come la dashboard: la stessa combinazione la chiude.
    @objc func showGuide(_: Any?) {
        if isGuideOpen {
            closeGuide()
        } else {
            presentGuide()
        }
    }

    func presentGuide() {
        overlayPresenter?.present(.guide) {
            fullOverlayHost(GuideView(
                settings: self.settings,
                onClose: { [weak self] in self?.closeGuide() }
            ))
        }
    }

    func closeGuide() {
        overlayPresenter?.dismiss(.guide)
    }

    /// Riempie i terminali a schermo della demo facendo recitare `relay-cli simulate`: senza,
    /// i pane mostrano tre shell mute, e uno screenshot di Relay senza una chat dentro non dice
    /// niente di cosa fa. Solo le tab **visibili** del workspace selezionato: sono le uniche con
    /// una surface viva (le altre restano `unrealized` finché non le visiti, per design).
    ///
    /// Il CLI sta accanto all'eseguibile, sia in `.build/debug` sia nel bundle. Il ritardo lascia
    /// alle surface il tempo di montare la shell: scrivere in un pty che non ha ancora un prompt
    /// perde i caratteri.
    func startDemoChats() {
        let cli = (Bundle.main.executablePath as NSString?)?
            .deletingLastPathComponent.appending("/relay-cli") ?? "relay-cli"
        guard FileManager.default.isExecutableFile(atPath: cli) else { return }
        // Scenari diversi per pane: due chat identiche affiancate sembrano un errore di copia.
        // Il titolo è quello che manderebbe Claude Code (il nome della chat), non lo
        // `user@host:path` di zsh: è più vero, e tiene fuori dagli screenshot il nome del Mac.
        let chats = [
            (scenario: "coding", title: "fix the flaky reducer test"),
            (scenario: "permission", title: "deploy to staging"),
            (scenario: "burst", title: "refactor the pane tree"),
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let workspace = store.selectedWorkspace else { return }
            for (index, tabID) in workspace.layout.visibleTabIDs.enumerated() {
                let chat = chats[index % chats.count]
                // L'alias e il clear tengono fuori dallo schermo il path assoluto del CLI, che in
                // un dev build è lungo mezza riga e non dice niente a chi guarda. Il titolo va
                // fissato in **entrambi** gli hook di zsh: `precmd` lo riscrive a ogni prompt,
                // `preexec` lo cambia nel comando in esecuzione mentre gira.
                splitVC?.sendText(to: tabID, """
                alias sim='\(cli) simulate'
                title() { print -Pn "\\e]2;\(chat.title)\\a" }
                precmd() { title }
                preexec() { title }
                clear

                """)
                splitVC?.sendText(to: tabID, "sim \(chat.scenario) --fast --loops 3\n")
            }
        }
    }

    /// In demo la finestra nasce più grande del default (1100x700): gli screenshot del README
    /// devono mostrare uno split con del testo dentro senza mandare a capo ogni riga. Differito
    /// come l'overlay: durante il seed la finestra non esiste ancora.
    func resizeWindowForDemo() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, let visible = window.screen?.visibleFrame else {
                return
            }
            let size = NSSize(width: min(1600, visible.width), height: min(1000, visible.height))
            let origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }

    /// `--demo --show dashboard|guide`: apre un overlay subito dopo il seed, per gli screenshot
    /// automatici (`scripts/screenshots.sh` non può premere `Cmd+D` da solo). Differito al giro di
    /// runloop successivo: il presenter monta la hosting view sulla finestra, che durante il
    /// bootstrap non esiste ancora.
    func presentDemoOverlay(_ overlay: DemoOverlay) {
        DispatchQueue.main.async { [weak self] in
            switch overlay {
            case .dashboard: self?.openDashboard()
            case .guide: self?.presentGuide()
            }
        }
    }
}
