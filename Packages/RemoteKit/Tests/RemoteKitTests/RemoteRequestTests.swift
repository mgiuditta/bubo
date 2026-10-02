import CryptoKit
import Foundation
import RemoteKit
import Testing

struct RemoteRequestTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func request(level: Int, allowsSessionRule: Bool = true, needsReview: Bool? = nil) -> RemoteRequest {
        RemoteRequest(sessionID: UUID(), sessionTitle: "Correggi il login", project: "gestionale", level: level,
                      tool: "Bash", subject: "rm -rf build", reason: nil, allowsSessionRule: allowsSessionRule,
                      needsReview: needsReview ?? (level >= 4), expiresAt: now.addingTimeInterval(600))
    }

    @Test func levelTwoOffersEveryAnswerFromTheNotification() {
        let request = request(level: 2)
        #expect(request.category == .requestLow)
        #expect(Set(request.category.notificationAnswers) == [.deny, .allowOnce, .allowForSession])
    }

    @Test(arguments: [4, 5])
    func levelsFourAndFiveOfferNoApprovalInTheNotification(level: Int) {
        let request = request(level: level, allowsSessionRule: false)
        #expect(request.category == .requestHigh)
        #expect(request.category.notificationAnswers.isEmpty)
        #expect(request.answers == [.deny, .allowOnce])
    }

    @Test func callThatMustNotBeApprovedWithOneKeyNeedsTheApp() {
        #expect(request(level: 2, needsReview: true).category == .requestHigh)
    }

    @Test func withoutSessionRuleTheNotificationOffersOnlyOnceAndNo() {
        let request = request(level: 3, allowsSessionRule: false)
        #expect(request.category == .requestLowOnce)
        #expect(request.category.notificationAnswers == [.allowOnce, .deny])
        #expect(request.answers == [.deny, .allowOnce])
    }

    @Test func resolvedRequestHasNoActionsAndLeavesTheSnapshot() async throws {
        var resolved = request(level: 2)
        resolved.isResolved = true
        #expect(resolved.category.notificationAnswers.isEmpty)

        let channel = InMemoryRemoteChannel()
        let sealer = RecordSealer(key: SymmetricKey(size: .bits256))
        let macID = UUID()
        let deviceID = UUID()
        let open = request(level: 1)
        for request in [open, resolved] {
            let id = sealer.recordID(named: "request/\(request.id)")
            try await channel.save(RemoteRecord(id: id, kind: .request, macID: macID, deviceID: deviceID,
                                                expiresAt: now.addingTimeInterval(86_400),
                                                payload: sealer.seal(request, recordID: id),
                                                category: request.category.rawValue))
        }

        #expect(try await channel.snapshot(macID: macID, deviceID: deviceID, sealer: sealer).requests == [open])
    }

    @Test func expiresAfterTheDecisionWindow() {
        let request = request(level: 2)
        #expect(!request.isExpired(at: now.addingTimeInterval(599)))
        #expect(request.isExpired(at: now.addingTimeInterval(601)))
    }

    @Test func verdictTravelsSealedAndOpensOnTheMac() async throws {
        let channel = InMemoryRemoteChannel()
        let sealer = RecordSealer(key: SymmetricKey(size: .bits256))
        let macID = UUID()
        let deviceID = UUID()
        let signed = try Verdict(requestID: UUID(), answer: .allowOnce, macID: macID, issuedAt: now)
            .signed(by: SoftwareSigner(), deviceID: deviceID)

        try await channel.send(signed, sealer: sealer)

        let read = try await channel.verdicts(macID: macID, deviceID: deviceID, sealer: sealer)
        #expect(read.map(\.verdict) == [signed])
        let other = try await channel.verdicts(macID: macID, deviceID: deviceID,
                                               sealer: RecordSealer(key: SymmetricKey(size: .bits256)))
        #expect(other.map(\.verdict) == [nil])
    }
}
