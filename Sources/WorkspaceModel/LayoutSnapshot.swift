import Foundation

/// Fotografia serializzabile del layout: quanto basta a ricostruire workspace e tab al riavvio.
/// Puro e `Codable`; l'I/O su disco vive fuori dal model (modulo `LayoutStore`). Non contiene stato
/// agente (effimero) né surface (ricreate lazy al focus). Il `version` abilita migrazioni future.
public struct LayoutSnapshot: Codable, Equatable {
    /// Versione dello schema. Bump solo per cambi breaking (la load scarta le versioni diverse,
    /// buttando il layout dell'utente): un campo nuovo opzionale è additivo e NON bumpa, decodifica
    /// pulita in entrambe le direzioni (assente -> nil; ignoto -> ignorato).
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
    /// Origine del nome (vedi `NameOrigin`). Campo additivo (assente nei layout vecchi -> `.user`,
    /// vedi `init(from:)`): non richiede un bump di versione.
    public var nameOrigin: NameOrigin
    public var rootPath: String?
    public var pinned: Bool
    /// Nella sezione Archive. Campo additivo (assente nei layout vecchi -> `false`), quindi non
    /// richiede un bump di versione.
    public var archived: Bool
    public var selectedTabID: UUID?
    public var tabs: [TabSnapshot]

    public init(
        id: UUID,
        name: String,
        nameOrigin: NameOrigin = .user,
        rootPath: String?,
        pinned: Bool,
        archived: Bool = false,
        selectedTabID: UUID?,
        tabs: [TabSnapshot]
    ) {
        self.id = id
        self.name = name
        self.nameOrigin = nameOrigin
        self.rootPath = rootPath
        self.pinned = pinned
        self.archived = archived
        self.selectedTabID = selectedTabID
        self.tabs = tabs
    }

    /// Decode tollerante: `archived` e `nameOrigin` sono additivi, assenti nei layout salvati prima
    /// delle rispettive feature. La sintesi li esigerebbe come chiave e farebbe fallire l'intero
    /// decode (= layout dell'utente buttato via), quindi li leggo con `decodeIfPresent ?? default`.
    /// `nameOrigin` assente -> `.user`: i nomi salvati prima della nomina automatica sono
    /// conosciuti
    /// dall'utente, non vanno rigenerati. Gli altri campi seguono la sintesi (gli opzionali già
    /// tollerano l'assenza). Encode resta sintetizzato.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        nameOrigin = try c.decodeIfPresent(NameOrigin.self, forKey: .nameOrigin) ?? .user
        rootPath = try c.decodeIfPresent(String.self, forKey: .rootPath)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        selectedTabID = try c.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        tabs = try c.decode([TabSnapshot].self, forKey: .tabs)
    }
}

public struct TabSnapshot: Codable, Equatable {
    public var id: UUID
    public var title: String
    public var hasCustomTitle: Bool
    public var currentDirectory: String?
    public var resume: ResumeBinding?
    /// Completamento mai ripreso ("in sospeso") e il suo timestamp: al restore la tab riparte
    /// `pending` con questa età (dashboard, decadenza). `nil` = niente sospeso. Campo additivo
    /// (assente nei layout vecchi -> nil), per questo non ha richiesto un bump di versione.
    public var pendingSince: Date?

    public init(
        id: UUID,
        title: String,
        hasCustomTitle: Bool,
        currentDirectory: String?,
        resume: ResumeBinding? = nil,
        pendingSince: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.currentDirectory = currentDirectory
        self.resume = resume
        self.pendingSince = pendingSince
    }
}
