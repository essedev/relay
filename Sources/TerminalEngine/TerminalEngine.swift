import AppKit
import Foundation

// Astrazione sottile sull'engine terminale. Il resto dell'app parla con questi tipi, mai con
// SwiftTerm o libghostty direttamente: così cambiare backend è un update localizzato.
// Backend v1: SwiftTerm. Espone solo `NSView` (tipo di piattaforma), mai tipi SwiftTerm.

@MainActor
public protocol TerminalSurfaceHandle: AnyObject {
    var id: UUID { get }
    /// La view da inserire nell'albero AppKit. Tipo di piattaforma, non dell'engine.
    var view: NSView { get }
    /// Notifica quando il programma cambia il titolo (OSC). Usato per auto-titolare la tab.
    var onTitleChanged: ((String) -> Void)? { get set }
    /// Avvia shell/processo. Lazy: chiamato al primo focus del pane (vedi lifecycle ARCHITECTURE).
    func start()
    /// Termina il processo e rilascia le risorse (chiusura tab/workspace).
    func teardown()
}

@MainActor
public protocol TerminalEngine {
    func makeSurface(cwd: String?, shell: String?) -> TerminalSurfaceHandle
}
