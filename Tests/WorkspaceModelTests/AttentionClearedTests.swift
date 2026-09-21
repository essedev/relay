import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// `onAttentionCleared` è il simmetrico di `onNotifiableTransition`: quando la tab non aspetta più
// niente, il composition root ritira il banner macOS. Senza, il centro notifiche accumulava una
// voce per ogni transizione di ogni tab mai aperta, e cliccarne una mezza giornata dopo riportava
// in vista una conversazione già letta.

/// Una tab nascosta con un completamento non visto: il caso in cui un banner esiste davvero.
@MainActor
private func fixtureWithUnseenTab() -> AgentFixture {
    let fixture = makeAgentFixture()
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID, state: .running, at: Date(timeIntervalSince1970: 1)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(fixture.hiddenTab.attention == .unseen)
    return fixture
}

@Test @MainActor func markingSeenClearsTheNotificationOnce() {
    let fixture = fixtureWithUnseenTab()
    var cleared: [UUID] = []
    fixture.store.onAttentionCleared = { cleared.append($0) }

    fixture.store.markSeen(fixture.hiddenTab.id)
    #expect(cleared == [fixture.hiddenTab.id])

    // Già declassata: non c'è più niente da ritirare, e ripetere la chiamata non deve emettere.
    fixture.store.markSeen(fixture.hiddenTab.id)
    #expect(cleared.count == 1)
}

@Test @MainActor func aTabWithoutAMarkerNeverClears() {
    let fixture = makeAgentFixture()
    var cleared: [UUID] = []
    fixture.store.onAttentionCleared = { cleared.append($0) }
    fixture.store.markSeen(fixture.hiddenTab.id)
    #expect(cleared.isEmpty)
}

@Test @MainActor func dismissAndDecayClearTheNotification() {
    let fixture = fixtureWithUnseenTab()
    var cleared: [UUID] = []
    fixture.store.onAttentionCleared = { cleared.append($0) }

    #expect(fixture.store.dismissAttention(fixture.hiddenTab.id))
    #expect(cleared == [fixture.hiddenTab.id])

    // Un sospeso che decade è l'altro modo in cui il marker si spegne da solo.
    fixture.hiddenTab.attention = .pending
    fixture.hiddenTab.attentionSince = Date(timeIntervalSince1970: 0)
    #expect(fixture.store.decayPending(olderThan: Date(timeIntervalSince1970: 100)) == 1)
    #expect(cleared.count == 2)
}

/// "Mark as Read" spegne e ritira; "Mark as Unread" ri-alza il segnale, ma **non** manda una
/// notifica nuova (nasce da un flag manuale, non da un evento), quindi non c'è niente da ritirare.
@Test @MainActor func toggleUnreadClearsOnlyWhenItTurnsTheMarkerOff() {
    let fixture = fixtureWithUnseenTab()
    var cleared: [UUID] = []
    fixture.store.onAttentionCleared = { cleared.append($0) }

    fixture.store.toggleUnread(fixture.hiddenTab.id) // unseen -> none
    #expect(cleared == [fixture.hiddenTab.id])

    fixture.store.toggleUnread(fixture.hiddenTab.id) // none -> unseen
    #expect(cleared.count == 1)
}

/// La tab non esiste più: un banner che la riapre porterebbe da nessuna parte.
@Test @MainActor func closingATabClearsItsNotification() throws {
    let fixture = makeAgentFixture()
    let workspace = try #require(fixture.store.workspaces.first { $0.name == "B" })
    let extra = fixture.store.addTab(to: workspace)
    var cleared: [UUID] = []
    fixture.store.onAttentionCleared = { cleared.append($0) }

    fixture.store.closeTab(extra.id, in: workspace)
    #expect(cleared == [extra.id])
}
