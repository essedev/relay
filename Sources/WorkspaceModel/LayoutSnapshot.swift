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
    /// Il workspace mostrato dalla finestra key. Resta anche col multi-window: è la selezione da
    /// cui
    /// ripartire, e i layout salvati prima delle finestre non hanno altro.
    public var selectedWorkspaceID: UUID?
    public var workspaces: [WorkspaceSnapshot]
    /// Le finestre aperte. Campo additivo: assente nei layout salvati prima del multi-window, che
    /// al
    /// restore ricadono su una finestra sola (`RelayWindow.mainID`) con tutti i workspace dentro.
    public var windows: [WindowSnapshot]

    public init(
        version: Int = LayoutSnapshot.currentVersion,
        selectedWorkspaceID: UUID?,
        workspaces: [WorkspaceSnapshot],
        windows: [WindowSnapshot] = []
    ) {
        self.version = version
        self.selectedWorkspaceID = selectedWorkspaceID
        self.workspaces = workspaces
        self.windows = windows
    }

    /// Decode tollerante: `windows` è additivo (vedi sopra), la sintesi lo esigerebbe come chiave e
    /// farebbe fallire l'intero decode, cioè butterebbe il layout dell'utente.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        selectedWorkspaceID = try c.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceID)
        workspaces = try c.decode([WorkspaceSnapshot].self, forKey: .workspaces)
        windows = try c.decodeIfPresent([WindowSnapshot].self, forKey: .windows) ?? []
    }
}

/// Una finestra salvata: quale workspace mostrava e dov'era sullo schermo.
public struct WindowSnapshot: Codable, Equatable {
    public var id: UUID
    public var selectedWorkspaceID: UUID?
    public var frame: WindowFrame?
    /// Aveva il focus al momento del salvataggio: al restore torna key.
    public var isKey: Bool

    public init(
        id: UUID,
        selectedWorkspaceID: UUID?,
        frame: WindowFrame? = nil,
        isKey: Bool = false
    ) {
        self.id = id
        self.selectedWorkspaceID = selectedWorkspaceID
        self.frame = frame
        self.isKey = isKey
    }
}

public struct WorkspaceSnapshot: Codable, Equatable {
    public var id: UUID
    /// La finestra che lo possiede. Campo additivo (assente nei layout salvati prima del
    /// multi-window -> `RelayWindow.mainID`, l'unica finestra di allora).
    public var windowID: UUID
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
    /// Disposizione dei pane. Campo additivo (assente nei layout pre-split -> `nil`, ricostruito
    /// come pane radice con tutte le tab). Il `Codable` di `SplitNode` decodifica anche il formato
    /// v1 (foglie-tab). Al restore viene sanitizzato contro le tab davvero ricostruite.
    public var splitLayout: SplitNode?
    /// Il pane focused. Campo additivo (assente nei layout pre-cmux -> il pane della selezione).
    public var focusedPaneID: UUID?

    public init(
        id: UUID,
        windowID: UUID = RelayWindow.mainID,
        name: String,
        nameOrigin: NameOrigin = .user,
        rootPath: String?,
        pinned: Bool,
        archived: Bool = false,
        selectedTabID: UUID?,
        splitLayout: SplitNode? = nil,
        focusedPaneID: UUID? = nil,
        tabs: [TabSnapshot]
    ) {
        self.id = id
        self.windowID = windowID
        self.name = name
        self.nameOrigin = nameOrigin
        self.rootPath = rootPath
        self.pinned = pinned
        self.archived = archived
        self.selectedTabID = selectedTabID
        self.tabs = tabs
        self.splitLayout = splitLayout
        self.focusedPaneID = focusedPaneID
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
        windowID = try c.decodeIfPresent(UUID.self, forKey: .windowID) ?? RelayWindow.mainID
        name = try c.decode(String.self, forKey: .name)
        nameOrigin = try c.decodeIfPresent(NameOrigin.self, forKey: .nameOrigin) ?? .user
        rootPath = try c.decodeIfPresent(String.self, forKey: .rootPath)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        selectedTabID = try c.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        tabs = try c.decode([TabSnapshot].self, forKey: .tabs)
        splitLayout = try c.decodeIfPresent(SplitNode.self, forKey: .splitLayout)
        focusedPaneID = try c.decodeIfPresent(UUID.self, forKey: .focusedPaneID)
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
