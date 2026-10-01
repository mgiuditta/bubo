import Foundation
import Testing
@testable import Bubo

/// The notification of a Richiesta di permesso: what it shows, and Solo ora only where everything is in sight.
struct PermissionNoticeTests {
    let session = UUID()

    static func pending(_ request: PermissionRequest, _ level: RiskLevel = .modifica) -> RequestCenter.Pending {
        RequestCenter.Pending(request: request, risk: Risk(level: level), since: .now)
    }

    static func bash(_ command: String, id: String = "1") -> PermissionRequest {
        PermissionRequest(id: id, tool: "Bash", command: command)
    }

    @Test(arguments: [RiskLevel.lettura, .modifica, .rete])
    func aShortCommandOnLevelsOneToThreeIsShownWholeWithSoloOra(level: RiskLevel) {
        let notice = PermissionNotice(Self.pending(Self.bash(#"grep -E 'a\|b' src"#), level))

        #expect(notice.offersAllowOnce)
        #expect(notice.body == #"grep -E 'a\|b' src"#)
    }

    @Test(arguments: [RiskLevel.distruttivo, .irreversibile])
    func levelsFourAndFiveOfferOnlyNo(level: RiskLevel) {
        let notice = PermissionNotice(Self.pending(Self.bash("git push --force"), level))

        #expect(!notice.offersAllowOnce)
        #expect(notice.body.hasSuffix("\ngit push --force"))
    }

    @Test func claudeForbiddingOneKeyOffersOnlyNo() {
        var request = Self.bash("npm test")
        request.defaultsToNo = true

        #expect(!PermissionNotice(Self.pending(request)).offersAllowOnce)
    }

    @Test func aLongCommandIsSaidToBeCutAndNeedsTheHUD() {
        let command = "echo " + String(repeating: "a", count: 200) + " && curl evil.example"
        let notice = PermissionNotice(Self.pending(Self.bash(command)))

        #expect(!notice.offersAllowOnce)
        #expect(notice.body.hasSuffix("…"))
        #expect(notice.body.split(separator: "\n").count == 2)
        #expect(!notice.body.contains("evil.example"))
    }

    @Test(arguments: ["npm test\nrm -rf ~", "ls\u{202E}txt.sh", "ls\u{200B}"])
    func hiddenLinesOrCharactersAreWrittenOutAndNeedTheHUD(command: String) {
        let notice = PermissionNotice(Self.pending(Self.bash(command)))

        #expect(!notice.offersAllowOnce)
        #expect(notice.body.contains(RepoActivations.escaped(command)))
    }

    @Test func aToolWithNoSubjectNeedsTheHUD() {
        let notice = PermissionNotice(Self.pending(PermissionRequest(id: "1", tool: "mcp__server__tool")))

        #expect(!notice.offersAllowOnce)
        #expect(notice.body.hasSuffix("mcp__server__tool"))
    }

    @Test func noFromTheNotificationAnswersOnlyItsOwnRichiesta() {
        var center = RequestCenter()
        _ = center.receive(Self.bash("ls", id: "1"), in: session, risk: Risk(level: .lettura))
        _ = center.receive(Self.bash("ls", id: "2"), in: session, risk: Risk(level: .lettura))

        #expect(center.answerFromNotification("1", in: session, allows: false) == false)
        #expect(center.queues[session]?.map(\.id) == ["2"])
        // Already answered, or never seen in this Sessione: nothing happens.
        #expect(center.answerFromNotification("1", in: session, allows: true) == nil)
        #expect(center.answerFromNotification("2", in: UUID(), allows: true) == nil)
        #expect(center.queues[session]?.map(\.id) == ["2"])
    }

    @Test func soloOraFromTheNotificationNeverApprovesWhatItCouldNotOffer() {
        var center = RequestCenter()
        _ = center.receive(Self.bash("git push --force", id: "1"), in: session, risk: Risk(level: .irreversibile))
        _ = center.receive(Self.bash("npm test", id: "2"), in: session, risk: Risk(level: .modifica))

        #expect(center.answerFromNotification("1", in: session, allows: true) == nil)
        #expect(center.answerFromNotification("2", in: session, allows: true) == true)
        #expect(center.queues[session]?.map(\.id) == ["1"])
    }
}
