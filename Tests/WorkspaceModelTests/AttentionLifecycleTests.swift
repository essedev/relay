import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// Ciclo di vita del marker "in sospeso" (visto ma mai ripreso): dismiss esplicito, decadenza
// opzionale, persistenza nel layout. La transizione unseen -> pending vive nel composition root
// (interazione col terminale); qui si testano le operazioni dello store.

@Test func dismissClearsAnyAttentionLevel() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "w")
    let tab = workspace.tabs[0]

    tab.attention = .pending
    #expect(store.dismissAttention(tab.id))
    #expect(tab.attention == .none)

    tab.attention = .unseen
    #expect(store.dismissAttention(tab.id))
    #expect(tab.attention == .none)

    // Niente da spegnere o tab inesistente -> no-op.
    #expect(!store.dismissAttention(tab.id))
    #expect(!store.dismissAttention(UUID()))
}

@Test func decayClearsOnlyOldPending() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "w")
    let old = workspace.tabs[0]
    let recent = store.addTab(to: workspace)
    let unseen = store.addTab(to: workspace)

    old.attention = .pending
    old.lastEventAt = Date(timeIntervalSince1970: 100)
    recent.attention = .pending
    recent.lastEventAt = Date(timeIntervalSince1970: 900)
    // La decadenza tocca solo i sospesi: il segnale forte non scade mai da solo.
    unseen.attention = .unseen
    unseen.lastEventAt = Date(timeIntervalSince1970: 100)

    let decayed = store.decayPending(olderThan: Date(timeIntervalSince1970: 500))
    #expect(decayed == 1)
    #expect(old.attention == .none)
    #expect(recent.attention == .pending)
    #expect(unseen.attention == .unseen)
}

/// Un sospeso senza timestamp (mai successo via reducer, ma difensivo) decade come "vecchissimo".
@Test func decayTreatsMissingTimestampAsAncient() {
    let store = WorkspaceStore()
    let tab = store.createWorkspace(name: "w").tabs[0]
    tab.attention = .pending
    tab.lastEventAt = nil
    #expect(store.decayPending(olderThan: Date(timeIntervalSince1970: 0)) == 1)
    #expect(tab.attention == .none)
}

// MARK: - Persistence

@Test func snapshotPersistsPendingWithTimestamp() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "w")
    let tab = workspace.tabs[0]
    tab.attention = .pending
    tab.lastEventAt = Date(timeIntervalSince1970: 42)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())
    let restoredTab = restored.workspaces[0].tabs[0]
    #expect(restoredTab.attention == .pending)
    #expect(restoredTab.lastEventAt == Date(timeIntervalSince1970: 42)) // età per dashboard/decay
}

/// `unseen` degrada a `pending` attraverso il riavvio: al restore il segnale forte sarebbe
/// stantio (niente float/ring fantasma), ma il completamento mai ripreso non si perde.
@Test func unseenSurvivesRestartAsPending() {
    let store = WorkspaceStore()
    let tab = store.createWorkspace(name: "w").tabs[0]
    tab.attention = .unseen
    tab.lastEventAt = Date(timeIntervalSince1970: 7)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())
    #expect(restored.workspaces[0].tabs[0].attention == .pending)
}

@Test func noAttentionMeansNoPendingSince() {
    let store = WorkspaceStore()
    let tab = store.createWorkspace(name: "w").tabs[0]
    tab.attention = .none
    tab.lastEventAt = Date(timeIntervalSince1970: 7) // evento recente ma nessun marker

    let snap = store.snapshot()
    #expect(snap.workspaces[0].tabs[0].pendingSince == nil)
}
