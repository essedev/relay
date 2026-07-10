import Foundation

/// Una finestra dell'app. Le finestre sono una **partizione** dei workspace: ognuno appartiene a
/// esattamente una finestra, e lo store resta unico (un solo `~/.relay/layout.json`, un solo
/// receiver di eventi agente). Nessuna finestra è "la principale": chiuderne una rimpatria i suoi
/// workspace in quella attivata più di recente.
///
/// Puro e osservabile: la `NSWindow` vera vive nel composition root, legata per `id`.
@Observable
public final class RelayWindow: Identifiable {
    public let id: UUID
    /// Il workspace mostrato in questa finestra. Ogni finestra ha la **sua** selezione: due
    /// finestre
    /// mostrano due workspace diversi contemporaneamente.
    public var selectedWorkspaceID: UUID?
    /// Ultimo frame noto, persistito per riaprirla dov'era. `nil` = mai posizionata (la centra
    /// AppKit). `setFrameAutosaveName` non basta più: sa gestire una finestra sola.
    public var frame: WindowFrame?

    public init(id: UUID = UUID(), selectedWorkspaceID: UUID? = nil, frame: WindowFrame? = nil) {
        self.id = id
        self.selectedWorkspaceID = selectedWorkspaceID
        self.frame = frame
    }

    /// Id della finestra che esiste al primo avvio e dove finiscono i workspace dei layout salvati
    /// prima del multi-window (campo `windowID` assente). Costante, così la migrazione è stabile e
    /// non serve inventare un id nuovo a ogni restore. Non è privilegiata in nessun altro modo: si
    /// chiude come le altre.
    public static let mainID = UUID(uuid: (
        0x2E, 0x1A, 0x4B, 0x00, 0x52, 0x45, 0x4C, 0x41,
        0x59, 0x00, 0x57, 0x49, 0x4E, 0x00, 0x00, 0x01
    ))
}

/// Frame di una finestra in coordinate schermo. Struct pura (niente CoreGraphics nel model), così
/// `WorkspaceModel` resta senza dipendenze di piattaforma.
public struct WindowFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
