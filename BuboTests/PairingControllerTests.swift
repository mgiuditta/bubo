import CryptoKit
import Foundation
import RemoteKit
import Testing
@testable import Bubo

/// The paired iPhones in memory: the keychain is not reachable from the test host (-34018).
actor MemoryDeviceStore: PairedDeviceStore {
    var stored: [UUID: PairedDevice] = [:]

    func items() -> [PairedDevice] { Array(stored.values) }
    func save(_ item: PairedDevice) { stored[item.id] = item }
    func delete(id: UUID) { stored[id] = nil }
}

/// A software P-256 key in place of the iPhone's Secure Enclave.
struct PhoneSigner: RemoteSigner {
    let key = P256.Signing.PrivateKey()
    var publicKey: P256.Signing.PublicKey { key.publicKey }
    func signature(for message: Data) throws -> P256.Signing.ECDSASignature { try key.signature(for: message) }
}

@MainActor
struct PairingControllerTests {
    let channel = InMemoryRemoteChannel()
    let store = MemoryDeviceStore()
    let controller: PairingController

    init() {
        controller = PairingController(macID: UUID(), macName: "Mac di prova", channel: channel, store: store)
    }

    /// The iPhone's side: reads the QR and answers it.
    func answer(
        _ invitation: PairingInvitation,
        deviceID: UUID = UUID(),
        signer: PhoneSigner = PhoneSigner()
    ) throws -> (PairingResponse, PairingSecrets) {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let read = try PairingInvitation(qrPayload: invitation.qrPayload)
        let secrets = try PairingCrypto.secrets(privateKey: key, peerKey: read.agreementKey, invitation: read, deviceID: deviceID)
        let response = try PairingResponse(to: read, deviceID: deviceID, deviceName: "iPhone di prova",
                                           agreementKey: key.publicKey, secrets: secrets, signer: signer)
        return (response, secrets)
    }

    func waitingInvitation() throws -> PairingInvitation {
        guard case .waiting(let invitation) = controller.phase else {
            Issue.record("Nessun QR in attesa")
            throw CancellationError()
        }
        return invitation
    }

    @Test func pairingShowsTheSameCodeAndSavesTheDevice() async throws {
        controller.startPairing()
        let invitation = try waitingInvitation()
        let signer = PhoneSigner()
        let (response, phoneSecrets) = try answer(invitation, signer: signer)
        await channel.send(response)

        await controller.waitForResponse()

        guard case .confirming(let pending) = controller.phase else {
            Issue.record("Il Mac non mostra il codice")
            return
        }
        #expect(pending.verificationCode == phoneSecrets.verificationCode)
        await controller.confirm()
        let device = try #require(controller.devices.first)
        #expect(device.name == "iPhone di prova")
        #expect(device.signingKey == signer.publicKey.x963Representation)
        #expect(await store.items() == [device])
        // The record key on the Mac opens what the iPhone seals.
        let sealed = try RecordSealer(key: phoneSecrets.key).seal(Data("Verdetto".utf8), recordID: "v1")
        #expect(try RecordSealer(key: SymmetricKey(data: device.recordKey)).open(sealed, recordID: "v1") == Data("Verdetto".utf8))
    }

    @Test func answerAfterFiveMinutesExpiresTheQR() throws {
        let now = Date.now
        controller.startPairing(now: now)
        let invitation = try waitingInvitation()
        let (response, _) = try answer(invitation)

        #expect(controller.accept(response, to: invitation, now: now.addingTimeInterval(301)))
        guard case .expired = controller.phase else {
            Issue.record("Il QR non è scaduto")
            return
        }
    }

    @Test func forgedAnswerIsIgnoredAndTheQRStaysValid() throws {
        controller.startPairing()
        let invitation = try waitingInvitation()
        let (response, _) = try answer(invitation)
        let forged = try JSONDecoder().decode(PairingResponse.self, from: JSONEncoder().encode(response)
            .replacing(Data(response.deviceID.uuidString.utf8), with: Data(UUID().uuidString.utf8)))

        #expect(!controller.accept(forged, to: invitation))
        #expect(controller.accept(response, to: invitation))
    }

    @Test func cancelForgetsTheQR() throws {
        controller.startPairing()
        let invitation = try waitingInvitation()
        controller.cancel()
        let (response, _) = try answer(invitation)
        #expect(controller.accept(response, to: invitation))
        guard case .idle = controller.phase else {
            Issue.record("Il QR annullato accetta ancora risposte")
            return
        }
    }

    @Test func revokeFromTheMacDeletesKeyAndRecords() async throws {
        let deviceID = try await pairedDevice()
        await channel.save(RemoteRecord(kind: .sessionCard, macID: controller.macID, deviceID: deviceID,
                                            expiresAt: .now.addingTimeInterval(60), payload: Data([1])))
        let device = try #require(controller.devices.first)

        await controller.revoke(device)

        #expect(controller.devices.isEmpty)
        #expect(await store.items().isEmpty)
        #expect(await channel.records(macID: controller.macID, deviceID: deviceID).isEmpty)
        #expect(await channel.revoked == [Revocation(macID: controller.macID, deviceID: deviceID)])
    }

    @Test(.timeLimit(.minutes(1))) func revokeFromTheIPhoneDeletesTheKeyOnTheMac() async throws {
        let deviceID = try await pairedDevice()
        await channel.revoke(Revocation(macID: controller.macID, deviceID: deviceID))
        // Another Mac's revocation of the same iPhone is not for this one.
        await channel.revoke(Revocation(macID: UUID(), deviceID: deviceID))
        let running = Task { await controller.run() }
        defer { running.cancel() }

        while await !store.items().isEmpty { await Task.yield() }
        #expect(controller.devices.isEmpty)
    }

    private func pairedDevice() async throws -> UUID {
        controller.startPairing()
        let invitation = try waitingInvitation()
        let deviceID = UUID()
        let (response, _) = try answer(invitation, deviceID: deviceID)
        #expect(controller.accept(response, to: invitation))
        await controller.confirm()
        return deviceID
    }
}
