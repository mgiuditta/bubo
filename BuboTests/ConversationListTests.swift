import Foundation
import Testing
@testable import Bubo

/// The Domande and the Sessioni in one list of the sidebar, by day.
struct ConversationListTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    /// Saturday 3 October 2026, 08:00 GMT.
    private let now = Date(timeIntervalSince1970: 1_791_014_400)

    private func question(_ title: String, hoursAgo: Double, session: UUID? = nil) -> ArchivedQuestion {
        ArchivedQuestion(id: UUID(), title: title, date: now.addingTimeInterval(-hoursAgo * 3600), turns: [],
                         sessionID: session)
    }

    @Test func itemsGoInDayGroupsNewestFirst() {
        let items = [question("Vecchia", hoursAgo: 24 * 30), question("Ieri", hoursAgo: 20),
                     question("Oggi", hoursAgo: 1), question("Martedì", hoursAgo: 24 * 4)].map(ConversationItem.question)
        let groups = ConversationList.groups(of: items, now: now, calendar: calendar)
        #expect(groups.map(\.group) == [.today, .yesterday, .thisWeek, .earlier])
        #expect(groups.map { $0.items.map(\.title) } == [["Oggi"], ["Ieri"], ["Martedì"], ["Vecchia"]])
    }

    @Test func emptyGroupsAreLeftOut() {
        let groups = ConversationList.groups(of: [.question(question("Oggi", hoursAgo: 1))], now: now, calendar: calendar)
        #expect(groups.map(\.group) == [.today])
    }

    @Test func domandeAndSessioniAreOneListNewestFirst() {
        var session = Session(id: UUID(), title: "Login che scade", project: URL(filePath: "/tmp/bubo"), activity: .attende)
        session.activitySince = now.addingTimeInterval(-1800)
        let items = ConversationList.items(questions: [question("Meteo", hoursAgo: 2)], sessions: [session], cli: [],
                                           includingCLI: false)
        #expect(items.map(\.title) == ["Login che scade", "Meteo"])
        #expect(items.first == .session(id: session.id, title: "Login che scade", project: URL(filePath: "/tmp/bubo"),
                                        date: now.addingTimeInterval(-1800), activity: .attende))
    }

    @Test func theCommandLineShowsOnlyWhenAsked() {
        let cli = CLIConversation(id: "abc", title: "Da terminale", folder: nil, branch: nil, lastModified: now)
        #expect(ConversationList.items(questions: [], sessions: [], cli: [cli], includingCLI: false).isEmpty)
        #expect(ConversationList.items(questions: [], sessions: [], cli: [cli], includingCLI: true).map(\.id) == ["c-abc"])
    }

    @Test func aQuestionThatBecameASessionStaysListed() {
        let items = ConversationList.items(questions: [question("Login", hoursAgo: 1, session: UUID())], sessions: [],
                                           cli: [], includingCLI: false)
        #expect(items.map(\.title) == ["Login"])
    }
}
