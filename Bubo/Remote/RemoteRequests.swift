import CryptoKit
import Foundation
import os
import RemoteKit

/// Sends the Richieste di permesso to the paired iPhones and takes back their Verdicts (spec 21).
///
/// A Richiesta goes out as a Request record, one copy per iPhone, with a notification category only while the user is
/// away from the Mac: at the Mac the record carries none, so no push leaves, and it gets one when the user walks away.
/// A Verdict counts only when it passes ``VerdictVerifier`` (signature of a paired iPhone, this Mac, at most 10 minutes
/// old, a fresh nonce), answers a Richiesta still open within its 10 minutes, and gives an answer the Richiesta offers;
/// then it answers as the HUD does. A Richiesta resolved after its notification left is rewritten as resolved, so the
/// iPhone replaces the notification; one that never notified is deleted.
final class RemoteRequests {
    /// How often the Verdicts are read while a Richiesta is out: push notifications to the Mac are not guaranteed.
    static let verdictInterval: TimeInterval = 3
    /// How often the user's presence is checked again while nothing is out, or a Richiesta waits without notification.
    static let presenceInterval: TimeInterval = 30
    /// How long a resolved Richiesta stays, for the iPhone to rewrite its notification, before the cleanup.
    static let resolvedLifetime: TimeInterval = 600

    /// A Richiesta of a Sessione.
    struct Key: Hashable {
        let session: UUID
        let request: PermissionRequest.ID
    }

    /// A Verdict that passed every check, for a Richiesta still open.
    struct Decision: Equatable {
        let session: UUID
        let request: PermissionRequest.ID
        let answer: PermissionAnswer
    }

    /// Why a Verdict was discarded.
    enum Refusal: Error, Equatable {
        /// The record does not open with the pair's key.
        case unreadable
        /// The Verdict itself fails: unknown or revoked iPhone, bad signature, other Mac, too old, repeated nonce.
        case rejected(VerdictRejection)
        /// The Richiesta was already resolved on the Mac, or by another Verdict.
        case alreadyResolved
        /// Signed after the 10 minutes the iPhone had to decide.
        case expired
        /// An answer the Richiesta does not offer from the iPhone, such as Per questa Sessione on level 5.
        case answerNotOffered
    }

    /// A Richiesta as sent, and whether its notification left.
    private struct Sent {
        var remote: RemoteRequest
        var isNotified: Bool
    }

    private let macID: UUID
    private let channel: any RemoteChannel
    private let devices: () -> [PairedDevice]
    private let isOn: () -> Bool
    private let macOnly: MacOnlyProjects
    private let isUserAtMac: () -> Bool
    private var sent: [Key: Sent] = [:]
    /// The iPhones the Richieste in ``sent`` went to: a change sends them all again.
    private var sentDevices: Set<UUID> = []
    private var verifier: VerdictVerifier
    /// The Verdicts discarded by the latest read, for the log and the tests.
    private(set) var refusals: [Refusal] = []
    private let log = Logger(subsystem: "com.mgiuditta.bubo", category: "remote")

    /// Creates the Richieste of the Mac `macID`.
    ///
    /// - Parameters:
    ///   - devices: The paired iPhones now.
    ///   - isOn: Whether the Telecomando is on, the user's consent.
    ///   - isUserAtMac: Whether the user is at the Mac now: then no notification leaves.
    init(macID: UUID, channel: any RemoteChannel, devices: @escaping () -> [PairedDevice], isOn: @escaping () -> Bool,
         macOnly: MacOnlyProjects, isUserAtMac: @escaping () -> Bool) {
        self.macID = macID
        self.channel = channel
        self.devices = devices
        self.isOn = isOn
        self.macOnly = macOnly
        self.isUserAtMac = isUserAtMac
        verifier = VerdictVerifier(macID: macID)
    }

    /// The Richieste of the Telecomando of `remote`, with the switch in `defaults`.
    static func live(remote: PairingController, macOnly: MacOnlyProjects, presence: PresenceMonitor,
                     defaults: UserDefaults = .standard) -> RemoteRequests {
        RemoteRequests(macID: remote.macID, channel: remote.channel, devices: { [weak remote] in remote?.devices ?? [] },
                       isOn: { defaults.bool(forKey: PairingController.isOnKey) }, macOnly: macOnly) { [weak presence] in
            presence?.isUserAtMac ?? true
        }
    }

    /// Sends the Richieste of `store` as they arrive, and answers them with the Verdicts, until cancelled.
    func run(sessions store: SessionStore) async {
        async let changes: Void = publishChanges(of: store)
        async let checks: Void = checkRegularly(store)
        _ = await (changes, checks)
    }

    /// Writes the Richieste waiting in `requests` that are not out yet, gives a notification to those waiting
    /// without one once the user is away, and retires those no longer waiting. Nothing of a Progetto solo Mac or an
    /// Archiviata goes out, and nothing at all with the Telecomando off.
    func publish(_ sessions: [Session], requests: RequestCenter, now: Date = .now) async {
        let paired = devices()
        let devices = isOn() ? paired : []
        if Set(devices.map(\.id)) != sentDevices {
            // Turned off, or the iPhones changed: what went out is withdrawn, and goes again to the new set.
            if !sent.isEmpty { await delete(sent.values.map(\.remote), for: paired) }
            sent = [:]
            sentDevices = Set(devices.map(\.id))
        }
        guard !devices.isEmpty else { return }

        let isAway = !isUserAtMac()
        var writes: [(remote: RemoteRequest, notifies: Bool)] = []
        var waiting = Set<Key>()
        // The state changes before any write: a concurrent call never sends the same Richiesta twice.
        for session in sessions where session.phase != .archiviata && !macOnly.isMacOnly(session.project) {
            for pending in requests.queues[session.id] ?? [] {
                let key = Key(session: session.id, request: pending.id)
                waiting.insert(key)
                if var entry = sent[key] {
                    guard isAway, !entry.isNotified, !entry.remote.isExpired(at: now) else { continue }
                    entry.isNotified = true
                    sent[key] = entry
                    writes.append((entry.remote, true))
                } else {
                    let remote = Self.remote(of: pending, in: session, now: now)
                    sent[key] = Sent(remote: remote, isNotified: isAway)
                    writes.append((remote, isAway))
                }
            }
        }
        var deletions: [RemoteRequest] = []
        for (key, entry) in sent where !waiting.contains(key) {
            sent[key] = nil
            if let resolved = Self.resolved(entry) { writes.append((resolved, true)) } else { deletions.append(entry.remote) }
        }
        for write in writes {
            for device in devices {
                await save(write.remote, notifies: write.notifies, for: device, now: now)
            }
        }
        if !deletions.isEmpty { await delete(deletions, for: devices) }
    }

    /// Reads the Verdicts of every paired iPhone, deletes them, and returns those that answer a Richiesta still open.
    ///
    /// The Richiesta of an accepted Verdict is retired at once: a second Verdict for it, from this iPhone or another,
    /// finds it resolved.
    func readVerdicts(now: Date = .now) async -> [Decision] {
        var decisions: [Decision] = []
        var read: [String] = []
        refusals = []
        for device in devices() {
            if let key = try? P256.Signing.PublicKey(x963Representation: device.signingKey) {
                verifier.trust(deviceID: device.id, signingKey: key)
            }
            let verdicts: [(recordID: String, verdict: SignedVerdict?)]
            do {
                verdicts = try await channel.verdicts(macID: macID, deviceID: device.id, sealer: Self.sealer(for: device))
            } catch {
                log.error("Verdetti non letti: \(String(describing: error), privacy: .public)")
                continue
            }
            for (recordID, signed) in verdicts {
                read.append(recordID)
                do {
                    let (decision, entry) = try check(signed, now: now)
                    decisions.append(decision)
                    if let resolved = Self.resolved(entry) {
                        for device in devices() { await save(resolved, notifies: true, for: device, now: now) }
                    } else {
                        await delete([entry.remote], for: devices())
                    }
                } catch {
                    refusals.append(error)
                    log.notice("Verdetto scartato: \(String(describing: error), privacy: .public)")
                }
            }
        }
        if !read.isEmpty {
            do {
                try await channel.deleteRecords(read)
            } catch {
                log.error("Verdetti non cancellati: \(String(describing: error), privacy: .public)")
            }
        }
        return decisions
    }

    /// The Richiesta `signed` answers, retired from ``sent``, with the answer it gives.
    private func check(_ signed: SignedVerdict?, now: Date) throws(Refusal) -> (Decision, Sent) {
        guard let signed else { throw .unreadable }
        let verdict: Verdict
        do {
            verdict = try verifier.verify(signed, now: now)
        } catch {
            throw .rejected(error)
        }
        guard let (key, entry) = sent.first(where: { $0.value.remote.id == verdict.requestID }) else {
            throw .alreadyResolved
        }
        guard !entry.remote.isExpired(at: verdict.issuedAt) else { throw .expired }
        guard entry.remote.answers.contains(verdict.answer) else { throw .answerNotOffered }
        sent[key] = nil
        let answer: PermissionAnswer = switch verdict.answer {
        case .deny: .deny
        case .allowOnce: .allowOnce
        case .allowForSession: .allowForSession
        }
        return (Decision(session: key.session, request: key.request, answer: answer), entry)
    }

    /// The Richiesta `pending` of `session` as the iPhone sees it, decidable for the next 10 minutes.
    ///
    /// Only what the Mac's notification may approve is approved from the iPhone's: a long command, one with invisible
    /// characters, one outside the Sandbox or of levels 4–5 opens the full-screen page.
    static func remote(of pending: RequestCenter.Pending, in session: Session, now: Date) -> RemoteRequest {
        let request = pending.request
        return RemoteRequest(
            sessionID: session.id,
            sessionTitle: session.title,
            project: session.project.lastPathComponent,
            level: pending.risk.level.rawValue,
            tool: request.tool,
            subject: request.subject,
            reason: request.title,
            allowsSessionRule: pending.allowsSessionRule,
            needsReview: pending.needsHold || !PermissionNotice(pending).offersAllowOnce,
            expiresAt: now.addingTimeInterval(RemoteRequest.decisionWindow)
        )
    }

    private func publishChanges(of store: SessionStore) async {
        for await _ in Observations({ store.permissions }) {
            await publish(store.sessions, requests: store.permissions)
        }
    }

    /// Checks the presence and reads the Verdicts: every 3 s while a Richiesta is out, every 30 s otherwise.
    private func checkRegularly(_ store: SessionStore) async {
        while !Task.isCancelled {
            await publish(store.sessions, requests: store.permissions)
            for decision in await readVerdicts() {
                store.answer(decision.request, in: decision.session, with: decision.answer)
            }
            let interval = sent.isEmpty ? Self.presenceInterval : Self.verdictInterval
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    /// The resolved version of `entry`, to replace its notification; `nil` when no notification left.
    private static func resolved(_ entry: Sent) -> RemoteRequest? {
        guard entry.isNotified else { return nil }
        var resolved = entry.remote
        resolved.isResolved = true
        return resolved
    }

    /// Seals `remote` for `device` and saves it, with its notification category when it `notifies`.
    private func save(_ remote: RemoteRequest, notifies: Bool, for device: PairedDevice, now: Date) async {
        let sealer = Self.sealer(for: device)
        let id = sealer.recordID(named: Self.recordName(of: remote))
        let lifetime = remote.isResolved ? Self.resolvedLifetime : RemoteBridge.recordLifetime
        do {
            try await channel.save(RemoteRecord(id: id, kind: .request, macID: macID, deviceID: device.id,
                                                expiresAt: now.addingTimeInterval(lifetime),
                                                payload: sealer.seal(remote, recordID: id),
                                                category: notifies ? remote.category.rawValue : nil))
        } catch {
            log.error("Richiesta del Telecomando non scritta: \(String(describing: error), privacy: .public)")
        }
    }

    private func delete(_ requests: [RemoteRequest], for devices: [PairedDevice]) async {
        let ids = devices.flatMap { device in
            requests.map { Self.sealer(for: device).recordID(named: Self.recordName(of: $0)) }
        }
        guard !ids.isEmpty else { return }
        do {
            try await channel.deleteRecords(ids)
        } catch {
            log.error("Richieste del Telecomando non cancellate: \(String(describing: error), privacy: .public)")
        }
    }

    private static func recordName(of request: RemoteRequest) -> String {
        "request/\(request.id.uuidString)"
    }

    private static func sealer(for device: PairedDevice) -> RecordSealer {
        RecordSealer(key: SymmetricKey(data: device.recordKey))
    }
}
