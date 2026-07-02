import Foundation

/// Backend v1 basato su SwiftTerm. Stub: il wiring con `LocalProcessTerminalView` arriva in
/// Fase 2. Tenuto dietro `TerminalEngine` così l'app non dipende da SwiftTerm.
public final class SwiftTermEngine: TerminalEngine {
    public init() {}

    public func makeSurface(cwd: String?) -> TerminalSurfaceHandle {
        SwiftTermSurface(id: UUID())
    }
}

final class SwiftTermSurface: TerminalSurfaceHandle {
    let id: UUID
    init(id: UUID) { self.id = id }
}
