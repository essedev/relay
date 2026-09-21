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
    /// I gruppi della sidebar (solo aspetto: i membri stanno su `WorkspaceSnapshot.groupID`). Campo
    /// additivo, assente nei layout salvati prima dei gruppi -> nessun gruppo, righe tutte libere.
    public var groups: [GroupSnapshot]

    public init(
        version: Int = LayoutSnapshot.currentVersion,
        selectedWorkspaceID: UUID?,
        workspaces: [WorkspaceSnapshot],
        windows: [WindowSnapshot] = [],
        groups: [GroupSnapshot] = []
    ) {
        self.version = version
        self.selectedWorkspaceID = selectedWorkspaceID
        self.workspaces = workspaces
        self.windows = windows
        self.groups = groups
    }

    /// Decode tollerante: `windows` e `groups` sono additivi (vedi sopra), la sintesi li esigerebbe
    /// come chiave e farebbe fallire l'intero decode, cioè butterebbe il layout dell'utente.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        selectedWorkspaceID = try c.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceID)
        workspaces = try c.decode([WorkspaceSnapshot].self, forKey: .workspaces)
        windows = try c.decodeIfPresent([WindowSnapshot].self, forKey: .windows) ?? []
        groups = try c.decodeIfPresent([GroupSnapshot].self, forKey: .groups) ?? []
    }
}

/// Un gruppo salvato: solo identità e aspetto. L'appartenenza vive sui workspace, quindi qui non
/// c'è una lista di membri che il restore debba validare.
public struct GroupSnapshot: Codable, Equatable {
    public var id: UUID
    public var name: String
    public var colorIndex: Int
    public var collapsed: Bool
    public var pinned: Bool

    public init(id: UUID, name: String, colorIndex: Int, collapsed: Bool, pinned: Bool) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.collapsed = collapsed
        self.pinned = pinned
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
    /// Il gruppo che lo contiene. Campo additivo (assente -> `nil`, riga libera). Un id che non
    /// trova il suo gruppo degrada a riga libera, non fa fallire il restore.
    public var groupID: UUID?
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
        groupID: UUID? = nil,
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
        self.groupID = groupID
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
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        selectedTabID = try c.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        tabs = try c.decode([TabSnapshot].self, forKey: .tabs)
        // Tolleranti anche al **valore**, non solo alla chiave: un nodo corrotto (file toccato a
        // mano) o di un formato futuro degrada a `nil` - pane radice con tutte le tab al restore -
        // invece di far fallire l'intero decode e buttare il layout dell'utente.
        splitLayout = try? c.decodeIfPresent(SplitNode.self, forKey: .splitLayout)
        focusedPaneID = try? c.decodeIfPresent(UUID.self, forKey: .focusedPaneID)
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
    /// La sessione è stata spenta di proposito (vedi `Tab.deactivated`): sopravvive al riavvio,
    /// altrimenti al primo focus `autoResumeAgents` rimetterebbe in piedi proprio le sessioni che
    /// avevi spento. Campo additivo, letto con un default (vedi `init(from:)`).
    public var deactivated: Bool

    public init(
        id: UUID,
        title: String,
        hasCustomTitle: Bool,
        currentDirectory: String?,
        resume: ResumeBinding? = nil,
        pendingSince: Date? = nil,
        deactivated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.currentDirectory = currentDirectory
        self.resume = resume
        self.pendingSince = pendingSince
        self.deactivated = deactivated
    }

    /// Decode tollerante per lo stesso motivo di `WorkspaceSnapshot`: `deactivated` è additivo e la
    /// sintesi lo esigerebbe come chiave, facendo fallire il decode dell'intero layout salvato
    /// prima della feature. Encode resta sintetizzato.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        hasCustomTitle = try container.decode(Bool.self, forKey: .hasCustomTitle)
        currentDirectory = try container.decodeIfPresent(String.self, forKey: .currentDirectory)
        resume = try container.decodeIfPresent(ResumeBinding.self, forKey: .resume)
        pendingSince = try container.decodeIfPresent(Date.self, forKey: .pendingSince)
        deactivated = try container.decodeIfPresent(Bool.self, forKey: .deactivated) ?? false
    }
}
