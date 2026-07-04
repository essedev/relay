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

    // Il decay misura da `attentionSince` (da quando è in sospeso), non dall'ultimo evento.
    old.attention = .pending
    old.attentionSince = Date(timeIntervalSince1970: 100)
    recent.attention = .pending
    recent.attentionSince = Date(timeIntervalSince1970: 900)
    // La decadenza tocca solo i sospesi: il segnale forte non scade mai da solo.
    unseen.attention = .unseen
    unseen.attentionSince = Date(timeIntervalSince1970: 100)

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
    tab.attentionSince = nil
    tab.lastEventAt = nil
    #expect(store.decayPending(olderThan: Date(timeIntervalSince1970: 0)) == 1)
    #expect(tab.attention == .none)
}

/// Regression (bug major): un completamento mai visto, riaperto molto dopo la soglia di decadenza,
/// non deve essere spazzato al primo boot. Il clock del marker riparte dal restore, non
/// dall'evento.
@Test func restoredMarkerSurvivesImmediateDecay() {
    let store = WorkspaceStore()
    let tab = store.createWorkspace(name: "w").tabs[0]
    tab.attention = .unseen
    tab.lastEventAt = Date(timeIntervalSince1970: 100) // completato tantissimo tempo fa

    let restored = WorkspaceStore()
    let boot = Date(timeIntervalSince1970: 1_000_000)
    restored.restore(from: store.snapshot(), now: boot)
    let rtab = restored.workspaces[0].tabs[0]
    #expect(rtab.attention == .pending)

    // Decay al boot con soglia 12h: il marker è "in sospeso da ora", quindi sopravvive.
    #expect(restored.decayPending(olderThan: boot.addingTimeInterval(-12 * 3600)) == 0)
    #expect(rtab.attention == .pending)
}

/// L'interazione declassa unseen -> pending e "resetta" il clock del sospeso al momento della
/// vista.
@Test func markSeenDegradesAndStampsClock() {
    let tab = Tab(attention: .unseen, lastEventAt: Date(timeIntervalSince1970: 100))
    let seenAt = Date(timeIntervalSince1970: 500)
    tab.markSeen(at: seenAt)
    #expect(tab.attention == .pending)
    #expect(tab.attentionSince == seenAt)

    // No-op se non è unseen: guardare un pending non cambia il suo clock.
    tab.markSeen(at: Date(timeIntervalSince1970: 999))
    #expect(tab.attentionSince == seenAt)
}

// MARK: - Persistence

@Test func snapshotPersistsPendingWithTimestamp() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "w")
    let tab = workspace.tabs[0]
    tab.attention = .pending
    tab.attentionSince = Date(timeIntervalSince1970: 42)
    tab.lastEventAt = Date(timeIntervalSince1970: 42)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())
    let restoredTab = restored.workspaces[0].tabs[0]
    #expect(restoredTab.attention == .pending)
    #expect(restoredTab.lastEventAt == Date(timeIntervalSince1970: 42)) // età evento (dashboard)
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
