import Foundation

/// Fotografia serializzabile del layout: quanto basta a ricostruire workspace e tab al riavvio.
/// Puro e `Codable`; l'I/O su disco vive fuori dal model (modulo `LayoutStore`). Non contiene stato
/// agente (effimero) né surface (ricreate lazy al focus). Il `version` abilita migrazioni future.
public struct LayoutSnapshot: Codable, Equatable {
    /// Versione dello schema. Bump quando cambia la forma; `LayoutStore` scarta versioni ignote.
    public static let currentVersion = 1

    public var version: Int
    public var selectedWorkspaceID: UUID?
    public var workspaces: [WorkspaceSnapshot]

    public init(
        version: Int = LayoutSnapshot.currentVersion,
        selectedWorkspaceID: UUID?,
        workspaces: [WorkspaceSnapshot]
    ) {
        self.version = version
        self.selectedWorkspaceID = selectedWorkspaceID
        self.workspaces = workspaces
    }
}

public struct WorkspaceSnapshot: Codable, Equatable {
    public var id: UUID
    public var name: String
    public var rootPath: String?
    public var pinned: Bool
    public var selectedTabID: UUID?
    public var tabs: [TabSnapshot]

    public init(
        id: UUID,
        name: String,
        rootPath: String?,
        pinned: Bool,
        selectedTabID: UUID?,
        tabs: [TabSnapshot]
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.pinned = pinned
        self.selectedTabID = selectedTabID
        self.tabs = tabs
    }
}

public struct TabSnapshot: Codable, Equatable {
    public var id: UUID
    public var title: String
    public var hasCustomTitle: Bool
    public var currentDirectory: String?

    public init(id: UUID, title: String, hasCustomTitle: Bool, currentDirectory: String?) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.currentDirectory = currentDirectory
    }
}
