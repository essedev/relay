import AppKit
import SwiftUI

/// Rende una zona trascinabile come una vera title bar: drag della finestra e doppio click
/// (zoom/minimizza secondo la preferenza macOS, `System Settings > Desktop & Dock`). Serve perché
/// con full-size content view le nostre strip coprono la title bar di sistema, che altrimenti non
/// riceverebbe il drag. Si usa al posto di `isMovableByWindowBackground`, che rendeva trascinabile
/// tutto il corpo (anche il terminale).
///
/// NSView pura (non un gesture SwiftUI): `performDrag(with:)` è deterministico anche sotto hosting
/// SwiftUI, dove `mouseDownCanMoveWindow` non sempre si propaga. Il doppio click è gestito a mano
/// perché con `performDrag` non arriva quello nativo.
public struct WindowDragArea: NSViewRepresentable {
    public init() {}

    public func makeNSView(context _: Context) -> NSView {
        DragView()
    }

    public func updateNSView(_: NSView, context _: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                Self.performTitleBarDoubleClick(on: window)
                return
            }
            // Nessun movimento -> `performDrag` ritorna al mouseUp senza spostare, lasciando
            // arrivare il secondo click del doppio click.
            window.performDrag(with: event)
        }

        /// Replica il doppio click sulla title bar rispettando la preferenza di sistema.
        private static func performTitleBarDoubleClick(on window: NSWindow) {
            let key = "AppleActionOnDoubleClick"
            let action = UserDefaults.standard.string(forKey: key) ?? "Maximize"
            switch action {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        }
    }
}
