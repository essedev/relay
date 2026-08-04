import Foundation

// Posizione delle cose nella lista: dove si sposta un workspace (drag, bump) e **dove nasce** una
// cosa nuova. Estratto da `WorkspaceStore` per tenere il file principale entro il budget di
// dimensione (vedi CONVENTIONS). Tutto posizionale e puro: l'ordine canonico è `workspaces`, la
// sidebar ne è una proiezione (`orderedWorkspaces`).

public extension WorkspaceStore {
    /// Inserisce il workspace `id` immediatamente **prima** di `targetID` nell'ordine canonico
    /// (drag & drop nella sidebar, o bump da attività). `targetID == nil` (o non trovato) lo porta
    /// in fondo. No-op se gli id coincidono o `id` non esiste. La sidebar mostra
    /// `orderedWorkspaces` (canonico, pinned in testa): l'ancora giusta per lo slot visivo la
    /// sceglie `SidebarDrop`.
    func moveWorkspace(_ id: UUID, before targetID: UUID?) {
        workspaces.move(id, before: targetID)
    }

    /// Inserisce il workspace `id` immediatamente **dopo** `targetID` nell'ordine canonico. Serve
    /// al drag & drop quando si rilascia in fondo al blocco pinned: lì `before` prenderebbe il
    /// primo del segmento successivo, che in ordine canonico non è contiguo, producendo un no-op.
    /// No-op se gli id coincidono o `id` non esiste.
    func moveWorkspace(_ id: UUID, after targetID: UUID) {
        workspaces.move(id, after: targetID)
    }

    /// Inserisce la tab `tabID` immediatamente **prima** di `targetID` nell'ordine del workspace
    /// (drag & drop nella tab bar). `targetID == nil` (o non trovato) la porta in fondo. La tab bar
    /// non ha float: l'ordine è unico, quindi l'indicatore riflette sempre l'esito. La selezione
    /// corrente non cambia (spostare non è selezionare).
    func moveTab(_ tabID: UUID, before targetID: UUID?, in workspace: Workspace) {
        workspace.moveTab(tabID, before: targetID)
    }

    /// Sposta una tab in un **nuovo** workspace preservando la sessione viva: sposta lo stesso
    /// oggetto `Tab` (stesso `Tab.id`), quindi la surface legata per id resta intatta - nessun
    /// teardown del pty, il lavoro dentro la tab non si tocca. Il nuovo workspace eredita la cwd
    /// della tab come `rootPath` e nasce `.default` (eleggibile alla nomina automatica: il nome
    /// passato è un placeholder). Diventa il selezionato, con la tab spostata attiva.
    ///
    /// **No-op se la tab è l'unica del suo workspace** (sarebbe solo un rename del workspace, e
    /// svuoterebbe l'origine) o se `tabID` non esiste lì. Ritorna il nuovo workspace, o `nil` se
    /// no-op. L'append + il remove avvengono nella stessa mutazione sincrona, così la tab è sempre
    /// presente in `store.workspaces` a ogni istante osservabile: il reconcile delle surface
    /// (`retain` su tutti gli id) non la sfratta mai (vedi TerminalHostUI).
    @discardableResult
    func moveTabToNewWorkspace(
        _ tabID: UUID,
        from workspace: Workspace,
        name: String,
        nameOrigin: NameOrigin = .default
    ) -> Workspace? {
        guard workspace.tabs.count > 1,
              let tab = workspace.tabs.first(where: { $0.id == tabID }) else { return nil }
        // Nella finestra del workspace d'origine, non nella key: l'azione parte dalla sua strip,
        // e un nuovo workspace che finisse in un'altra finestra violerebbe la partizione (sidebar
        // che non lo lista, stessa surface montata in due aree).
        // Nasce accanto al workspace d'origine e nel suo gruppo (stessa regola di
        // `createWorkspace`): la tab estratta resta dove stavi lavorando. Non se l'origine è
        // archiviato: lì l'ancora non ha una posizione visibile in lista.
        let anchored = !workspace.archived
        let newWorkspace = Workspace(
            windowID: workspace.windowID,
            name: name,
            nameOrigin: nameOrigin,
            rootPath: tab.currentDirectory,
            groupID: anchored ? workspace.groupID : nil,
            tabs: [tab],
            selectedTabID: tab.id
        )
        workspaces.append(newWorkspace)
        if anchored { workspaces.move(newWorkspace.id, after: workspace.id) }
        workspace.removeTab(tabID)
        windows.first { $0.id == workspace.windowID }?.selectedWorkspaceID = newWorkspace.id
        return newWorkspace
    }
}

extension WorkspaceStore {
    /// Porta il workspace in cima al **proprio contenitore** ("bump" da attività non vista: un
    /// completamento o una richiesta di input arrivati mentre non lo guardavi). È un vero riordino
    /// persistente, non un float derivato: la posizione guadagnata resta finché non la scavalca un
    /// altro bump o non la sposti a mano. No-op se è già in testa, o se è pinned/archiviato (i
    /// pinned sono già fissi in cima, gli archiviati fuori dalla lista).
    ///
    /// Il contenitore è il gruppo, se ne ha uno: un membro sale in cima **alla sua card** e la card
    /// non si muove (un gruppo sta dove l'hai messo, salvo pin o drag). Un workspace libero sale in
    /// cima al primo elemento non pinned della sua sidebar: se quell'elemento è un gruppo, si
    /// ancora al suo primo membro e finisce quindi **sopra** la card.
    func bumpWorkspaceToTop(_ id: UUID) {
        // In cima **alla sua sidebar**: il bump riordina dentro la finestra che lo mostra, non lo
        // strappa in testa alla lista globale (che nessuno vede intera).
        guard let ws = workspaces.first(where: { $0.id == id }), !ws.archived else { return }
        if let groupID = ws.groupID {
            guard let first = workspaces.first(where: {
                $0.groupID == groupID && $0.windowID == ws.windowID && !$0.archived
            }), first.id != id else { return }
            moveWorkspace(id, before: first.id)
            return
        }
        guard !ws.pinned,
              let anchor = sidebarItems(in: ws.windowID).first(where: { !$0.pinned })?
              .workspaces.first,
              anchor.id != id else { return }
        moveWorkspace(id, before: anchor.id)
    }

    /// Il workspace dopo il quale nasce un workspace nuovo: quello selezionato nella finestra che
    /// lo ospita. Il nuovo ne eredita anche il **gruppo**, quindi creare dentro una card crea
    /// dentro quella card (uscirne è un drag, come entrarci).
    ///
    /// `nil` (= in fondo, il vecchio comportamento) se la finestra non ha selezione o se il
    /// selezionato è **archiviato**: gli archiviati stanno fuori da `orderedWorkspaces`, quindi
    /// ancorarcisi darebbe una posizione che nella lista non corrisponde a niente.
    /// L'ancora **pinned** va invece bene: il nuovo non è pinned, quindi il segmento non pinned se
    /// lo trova in testa - la riga più vicina possibile a quella da cui l'hai creato.
    func insertionAnchor(in windowID: UUID) -> Workspace? {
        guard let selected = windows.first(where: { $0.id == windowID })?.selectedWorkspaceID,
              let workspace = workspaces.first(where: { $0.id == selected }),
              workspace.windowID == windowID, !workspace.archived else { return nil }
        return workspace
    }
}
