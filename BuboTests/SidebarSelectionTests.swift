import Foundation
import Testing
@testable import Bubo

/// What the window's sidebar shows on the right (ADR 0013).
@MainActor
struct SidebarSelectionTests {
    @Test func theWindowOpensOnTheBrain() {
        #expect(HUDPresenter().selection == .brain)
    }

    @Test func showingASessionSelectsItsConversation() {
        let hud = HUDPresenter()
        let id = UUID()
        hud.show(session: id)
        #expect(hud.selection == .conversation("s-\(id)"))
    }

    @Test func openingTheFullChatSelectsTheQuestion() {
        let hud = HUDPresenter()
        let id = UUID()
        hud.show(question: id)
        #expect(hud.selection == .conversation("q-\(id)"))
    }

    @Test func theDraftsAreInLavoro() {
        let hud = HUDPresenter()
        hud.showDrafts()
        #expect(hud.selection == .work)
    }

    @Test func aSelectionMatchesItsListItem() {
        let id = UUID()
        let item = ConversationItem.session(id: id, title: "Login", project: URL(filePath: "/tmp/bubo"), date: .now,
                                            activity: nil)
        #expect(SidebarSelection.conversation(item.id) == .session(id))
    }
}
