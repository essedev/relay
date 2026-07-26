import Foundation

// Gruppi della sidebar: creazione, appartenenza, aspetto e spostamento del blocco. Estratto da
// `WorkspaceStore` per tenere il file principale entro il budget di dimensione (vedi CONVENTIONS).
//
// Due regole reggono tutto il file:
// 1. **L'appartenenza vive sul workspace** (`Workspace.groupID`). `groups` porta solo identità e
//    aspetto, quindi non esiste una lista di membri che possa divergere dall'array canonico.
// 2. **Un gruppo senza membri non esiste**: ogni operazione che può svuotarlo chiama
//    `pruneEmptyGroups`, come chiudere l'ultima tab chiude il workspace.

public extension WorkspaceStore {
    // MARK: - Query

    func group(_ id: UUID) -> WorkspaceGroup? {
        groups.first { $0.id == id }
    }

    /// I membri di un gruppo in ordine canonico (l'ordine con cui la card li mostra).
    func members(of groupID: UUID) -> [Workspace] {
        workspaces.filter { $0.groupID == groupID && !$0.archived }
    }

    // MARK: - Ciclo di vita

    /// Crea un gruppo attorno a dei workspace esistenti. I membri escono dal pin (dentro una card
    /// pinna la card) e da un eventuale gruppo precedente, e vengono compattati alla posizione del
    /// primo, così la card nasce dove stava la riga da cui sei partito. Ritorna `nil` se non c'è
    /// nemmeno un workspace valido: un gruppo vuoto non è rappresentabile.
    @discardableResult
    func createGroup(
        name: String, with workspaceIDs: [UUID], colorIndex: Int? = nil
    ) -> WorkspaceGroup? {
        let members = workspaceIDs.compactMap { id in workspaces.first { $0.id == id } }
        guard let first = members.first else { return nil }
        let group = WorkspaceGroup(
            name: name,
            colorIndex: colorIndex ?? WorkspaceGroup.defaultColorIndex(existing: groups.count)
        )
        groups.append(group)
        for member in members {
            member.groupID = group.id
            member.pinned = false
            member.archived = false
        }
        // Compatta dopo aver marcato tutti: `compact` legge `groupID`.
        compact(group.id, around: first.id)
        pruneEmptyGroups()
        return group
    }

    /// Scioglie il gruppo: i membri tornano righe libere **dove stanno** (l'ordine non cambia, si
    /// perde solo la card) e il gruppo sparisce.
    func ungroup(_ groupID: UUID) {
        for workspace in workspaces where workspace.groupID == groupID {
            workspace.groupID = nil
        }
        groups.removeAll { $0.id == groupID }
    }

    /// Mette un workspace in un gruppo. Esce dal pin e dall'archivio (dentro una card non si sta
    /// archiviati) e si posiziona prima di `targetID` fra i membri, o in fondo alla card se `nil`.
    /// No-op se il gruppo non esiste.
    func addToGroup(_ id: UUID, group groupID: UUID, before targetID: UUID? = nil) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              groups.contains(where: { $0.id == groupID }) else { return }
        let previous = workspace.groupID
        workspace.groupID = groupID
        workspace.pinned = false
        workspace.archived = false
        place(id, inGroup: groupID, before: targetID)
        if previous != nil, previous != groupID { pruneEmptyGroups() }
    }

    /// Cambia (o toglie) l'appartenenza **senza** toccare la posizione: la usa il drop della
    /// sidebar, che il posizionamento lo decide da sé (slot rilasciato) e lo applica dopo con
    /// `moveWorkspace`. Entrando in un gruppo il workspace lascia pin e archivio; uscendo, la card
    /// rimasta vuota muore. No-op se il gruppo indicato non esiste.
    func assignGroup(_ id: UUID, to groupID: UUID?) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.groupID != groupID else { return }
        if let groupID {
            guard groups.contains(where: { $0.id == groupID }) else { return }
            workspace.pinned = false
            workspace.archived = false
        }
        workspace.groupID = groupID
        pruneEmptyGroups()
    }

    /// Pin esplicito di una riga libera (il drop della sidebar sa già dove è finita, non gli serve
    /// un toggle). Dentro una card non ha effetto: lì a pinnare è il gruppo.
    func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.groupID == nil, workspace.pinned != pinned else { return }
        workspace.pinned = pinned
    }

    /// Tira un workspace fuori dal suo gruppo: resta dov'è nell'ordine canonico (subito sotto la
    /// card, se la card era sopra di lui) e la card muore se era l'ultimo membro.
    func removeFromGroup(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.groupID != nil else { return }
        workspace.groupID = nil
        pruneEmptyGroups()
    }

    // MARK: - Aspetto

    func renameGroup(_ groupID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let group = group(groupID) else { return }
        group.name = trimmed
    }

    func setGroupColor(_ groupID: UUID, colorIndex: Int) {
        guard WorkspaceGroup.colorIndices.contains(colorIndex) else { return }
        group(groupID)?.colorIndex = colorIndex
    }

    func toggleGroupCollapsed(_ groupID: UUID) {
        guard let group = group(groupID) else { return }
        group.collapsed.toggle()
    }

    /// Pin del blocco: la card sale in testa alla sidebar con i suoi membri.
    func setGroupPinned(_ groupID: UUID, _ pinned: Bool) {
        group(groupID)?.pinned = pinned
    }

    func toggleGroupPin(_ groupID: UUID) {
        guard let group = group(groupID) else { return }
        group.pinned.toggle()
    }

    // MARK: - Posizione

    /// Sposta la card intera: tutti i membri, nel loro ordine, prima di `targetID` (un workspace di
    /// primo livello) o in fondo se `nil`. Il target è un workspace perché l'ordine canonico non
    /// conosce i gruppi: per posare una card prima di un'altra si passa il primo membro di quella.
    func moveGroup(_ groupID: UUID, before targetID: UUID?) {
        let members = members(of: groupID)
        guard let first = members.first, first.id != targetID else { return }
        moveWorkspace(first.id, before: targetID)
        var previous = first.id
        for member in members.dropFirst() {
            moveWorkspace(member.id, after: previous)
            previous = member.id
        }
    }

    /// Come `moveGroup(_:before:)` ma dopo `targetID`.
    func moveGroup(_ groupID: UUID, after targetID: UUID) {
        let members = members(of: groupID)
        guard let first = members.first, first.id != targetID else { return }
        moveWorkspace(first.id, after: targetID)
        var previous = first.id
        for member in members.dropFirst() {
            moveWorkspace(member.id, after: previous)
            previous = member.id
        }
    }
}

extension WorkspaceStore {
    /// Cancella i gruppi rimasti senza membri. Chiamato da ogni operazione che può svuotarne uno
    /// (uscita, archiviazione, chiusura del workspace).
    func pruneEmptyGroups() {
        let alive = Set(workspaces.compactMap(\.groupID))
        groups.removeAll { !alive.contains($0.id) }
    }

    /// Porta il workspace in mezzo ai suoi nuovi compagni di card: prima di `targetID` se è un
    /// membro, altrimenti in fondo al blocco. Serve perché l'array canonico è piatto: senza questo
    /// il workspace resterebbe alla sua vecchia posizione e la card lo pescherebbe comunque (la
    /// proiezione è robusta), ma il drag e il bump lavorerebbero su un ordine che non somiglia a
    /// quello a schermo.
    func place(_ id: UUID, inGroup groupID: UUID, before targetID: UUID?) {
        let siblings = workspaces.filter { $0.groupID == groupID && $0.id != id }
        if let targetID, siblings.contains(where: { $0.id == targetID }) {
            workspaces.move(id, before: targetID)
        } else if let last = siblings.last {
            workspaces.move(id, after: last.id)
        }
    }

    /// Compatta i membri di un gruppo in un blocco contiguo, ancorato alla posizione di `anchorID`.
    func compact(_ groupID: UUID, around anchorID: UUID) {
        let members = workspaces.filter { $0.groupID == groupID }
        guard members.contains(where: { $0.id == anchorID }) else { return }
        var previous = anchorID
        for member in members where member.id != anchorID {
            workspaces.move(member.id, after: previous)
            previous = member.id
        }
    }
}
