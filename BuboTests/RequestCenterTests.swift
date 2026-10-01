import Foundation
import Testing
@testable import Bubo

struct RequestCenterTests {
    let session = UUID()
    let other = UUID()

    static func bash(_ id: String, _ command: String) -> PermissionRequest {
        PermissionRequest(id: id, tool: "Bash", command: command)
    }

    @Test func aCriticalPathIsRefusedWithoutAsking() {
        var center = RequestCenter()
        #expect(center.receive(Self.bash("1", "rm -rf /"), in: session, risk: .critical) == .denied)
        #expect(center.queues.isEmpty)
    }

    @Test func requestsQueuePerSessioneAndTheOldestTakesTheKeyboard() {
        var center = RequestCenter()
        let start = Date(timeIntervalSince1970: 0)
        _ = center.receive(Self.bash("a", "npm test"), in: session, risk: Risk(level: .modifica), at: start.addingTimeInterval(2))
        _ = center.receive(Self.bash("b", "npm run lint"), in: session, risk: Risk(level: .modifica), at: start.addingTimeInterval(3))
        _ = center.receive(Self.bash("c", "ls"), in: other, risk: Risk(level: .lettura), at: start.addingTimeInterval(1))

        #expect(center.queues[session]?.map(\.id) == ["a", "b"])
        #expect(center.first?.id == "c")
        #expect(center.answer("c", in: other, with: .deny) == false)
        #expect(center.first?.id == "a")
        #expect(center.answer("a", in: session, with: .allowOnce) == true)
        #expect(center.queues[session]?.map(\.id) == ["b"])
    }

    @Test func perQuestaSessioneAllowsExactlyTheSameCallAgainInThatSessioneOnly() {
        var center = RequestCenter()
        _ = center.receive(Self.bash("1", "npm test"), in: session, risk: Risk(level: .modifica))
        #expect(center.answer("1", in: session, with: .allowForSession) == true)

        #expect(center.receive(Self.bash("2", "npm test"), in: session, risk: Risk(level: .modifica)) == .allowed)
        #expect(center.receive(Self.bash("3", "npm test -- --watch"), in: session, risk: Risk(level: .modifica)) == .queued)
        #expect(center.receive(Self.bash("4", "npm test"), in: other, risk: Risk(level: .modifica)) == .queued)
    }

    @Test func levelsFourAndFiveNeedAHoldAndNeverGiveARule() throws {
        var center = RequestCenter()
        _ = center.receive(Self.bash("1", "git push --force"), in: session, risk: Risk(level: .irreversibile))
        let pending = try #require(center.queues[session]?.first)
        #expect(pending.needsHold)
        #expect(!pending.allowsSessionRule)

        // Even if asked for: it counts as Solo ora.
        #expect(center.answer("1", in: session, with: .allowForSession) == true)
        #expect(center.receive(Self.bash("2", "git push --force"), in: session, risk: Risk(level: .irreversibile)) == .queued)
    }

    @Test func claudeCanForbidOneKeyAndLastingPermissions() {
        var center = RequestCenter()
        var request = Self.bash("1", "npm test")
        request.defaultsToNo = true
        _ = center.receive(request, in: session, risk: Risk(level: .modifica))
        #expect(center.queues[session]?.first?.needsHold == true)

        request = Self.bash("2", "npm test")
        request.suppressesRule = true
        _ = center.receive(request, in: other, risk: Risk(level: .modifica))
        #expect(center.queues[other]?.first?.needsHold == false)
        #expect(center.queues[other]?.first?.allowsSessionRule == false)
    }

    @Test func aBashCallWithoutItsCommandGivesNoRule() {
        #expect(SessionRule(PermissionRequest(id: "1", tool: "Bash")) == nil)
        #expect(SessionRule(PermissionRequest(id: "2", tool: "WebFetch", url: "https://a.dev/x"))?.subject == "a.dev")
    }

    @Test func aWithdrawnOrStaleRequestIsNotAnswered() {
        var center = RequestCenter()
        _ = center.receive(Self.bash("1", "npm test"), in: session, risk: Risk(level: .modifica))
        #expect(center.withdraw("1", in: session) != nil)
        #expect(center.answer("1", in: session, with: .allowOnce) == nil)
        #expect(center.answer("missing", in: session, with: .allowOnce) == nil)
    }

    @Test func theEndOfATurnClearsTheQueueAndDeletingTheSessioneItsRules() {
        var center = RequestCenter()
        _ = center.receive(Self.bash("1", "npm test"), in: session, risk: Risk(level: .modifica))
        _ = center.answer("1", in: session, with: .allowForSession)
        _ = center.receive(Self.bash("2", "ls"), in: session, risk: Risk(level: .lettura))

        center.clear(session)
        #expect(center.queues[session] == nil)
        #expect(center.receive(Self.bash("3", "npm test"), in: session, risk: Risk(level: .modifica)) == .allowed)

        center.forget(session)
        #expect(center.receive(Self.bash("4", "npm test"), in: session, risk: Risk(level: .modifica)) == .queued)
    }

    @Test func theCardShowsEveryCharacterThatWillRun() {
        #expect(PermissionRequestView.shown("rm a\rb\u{202E}c\ntouch d")
            == "rm a\\u{D}b\\u{202E}c\ntouch d")
    }
}
