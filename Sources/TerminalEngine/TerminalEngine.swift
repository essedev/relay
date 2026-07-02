import Foundation

// Astrazione sottile sull'engine terminale. Il resto dell'app parla con questi tipi, mai con
// SwiftTerm o libghostty direttamente: così cambiare backend è un update localizzato.
// Backend v1: SwiftTerm (dipendenza dichiarata nel Package). Wiring reale in Fase 2.

public protocol TerminalSurfaceHandle: AnyObject {
    var id: UUID { get }
}

public protocol TerminalEngine {
    /// Crea una surface (lazy: chiamata al primo focus del pane, vedi ARCHITECTURE lifecycle).
    func makeSurface(cwd: String?) -> TerminalSurfaceHandle
}
