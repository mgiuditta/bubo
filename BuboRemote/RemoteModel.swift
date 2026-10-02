import CryptoKit
import Foundation
import os
import RemoteKit
import UIKit

/// The iPhone side of pairing and revocation (spec 21): QR, code, Face ID, the paired Macs.
@Observable
final class RemoteModel {
    /// Where a pairing is.
    enum Pairing {
        /// The camera looks for the Mac's QR.
        case scanning
        /// The QR is read: the user compares the code and pairs with Face ID.
        case reviewing(ScannedInvitation)
        /// The response is sent: the user confirms the code on the Mac.
        case sent(macName: String)
        /// The pairing stopped, with the reason to show.
        case failed(String)
    }

    /// A QR read and the secrets derived from it, before Face ID.
    struct ScannedInvitation {
        let invitation: PairingInvitation
        let agreementKey: Curve25519.KeyAgreement.PrivateKey
        let secrets: PairingSecrets
    }

    /// `UserDefaults` key of the random identifier of this iPhone.
    static let deviceIDKey = "remoteDeviceID"

    /// The paired Macs, oldest first.
    private(set) var macs: [PairedMac] = []
    /// The pairing in progress; `nil` when none.
    private(set) var pairing: Pairing?

    let deviceID: UUID
    private let deviceName: String
    private let channel: any RemoteChannel
    private let store: KeychainStore<PairedMac>
    private let log = Logger(subsystem: "com.mgiuditta.bubo.remote", category: "pairing")

    init(deviceID: UUID, deviceName: String, channel: any RemoteChannel, store: KeychainStore<PairedMac>) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.channel = channel
        self.store = store
    }

    /// The model of this iPhone, with its identifier in `defaults` and the Macs in the keychain.
    ///
    /// The channel is in memory until the CloudKit container exists (#244).
    static func live(defaults: UserDefaults = .standard) -> RemoteModel {
        let deviceID = defaults.string(forKey: deviceIDKey).flatMap(UUID.init(uuidString:)) ?? {
            let id = UUID()
            defaults.set(id.uuidString, forKey: deviceIDKey)
            return id
        }()
        return RemoteModel(
            deviceID: deviceID,
            deviceName: UIDevice.current.name,
            channel: InMemoryRemoteChannel(),
            store: KeychainStore(service: "com.mgiuditta.bubo.remote.mac")
        )
    }

    /// Loads the paired Macs, then applies the revocations the Macs send until cancelled.
    func run() async {
        do {
            macs = try await store.items().sorted { $0.pairedAt < $1.pairedAt }
        } catch {
            log.error("Portachiavi: \(error.status)")
        }
        if macs.isEmpty { pairing = .scanning }
        for await revocation in await channel.revocations() where revocation.deviceID == deviceID {
            await forget(revocation.macID)
        }
    }

    /// Opens the camera on the Mac's QR.
    func startPairing() {
        pairing = .scanning
    }

    /// Closes the pairing in progress; with no Mac paired, back to the camera.
    func cancelPairing() {
        pairing = macs.isEmpty ? .scanning : nil
    }

    /// Reads the text of a scanned QR and derives the pair's secrets.
    func scanned(_ payload: String, now: Date = .now) {
        guard case .scanning = pairing else { return }
        do {
            let invitation = try PairingInvitation(qrPayload: payload)
            guard !invitation.isExpired(at: now) else { throw PairingError.expired }
            guard invitation.protocolVersion == RemoteProtocol.version else { throw PairingError.incompatibleVersion }
            let key = Curve25519.KeyAgreement.PrivateKey()
            let secrets = try PairingCrypto.secrets(
                privateKey: key,
                peerKey: invitation.agreementKey,
                invitation: invitation,
                deviceID: deviceID
            )
            pairing = .reviewing(ScannedInvitation(invitation: invitation, agreementKey: key, secrets: secrets))
        } catch {
            pairing = .failed(Self.message(for: error))
        }
    }

    /// Creates the signing key in the Secure Enclave, proves it with Face ID and sends the response to the Mac.
    func pair(now: Date = .now) async {
        guard case .reviewing(let scanned) = pairing else { return }
        let invitation = scanned.invitation
        guard !invitation.isExpired(at: now) else {
            pairing = .failed(Self.message(for: PairingError.expired))
            return
        }
        do {
            let signer = try SecureEnclaveSigner.make()
            // Signing the proof asks for Face ID: the key is bound to the current enrollment.
            let response = try PairingResponse(
                to: invitation,
                deviceID: deviceID,
                deviceName: deviceName,
                agreementKey: scanned.agreementKey.publicKey,
                secrets: scanned.secrets,
                signer: signer
            )
            let mac = PairedMac(
                id: invitation.macID,
                name: invitation.macName,
                recordKey: scanned.secrets.key.withUnsafeBytes { Data($0) },
                signingKey: signer.dataRepresentation,
                pairedAt: now
            )
            try await channel.send(response)
            try await store.save(mac)
            macs.removeAll { $0.id == mac.id }
            macs.append(mac)
            pairing = .sent(macName: invitation.macName)
        } catch {
            log.error("Accoppiamento: \(String(describing: error), privacy: .public)")
            pairing = .failed(Self.message(for: error))
        }
    }

    /// Ends the pairing once the user has confirmed on the Mac.
    func finishPairing() {
        pairing = nil
    }

    /// Revokes this iPhone on every paired Mac: keys deleted here, records deleted in iCloud.
    func revokeThisPhone() async {
        for mac in macs {
            do {
                try await channel.revoke(Revocation(macID: mac.id, deviceID: deviceID))
            } catch {
                log.error("Revoca verso \(mac.id): \(String(describing: error), privacy: .public)")
            }
            await forget(mac.id)
        }
        pairing = .scanning
    }

    private func forget(_ macID: UUID) async {
        macs.removeAll { $0.id == macID }
        do {
            try await store.delete(id: macID)
        } catch {
            log.error("Portachiavi: \(error.status)")
        }
        if macs.isEmpty { pairing = .scanning }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case PairingError.unreadableCode:
            "Questo QR non è di Bubo. Inquadra quello in Bubo › Impostazioni › iPhone sul Mac."
        case PairingError.expired:
            "Il QR è scaduto. Sul Mac scegli Nuovo QR e inquadralo di nuovo."
        case PairingError.incompatibleVersion:
            "Bubo sul Mac e il Telecomando hanno versioni diverse. Aggiorna entrambi."
        case SecureEnclaveSigner.Failure.unavailable:
            "Questo iPhone non può creare una chiave sicura: servono un codice e Face ID attivi."
        default:
            "Accoppiamento non riuscito. Riprova dal Mac con un nuovo QR."
        }
    }
}
