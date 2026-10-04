import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import Bubo

@MainActor
struct PanelStatusTests {
    private static func session(_ activity: Session.Activity, phase: Session.Phase = .aperta) -> Session {
        var session = Session(id: UUID(), title: "s", project: URL(filePath: "/tmp"), activity: activity)
        session.phase = phase
        return session
    }

    @Test func nothingToSayMeansNoPill() {
        let sessions = [Self.session(.lavora), Self.session(.ferma)]
        #expect(PanelStatus.status(sessions: sessions, hasUnseenOutcome: false, questionFailed: false) == nil)
        #expect(PanelStatus.status(sessions: [], hasUnseenOutcome: false, questionFailed: true) == nil)
        #expect(PanelStatus.sessionsDescription(of: sessions) == nil)
    }

    @Test func attendeTeComesFirstAndLeadsToItsFirstSessione() {
        let first = Self.session(.attende)
        let sessions = [Self.session(.errore), first, Self.session(.attende)]
        let status = PanelStatus.status(sessions: sessions, hasUnseenOutcome: true, questionFailed: false)
        #expect(status == .waiting(count: 2, session: first.id))
        #expect(status?.showsLume == true)
        #expect(status?.text == String(localized: "\(2) ti attendono"))
        #expect(status?.accessibilityLabel == String(localized: "\(2) Sessioni ti attendono"))
    }

    @Test func errorsComeBeforeTheDomandaWithoutTheLume() {
        let failing = Self.session(.errore)
        let status = PanelStatus.status(sessions: [failing], hasUnseenOutcome: true, questionFailed: false)
        #expect(status == .failing(count: 1, session: failing.id))
        #expect(status?.showsLume == false)
    }

    @Test func sessioniNoLongerLiveDoNotCount() {
        let sessions = [Self.session(.attende, phase: .fusa), Self.session(.errore, phase: .archiviata)]
        #expect(PanelStatus.status(sessions: sessions, hasUnseenOutcome: false, questionFailed: false) == nil)
        #expect(PanelStatus.sessionsDescription(of: sessions) == nil)
    }

    @Test(arguments: [(false, PanelStatus.answerReady), (true, .questionFailed)])
    func anUnseenDomandaSaysHowItEnded(failed: Bool, expected: PanelStatus) {
        #expect(PanelStatus.status(sessions: [], hasUnseenOutcome: true, questionFailed: failed) == expected)
        #expect(expected.help == String(localized: "Riapre la Domanda nel Panel"))
    }

    @Test func theOrbValueTellsWaitingAndFailingSessioni() {
        let sessions = [Self.session(.attende), Self.session(.attende), Self.session(.errore)]
        #expect(PanelStatus.sessionsDescription(of: sessions)
            == "\(String(localized: "\(2) Sessioni ti attendono")), \(String(localized: "\(1) Sessioni in Errore"))")
    }

    @Test func anAnswerEndingWithTheBubbleClosedIsUnseenUntilItOpens() {
        let bubble = PanelBubble()
        bubble.follow(isAnswering: true, isSpeaking: false, panelIsVisible: true)
        bubble.close()
        bubble.follow(isAnswering: false, isSpeaking: false, panelIsVisible: true)
        #expect(bubble.hasUnseenOutcome)
        bubble.open(focus: .none)
        #expect(!bubble.hasUnseenOutcome)
    }

    @Test func anAnswerEndingInTheOpenBubbleOrInTheHUDIsSeen() {
        let bubble = PanelBubble()
        bubble.follow(isAnswering: true, isSpeaking: false, panelIsVisible: true)
        bubble.follow(isAnswering: false, isSpeaking: false, panelIsVisible: true)
        #expect(!bubble.hasUnseenOutcome)

        let hidden = PanelBubble()
        hidden.follow(isAnswering: true, isSpeaking: false, panelIsVisible: false)
        hidden.follow(isAnswering: false, isSpeaking: false, panelIsVisible: false)
        #expect(!hidden.hasUnseenOutcome)
    }

    @Test func aNewDomandaOrTheHUDClearsTheUnseenAnswer() {
        let bubble = PanelBubble()
        bubble.follow(isAnswering: true, isSpeaking: false, panelIsVisible: false)
        bubble.follow(isAnswering: false, isSpeaking: false, panelIsVisible: true)
        #expect(bubble.hasUnseenOutcome)
        bubble.markOutcomeSeen()
        #expect(!bubble.hasUnseenOutcome)
    }

    @Test func theWindowNeverTakesTheKeyboard() {
        let window = PanelStatusWindow.make(content: EmptyView())
        #expect(window.styleMask.contains(.nonactivatingPanel))
        #expect(!window.canBecomeKey)
        #expect(!window.hidesOnDeactivate)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.ignoresCycle))
        #expect(window.accessibilityLabel() == String(localized: "Stato del Panel"))
    }

    private static let screen = CGRect(x: 0, y: 0, width: 1470, height: 920)
    private static let pill = CGSize(width: 120, height: PanelStatusLayout.height)

    @Test func inTheBottomRightCornerThePillSitsLeftOfTheOrb() {
        let panel = CGRect(x: Self.screen.maxX - 112, y: 0, width: 112, height: 112)
        let frame = PanelStatusLayout.frame(ofSize: Self.pill, besidePanel: panel, in: .bottomRight,
                                            visibleFrame: Self.screen)
        #expect(frame.maxX < panel.midX)
        #expect(frame.midY == panel.midY)
        // Outside the click circle of 37 pt.
        #expect(panel.midX - frame.maxX > PanelSize.reduced.clickRadius)
    }

    @Test(arguments: PanelZone.allCases)
    func thePillStaysOnScreenAndTowardTheCenter(zone: PanelZone) {
        let panel = CGRect(x: zone == .left || zone == .topLeft || zone == .bottomLeft ? 0 : 600, y: 0,
                           width: 112, height: 112)
        let frame = PanelStatusLayout.frame(ofSize: Self.pill, besidePanel: panel, in: zone, visibleFrame: Self.screen)
        #expect(Self.screen.contains(frame))
        #expect(frame.size == Self.pill)
    }

    @Test func theDropHintSaysWhatADropDoes() {
        #expect(PanelStatus.dropHint.text == String(localized: "Rilascia: trascrivo e salvo nel cervello"))
        #expect(!PanelStatus.dropHint.showsLume)
    }
}
