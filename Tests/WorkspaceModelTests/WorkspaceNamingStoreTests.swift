import Foundation
import Testing
@testable import WorkspaceModel

// Lato store della nomina automatica: chi può sovrascrivere il nome di un workspace e chi no. La
// decisione di *quando* chiedere un nome sta in `Core` (testata lì); qui si verifica la guardia che
// protegge un nome scelto a mano e lo stato "nomina in corso" che la sidebar fa pulsare.

@MainActor
@Test func generatedNameAppliesToADefaultWorkspace() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "Workspace 1")
    #expect(workspace.nameOrigin == .default)

    #expect(store.applyGeneratedName(workspace.id, to: "Yellow Hub"))
    #expect(workspace.name == "Yellow Hub")
    #expect(workspace.nameOrigin == .generated)
}

@MainActor
@Test func generatedNameNeverOverwritesAUserName() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "Workspace 1")
    store.renameWorkspace(workspace.id, to: "Cliente X")

    #expect(!store.applyGeneratedName(workspace.id, to: "Yellow Hub"))
    #expect(workspace.name == "Cliente X")
    #expect(workspace.nameOrigin == .user)
}

/// One-shot: un nome già generato non viene rifatto da solo (solo "Regenerate name" lo rimette in
/// gioco), altrimenti l'app litigherebbe col nome che ha appena scelto.
@MainActor
@Test func generatedNameIsNotReappliedTwice() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "Workspace 1")
    store.applyGeneratedName(workspace.id, to: "Yellow Hub")

    #expect(!store.applyGeneratedName(workspace.id, to: "Something Else"))
    #expect(workspace.name == "Yellow Hub")
}

@MainActor
@Test func generatedNameRejectsBlankAndUnknownWorkspace() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "Workspace 1")

    #expect(!store.applyGeneratedName(workspace.id, to: "   "))
    #expect(workspace.name == "Workspace 1")
    #expect(workspace.nameOrigin == .default)
    #expect(!store.applyGeneratedName(UUID(), to: "Yellow Hub"))
}

@MainActor
@Test func generatedNameIsTrimmed() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "Workspace 1")

    #expect(store.applyGeneratedName(workspace.id, to: "  Yellow Hub\n"))
    #expect(workspace.name == "Yellow Hub")
}

/// "Regenerate name": rimette in gioco anche un nome scelto a mano (l'utente l'ha chiesto), senza
/// toccare il nome corrente finché il nuovo non arriva.
@MainActor
@Test func markNameRegenerableReopensAUserName() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "Workspace 1")
    store.renameWorkspace(workspace.id, to: "Cliente X")

    store.markNameRegenerable(workspace.id)
    #expect(workspace.nameOrigin == .default)
    #expect(workspace.name == "Cliente X")
    #expect(store.applyGeneratedName(workspace.id, to: "Yellow Hub"))
}

@MainActor
@Test func namingFlagTracksTheRequestInFlight() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "Workspace 1")
    #expect(!workspace.isNaming)

    store.setNaming(workspace.id, true)
    #expect(workspace.isNaming)
    store.setNaming(workspace.id, false)
    #expect(!workspace.isNaming)
}

/// Volatile: il pulsare del nome descrive una richiesta viva, e una richiesta non sopravvive a un
/// riavvio. Se finisse nello snapshot, un workspace ripartirebbe pulsando per sempre.
@MainActor
@Test func namingFlagDoesNotSurviveASnapshotRoundTrip() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "Workspace 1")
    store.setNaming(workspace.id, true)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())
    #expect(restored.workspaces.allSatisfy { !$0.isNaming })
}
