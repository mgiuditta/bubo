import CryptoKit
import Foundation
import os
import RemoteKit

/// Impostazioni › iPhone: the pairing QR, the 6-digit check, the paired iPhones and their revocation (spec 21).
///
/// The Mac's key-agreement key is fresh for every QR and forgotten once the pairing ends: revoking an iPhone
/// deletes its record key, so nothing it held opens any more, and the channel deletes the pair's records.
@Observable
final class PairingController {
    /// Where the pairing is.
    enum Phase {
        /// No QR on screen.
        case idle
        /// The QR is on screen, waiting for an iPhone.
        case waiting(PairingInvitation)
        /// An iPhone answered: the user compares the codes before confirming.
        case confirming(PendingDevice)
        /// The QR expired before an answer arrived.
        case expired
    }

    /// An iPhone that answered the QR and awaits the user's confirmation.
    struct PendingDevice: Identifiable {
        let id: UUID
        let name: String
        /// The code the iPhone shows too.
        let verificationCode: String
        let signingKey: Data
        let recordKey: SymmetricKey
    }

    /// `UserDefaults` key of the random identifier of this Mac, created at the first pairing.
    static let macIDKey = "remoteMacID"
    /// `UserDefaults` key of the Telecomando switch: turning it on is the consent (spec 21).
    static let isOnKey = "remoteIsOn"

    private(set) var phase: Phase = .idle
    /// The paired iPhones, oldest first.
    private(set) var devices: [PairedDevice] = []
    /// The last keychain or channel failure, shown under the list.
    private(set) var failure: String?

    let macID: UUID
    private let macName: String
    private let channel: any RemoteChannel
    private let store: any PairedDeviceStore
    /// The Mac's X25519 key of the QR on screen.
    private var agreementKey: Curve25519.KeyAgreement.PrivateKey?
    private let log = Logger(subsystem: "com.mgiuditta.bubo", category: "remote")

    init(macID: UUID, macName: String, channel: any RemoteChannel, store: any PairedDeviceStore) {
        self.macID = macID
        self.macName = macName
        self.channel = channel
        self.store = store
    }

    /// The controller of this Mac, with its identifier in `defaults` and the iPhones in the keychain.
    ///
    /// The channel is in memory until the CloudKit container exists (#244): the QR shows, but no iPhone answers yet.
    static func live(defaults: UserDefaults = .standard) -> PairingController {
        let macID = defaults.string(forKey: macIDKey).flatMap(UUID.init(uuidString:)) ?? {
            let id = UUID()
            defaults.set(id.uuidString, forKey: macIDKey)
            return id
        }()
        return PairingController(
            macID: macID,
            macName: Host.current().localizedName ?? "Mac",
            channel: InMemoryRemoteChannel(),
            store: KeychainStore<PairedDevice>(service: "com.mgiuditta.bubo.remote.device")
        )
    }

    /// Loads the paired iPhones, then applies the revocations the iPhones send until cancelled.
    func run() async {
        do {
            devices = try await store.items().sorted { $0.pairedAt < $1.pairedAt }
        } catch {
            report(error)
        }
        for await revocation in await channel.revocations() where revocation.macID == macID {
            await forget(revocation.deviceID)
        }
    }

    /// Shows a new QR, valid 5 minutes, replacing any pairing in progress.
    func startPairing(now: Date = .now) {
        let key = Curve25519.KeyAgreement.PrivateKey()
        agreementKey = key
        phase = .waiting(PairingInvitation(macID: macID, macName: macName, agreementKey: key.publicKey, now: now))
    }

    /// Waits for the iPhone's answer to the QR on screen, until it arrives or the caller is cancelled.
    func waitForResponse() async {
        guard case .waiting(let invitation) = phase else { return }
        for await response in await channel.responses(to: invitation.id) {
            if accept(response, to: invitation) { return }
        }
    }

    /// Takes the first valid answer to `invitation`; returns whether the wait is over.
    func accept(_ response: PairingResponse, to invitation: PairingInvitation, now: Date = .now) -> Bool {
        guard case .waiting(let current) = phase, current.id == invitation.id, let agreementKey else { return true }
        guard !invitation.isExpired(at: now) else {
            expire(invitation)
            return true
        }
        do {
            let secrets = try PairingCrypto.secrets(
                privateKey: agreementKey,
                peerKey: response.agreementKey,
                invitation: invitation,
                deviceID: response.deviceID
            )
            let enrollment = try response.enrollment(using: secrets)
            phase = .confirming(PendingDevice(
                id: response.deviceID,
                name: enrollment.deviceName,
                verificationCode: secrets.verificationCode,
                signingKey: enrollment.signingKey,
                recordKey: secrets.key
            ))
            return true
        } catch {
            // Someone else's answer, or a damaged one: the QR stays valid for the user's iPhone.
            log.error("Risposta all'accoppiamento scartata: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Ends the wait for `invitation`, whose QR has expired; a newer QR is left alone.
    func expire(_ invitation: PairingInvitation) {
        guard case .waiting(let current) = phase, current.id == invitation.id else { return }
        agreementKey = nil
        phase = .expired
    }

    /// The codes match: the iPhone becomes a paired device.
    func confirm(now: Date = .now) async {
        guard case .confirming(let pending) = phase else { return }
        let device = PairedDevice(
            id: pending.id,
            name: pending.name,
            signingKey: pending.signingKey,
            recordKey: pending.recordKey.withUnsafeBytes { Data($0) },
            pairedAt: now
        )
        agreementKey = nil
        phase = .idle
        do {
            try await store.save(device)
            devices.removeAll { $0.id == device.id }
            devices.append(device)
            failure = nil
        } catch {
            report(error)
        }
    }

    /// Stops the pairing in progress: the QR and its key are forgotten.
    func cancel() {
        agreementKey = nil
        phase = .idle
    }

    /// Revokes the iPhone `device`: the record key is deleted and the channel deletes the pair's records.
    func revoke(_ device: PairedDevice) async {
        await forget(device.id)
        do {
            try await channel.revoke(Revocation(macID: macID, deviceID: device.id))
        } catch {
            report(error)
        }
    }

    private func forget(_ deviceID: UUID) async {
        devices.removeAll { $0.id == deviceID }
        do {
            try await store.delete(id: deviceID)
        } catch {
            report(error)
        }
    }

    private func report(_ error: any Error) {
        log.error("Telecomando: \(String(describing: error), privacy: .public)")
        failure = if let keychain = error as? KeychainFailure {
            KeychainError(status: keychain.status).errorDescription
        } else {
            String(localized: "Il Telecomando non ha risposto. Riprova.")
        }
    }
}
