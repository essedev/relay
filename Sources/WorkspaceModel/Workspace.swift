import Foundation

/// Un progetto: raggruppa tab, sta nella sidebar, si pinna e si riordina.
/// (Model v1; persistence e gerarchia tab/pane arrivano quando servono.)
public struct Workspace: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var rootPath: String
    public var pinned: Bool
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        pinned: Bool = false,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.pinned = pinned
        self.sortIndex = sortIndex
    }
}
