import AppKit
import Core
import Panels
import SwiftUI
import TerminalEngine
import TerminalHostUI
import WorkspaceModel

/// Una finestra viva: la `NSWindow` con il suo split (sidebar + pane), gli overlay e i suoi eventi.
/// Legata al `RelayWindow` del model per `windowID`; mostra il workspace **che quella finestra ha
/// selezionato**, quindi due finestre mostrano due workspace insieme.
///
/// Non conosce lo store se non per leggerlo: le decisioni (chi diventa key, chi rimpatria i
/// workspace di una finestra che chiude) le prende `AppController` via callback, che resta l'unico
/// punto di wiring.
@MainActor
final class RelayWindowController: NSObject, NSWindowDelegate {
    let windowID: UUID
    let window: NSWindow
    let splitVC: MainSplitViewController
    let rootController: RootOverlayController
    let overlayPresenter: FullOverlayPresenter

    /// La finestra ha preso il focus.
    var onBecomeKey: ((UUID) -> Void)?
    /// La finestra è entrata o uscita dall'occlusione (coperta, minimizzata, su un altro Space).
    /// Guida `isVisible`: una tab in una finestra occlusa non la stai guardando.
    var onOcclusionChange: ((UUID, Bool) -> Void)?
    /// La finestra sta per chiudersi: i suoi workspace vanno rimpatriati, non buttati.
    var onClose: ((UUID) -> Void)?
    /// Nuovo frame dopo un resize o uno spostamento: lo persiste lo snapshot del layout.
    var onFrameChange: ((UUID, WindowFrame) -> Void)?

    init(
        windowID: UUID,
        splitVC: MainSplitViewController,
        toggleOverlay: NSView,
        frame: WindowFrame?
    ) {
        self.windowID = windowID
        self.splitVC = splitVC
        window = NSWindow(
            contentRect: frame.map(Self.rect) ?? NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        rootController = RootOverlayController(content: splitVC, overlay: toggleOverlay)
        overlayPresenter = FullOverlayPresenter(root: rootController, splitVC: splitVC)
        super.init()

        window.title = "Relay"
        // Sotto questa soglia sidebar + terminale non hanno più spazio utile.
        window.contentMinSize = NSSize(width: 700, height: 460)
        // Il contenuto sale fino al bordo: il titolo visibile è la strip del right pane.
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // Niente drag dal corpo: la finestra si sposta solo dalle strip in alto (`WindowDragArea`).
        window.isMovableByWindowBackground = false
        window.contentViewController = rootController
        window.delegate = self
        // Il frame lo persiste il `LayoutSnapshot`, per finestra: `setFrameAutosaveName` ne
        // gestirebbe una sola, e la seconda finestra si sovrapporrebbe alla prima.
        if frame == nil { window.center() }

        splitVC.onSidebarWidthChange = { [weak rootController] width in
            rootController?.sidebarWidthDidChange(width)
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    /// Porta la finestra davanti e le dà il focus (click su una notifica, jump dalla dashboard).
    func activate() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applyChrome(_ theme: RelayTheme) {
        window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(relay: theme.background)
    }

    var currentFrame: WindowFrame {
        let rect = window.frame
        return WindowFrame(
            x: Double(rect.origin.x), y: Double(rect.origin.y),
            width: Double(rect.width), height: Double(rect.height)
        )
    }

    private static func rect(_ frame: WindowFrame) -> NSRect {
        NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_: Notification) {
        onBecomeKey?(windowID)
    }

    /// `occlusionState` è l'unico modo per sapere se la finestra è **davvero** a schermo: coperta
    /// da
    /// un'altra app, minimizzata o su un altro Space non lo è. È la nozione che guida notifiche e
    /// bump - non l'avere il focus, che con due monitor mente (vedi `isVisible`).
    func windowDidChangeOcclusionState(_: Notification) {
        onOcclusionChange?(windowID, !window.occlusionState.contains(.visible))
    }

    func windowDidResize(_: Notification) {
        onFrameChange?(windowID, currentFrame)
    }

    func windowDidMove(_: Notification) {
        onFrameChange?(windowID, currentFrame)
    }

    func windowWillClose(_: Notification) {
        onClose?(windowID)
    }
}
