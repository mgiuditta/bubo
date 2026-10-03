import CryptoKit
import Foundation
import RemoteKit
import Testing
@testable import Bubo

/// Whether the user is at the Mac, which the tests change.
private final class Presence {
    var isAtMac = false
}

@MainActor
struct RemoteRequestsTests {
    let channel = InMemoryRemoteChannel()
    let macID = UUID()
    let signer = PhoneSigner()
    let phone: PairedDevice
    let macOnly = MacOnlyProjects(defaults: UserDefaults(suiteName: "RemoteRequestsTests-\(UUID().uuidString)")!)
    private let presence = Presence()
    let relay: RemoteRequests
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let session = Session(id: UUID(), title: "Correggi il login", project: URL(filePath: "/Users/u/Sviluppo/gestionale"),
                          activity: .attende)

    init() {
        let phone = PairedDevice(id: UUID(), name: "iPhone di prova", signingKey: signer.publicKey.x963Representation,
                                 recordKey: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }, pairedAt: .now)
        self.phone = phone
        let presence = presence
        relay = RemoteRequests(macID: macID, channel: channel, devices: { [phone] }, isOn: { true }, macOnly: macOnly) {
            presence.isAtMac
        }
    }

    var sealer: RecordSealer { RecordSealer(key: SymmetricKey(data: phone.recordKey)) }

    /// A Richiesta of `level` waiting in the Sessione.
    func requests(_ id: String = "1", command: String = "npm test", level: RiskLevel = .modifica) -> RequestCenter {
        var requests = RequestCenter()
        _ = requests.receive(PermissionRequest(id: id, tool: "Bash", command: command), in: session.id,
                             risk: Risk(level: level), at: now)
        return requests
    }

    func requestRecords() async throws -> [RemoteRecord] {
        try await channel.records(macID: macID, deviceID: phone.id).filter { $0.kind == .request }
    }

    /// The Richiesta the iPhone sees.
    func phoneRequest() async throws -> RemoteRequest {
        try #require(try await channel.snapshot(macID: macID, deviceID: phone.id, sealer: sealer).requests.first)
    }

    /// The iPhone signs `answer` to `request` at `date` and writes the Verdict.
    @discardableResult
    func answer(_ request: RemoteRequest, with answer: Verdict.Answer, at date: Date) async throws -> SignedVerdict {
        let signed = try Verdict(requestID: request.id, answer: answer, macID: macID, issuedAt: date)
            .signed(by: signer, deviceID: phone.id)
        try await channel.send(signed, sealer: sealer)
        return signed
    }

    @Test func levelTwoGoesOutWithEveryAnswerInTheNotification() async throws {
        await relay.publish([session], requests: requests(), now: now)

        let record = try #require(try await requestRecords().first)
        #expect(record.category == RemoteRequest.Category.requestLow.rawValue)
        let request = try await phoneRequest()
        #expect(request.level == 2)
        #expect(request.subject == "npm test")
        #expect(request.answers == [.deny, .allowOnce, .allowForSession])
    }

    @Test func levelFiveOffersNoApprovalInTheNotification() async throws {
        await relay.publish([session], requests: requests(command: "git push --force", level: .irreversibile), now: now)

        let record = try #require(try await requestRecords().first)
        #expect(record.category == RemoteRequest.Category.requestHigh.rawValue)
        #expect(RemoteRequest.Category.requestHigh.notificationAnswers.isEmpty)
        #expect(try await phoneRequest().answers == [.deny, .allowOnce])
    }

    @Test func userAtTheMacGetsNoPushUntilAway() async throws {
        presence.isAtMac = true
        await relay.publish([session], requests: requests(), now: now)

        #expect(try await requestRecords().map(\.category) == [nil])

        presence.isAtMac = false
        await relay.publish([session], requests: requests(), now: now.addingTimeInterval(30))

        #expect(try await requestRecords().map(\.category) == [RemoteRequest.Category.requestLow.rawValue])
    }

    @Test func requestResolvedAtTheMacWithoutPushIsDeleted() async throws {
        presence.isAtMac = true
        await relay.publish([session], requests: requests(), now: now)

        await relay.publish([session], requests: RequestCenter(), now: now.addingTimeInterval(5))

        #expect(try await requestRecords().isEmpty)
    }

    @Test func requestResolvedAtTheMacRewritesItsNotification() async throws {
        await relay.publish([session], requests: requests(), now: now)

        await relay.publish([session], requests: RequestCenter(), now: now.addingTimeInterval(5))

        #expect(try await requestRecords().map(\.category) == [RemoteRequest.Category.resolved.rawValue])
        #expect(try await channel.snapshot(macID: macID, deviceID: phone.id, sealer: sealer).requests.isEmpty)
    }

    @Test func macOnlyProjectSendsNoRequest() async throws {
        macOnly.setMacOnly(true, for: session.project)

        await relay.publish([session], requests: requests(), now: now)

        #expect(try await requestRecords().isEmpty)
    }

    @Test func validVerdictAnswersTheRequest() async throws {
        await relay.publish([session], requests: requests(), now: now)
        try await answer(try await phoneRequest(), with: .allowForSession, at: now.addingTimeInterval(20))

        let decisions = await relay.readVerdicts(now: now.addingTimeInterval(25))

        #expect(decisions == [.init(session: session.id, request: "1", answer: .allowForSession)])
        #expect(try await channel.records(macID: macID, deviceID: phone.id).count { $0.kind == .verdict } == 0)
    }

    @Test func expiredVerdictIsDiscarded() async throws {
        await relay.publish([session], requests: requests(), now: now)
        try await answer(try await phoneRequest(), with: .allowOnce, at: now.addingTimeInterval(20))

        #expect(await relay.readVerdicts(now: now.addingTimeInterval(20 + 601)).isEmpty)
        #expect(relay.refusals == [.rejected(.expired)])
    }

    @Test func verdictSignedAfterTheDecisionWindowIsDiscarded() async throws {
        await relay.publish([session], requests: requests(), now: now)
        try await answer(try await phoneRequest(), with: .allowOnce, at: now.addingTimeInterval(700))

        #expect(await relay.readVerdicts(now: now.addingTimeInterval(705)).isEmpty)
        #expect(relay.refusals == [.expired])
    }

    @Test func replayedVerdictIsDiscarded() async throws {
        await relay.publish([session], requests: requests(), now: now)
        let signed = try await answer(try await phoneRequest(), with: .allowOnce, at: now.addingTimeInterval(20))
        #expect(await relay.readVerdicts(now: now.addingTimeInterval(25)).count == 1)
        // The same Verdict again, for the same Richiesta asked again with the same id.
        await relay.publish([session], requests: requests(), now: now.addingTimeInterval(26))

        try await channel.send(signed, sealer: sealer)

        #expect(await relay.readVerdicts(now: now.addingTimeInterval(30)).isEmpty)
        #expect(relay.refusals == [.rejected(.repeatedNonce)])
    }

    @Test func verdictForRequestResolvedAtTheMacIsDiscarded() async throws {
        await relay.publish([session], requests: requests(), now: now)
        let request = try await phoneRequest()
        await relay.publish([session], requests: RequestCenter(), now: now.addingTimeInterval(5))
        try await answer(request, with: .allowOnce, at: now.addingTimeInterval(10))

        #expect(await relay.readVerdicts(now: now.addingTimeInterval(12)).isEmpty)
        #expect(relay.refusals == [.alreadyResolved])
    }

    @Test func secondVerdictForTheSameRequestIsDiscarded() async throws {
        await relay.publish([session], requests: requests(), now: now)
        let request = try await phoneRequest()
        try await answer(request, with: .deny, at: now.addingTimeInterval(10))
        try await answer(request, with: .allowOnce, at: now.addingTimeInterval(11))

        let decisions = await relay.readVerdicts(now: now.addingTimeInterval(12))

        #expect(decisions.count == 1)
        #expect(relay.refusals == [.alreadyResolved])
    }

    @Test func sessionPermissionOnLevelFiveIsDiscarded() async throws {
        await relay.publish([session], requests: requests(command: "git push --force", level: .irreversibile), now: now)
        try await answer(try await phoneRequest(), with: .allowForSession, at: now.addingTimeInterval(10))

        #expect(await relay.readVerdicts(now: now.addingTimeInterval(12)).isEmpty)
        #expect(relay.refusals == [.answerNotOffered])
    }

    @Test func verdictOfAnUnpairedPhoneIsDiscarded() async throws {
        await relay.publish([session], requests: requests(), now: now)
        let request = try await phoneRequest()
        let forged = try Verdict(requestID: request.id, answer: .allowOnce, macID: macID, issuedAt: now)
            .signed(by: PhoneSigner(), deviceID: UUID())
        try await channel.save(RemoteRecord(id: "falso", kind: .verdict, macID: macID, deviceID: phone.id,
                                            expiresAt: now.addingTimeInterval(600),
                                            payload: sealer.seal(forged, recordID: "falso")))

        #expect(await relay.readVerdicts(now: now.addingTimeInterval(5)).isEmpty)
        #expect(relay.refusals == [.rejected(.unknownDevice)])
    }

    @Test func verdictReachesTheSessionThroughTheRequestCenter() async throws {
        var requests = requests()
        await relay.publish([session], requests: requests, now: now)
        try await answer(try await phoneRequest(), with: .allowForSession, at: now.addingTimeInterval(10))

        let decision = try #require(await relay.readVerdicts(now: now.addingTimeInterval(12)).first)

        #expect(requests.answer(decision.request, in: decision.session, with: decision.answer) == true)
        // Per questa Sessione: the same call again is allowed at once.
        let again = requests.receive(PermissionRequest(id: "2", tool: "Bash", command: "npm test"), in: session.id,
                                     risk: Risk(level: .modifica))
        #expect(again == .allowed)
    }

    @Test func awayFromTheMacOnlyThePhoneRings() {
        #expect(relay.notifiesPhone(about: session))

        presence.isAtMac = true

        #expect(!relay.notifiesPhone(about: session))
    }

    @Test func sessionOfAProjectSoloMacLeavesTheMacNotificationRinging() {
        macOnly.setMacOnly(true, for: session.project)

        #expect(!relay.notifiesPhone(about: session))
    }

    @Test func withoutAPairedPhoneTheMacNotificationRings() {
        let alone = RemoteRequests(macID: macID, channel: channel, devices: { [] }, isOn: { true }, macOnly: macOnly) {
            false
        }

        #expect(!alone.notifiesPhone(about: session))
    }
}
