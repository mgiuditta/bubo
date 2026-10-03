import AppKit
import CryptoKit
import Foundation
import os
import RemoteKit

/// Lets the Sessioni out to the paired iPhones (spec 21): a `SessionCard` per Sessione, the Battito every 60 s,
/// and the job that deletes every record older than 24 h, at launch and every hour.
///
/// Every record is sealed with the key of its pair, one copy per iPhone, with an ID that only the pair can tell.
/// Nothing leaves the Mac while the Telecomando is off, and nothing of a Progetto solo Mac ever does.
final class RemoteBridge {
    /// The least time between two writes of the same card.
    static let cardInterval: TimeInterval = 5
    /// The time between two Battiti.
    static let heartbeatInterval: TimeInterval = 60
    /// The time between two runs of the cleanup job.
    static let cleanupInterval: TimeInterval = 3_600
    /// How long a record lives in iCloud after its last write.
    static let recordLifetime: TimeInterval = 86_400
    /// A card unchanged for this long is written again, so that the cleanup never takes a Sessione still there.
    static let cardRefresh: TimeInterval = 43_200
    /// The longest excerpt that goes out.
    static let excerptLimit = 280
    /// The name of the Battito's record of each pair.
    private static let heartbeatName = "heartbeat"

    /// A card as last written, with when.
    private struct Written {
        let card: SessionCard
        let date: Date
    }

    private let macID: UUID
    private let macName: String
    private let channel: any RemoteChannel
    private let devices: () -> [PairedDevice]
    private let isOn: () -> Bool
    private let macOnly: MacOnlyProjects
    private let diffStats: (UUID) async -> SessionCard.DiffStats?
    /// The cards written, by Sessione, for the iPhones in ``writtenDevices``.
    private var written: [UUID: Written] = [:]
    /// The iPhones the cards in ``written`` went to: a new one gets them all again.
    private var writtenDevices: Set<UUID> = []
    private let log = Logger(subsystem: "com.mgiuditta.bubo", category: "remote")

    /// Creates the bridge of the Mac `macID`.
    ///
    /// - Parameters:
    ///   - devices: The paired iPhones now.
    ///   - isOn: Whether the Telecomando is on, the user's consent.
    ///   - diffStats: The diff of a Sessione, read when its card is written; `nil` when unknown.
    init(macID: UUID, macName: String, channel: any RemoteChannel, devices: @escaping () -> [PairedDevice],
         isOn: @escaping () -> Bool, macOnly: MacOnlyProjects,
         diffStats: @escaping (UUID) async -> SessionCard.DiffStats? = { _ in nil }) {
        self.macID = macID
        self.macName = macName
        self.channel = channel
        self.devices = devices
        self.isOn = isOn
        self.macOnly = macOnly
        self.diffStats = diffStats
    }

    /// The bridge of the Telecomando of `remote`, with the switch in `defaults`; always off in a build without the
    /// Telecomando.
    static func live(remote: PairingController, macOnly: MacOnlyProjects, sessions: SessionStore?,
                     defaults: UserDefaults = .standard) -> RemoteBridge {
        RemoteBridge(macID: remote.macID, macName: remote.macName, channel: remote.channel,
                     devices: { [weak remote] in remote?.devices ?? [] },
                     isOn: { ReleaseArea.remote.isAvailable() && defaults.bool(forKey: PairingController.isOnKey) }, macOnly: macOnly) { [weak sessions] id in
            await sessions?.diffStats(of: id)
        }
    }

    /// Publishes the Sessioni of `store` while they change, the Battito every minute and the cleanup every hour,
    /// until cancelled.
    func run(sessions store: SessionStore) async {
        async let cleanups: Void = cleanUpEveryHour()
        async let cards: Void = publishChanges(of: store)
        async let beats: Void = beatEveryMinute(of: store)
        async let sleeps: Void = beatAtSleep()
        async let wakes: Void = beatAtWake()
        _ = await (cleanups, cards, beats, sleeps, wakes)
    }

    /// Writes the card of each Sessione of `sessions` that changed, at most once every 5 s each, and deletes the
    /// cards of the Sessioni that no longer go out: Archiviate, solo Mac, deleted, or all with the Telecomando off.
    ///
    /// - Returns: When a card held back by the 5 s limit can be written; `nil` when none waits.
    @discardableResult
    func publish(_ sessions: [Session], now: Date = .now) async -> Date? {
        let paired = devices()
        let devices = isOn() ? paired : []
        if Set(devices.map(\.id)) != writtenDevices {
            // Turned off: what went out is withdrawn. A new iPhone gets every card; a gone one was revoked, and the
            // revocation deleted its records.
            if devices.isEmpty {
                _ = await delete(named: written.keys.map(Self.cardName) + [Self.heartbeatName], for: paired)
            }
            written = [:]
            writtenDevices = Set(devices.map(\.id))
        }
        guard !devices.isEmpty else { return nil }

        let shown = sessions.filter { $0.phase != .archiviata && !macOnly.isMacOnly($0.project) }
        let hidden = Set(written.keys).subtracting(shown.map(\.id))
        if !hidden.isEmpty, await delete(named: hidden.map(Self.cardName), for: devices) {
            for id in hidden { written[id] = nil }
        }

        var due: Date?
        for session in shown {
            var card = Self.card(of: session)
            let last = written[session.id]
            card.diff = last?.card.diff
            if let last, last.card == card, now.timeIntervalSince(last.date) < Self.cardRefresh { continue }
            if let last, now.timeIntervalSince(last.date) < Self.cardInterval {
                let next = last.date.addingTimeInterval(Self.cardInterval)
                due = min(due ?? next, next)
                continue
            }
            card.diff = await diffStats(session.id)
            var isWritten = true
            for device in devices {
                isWritten = await save(card, kind: .sessionCard, named: Self.cardName(of: session.id), for: device,
                                       now: now) && isWritten
            }
            if isWritten { written[session.id] = Written(card: card, date: now) }
        }
        return due
    }

    /// Writes the Battito for every paired iPhone; `isAsleep` when the Mac is going to sleep.
    func beat(isAsleep: Bool = false, now: Date = .now) async {
        guard isOn() else { return }
        let heartbeat = Heartbeat(macName: macName, sentAt: now, isAsleep: isAsleep)
        for device in devices() {
            await save(heartbeat, kind: .heartbeat, named: Self.heartbeatName, for: device, now: now)
        }
    }

    /// Deletes every record of this Mac older than 24 h.
    func cleanUp(now: Date = .now) async {
        do {
            try await channel.deleteRecords(of: macID, expiringBefore: now)
        } catch {
            log.error("Pulizia del Telecomando non riuscita: \(String(describing: error), privacy: .public)")
        }
    }

    /// The card of `session`, without its diff.
    static func card(of session: Session) -> SessionCard {
        let excerpt = (session.activity == .errore ? session.failure : nil) ?? session.summary
        return SessionCard(
            id: session.id,
            title: session.title,
            project: session.project.lastPathComponent,
            activity: SessionCard.Activity(rawValue: session.activity.rawValue) ?? .ferma,
            phase: SessionCard.Phase(rawValue: session.phase.rawValue) ?? .aperta,
            excerpt: excerpt.map { String($0.prefix(excerptLimit)) }
        )
    }

    private func publishChanges(of store: SessionStore) async {
        for await (sessions, _) in Observations({ [macOnly] in (store.sessions, macOnly.paths) }) {
            var due = await publish(sessions)
            while let next = due {
                try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
                if Task.isCancelled { return }
                due = await publish(store.sessions)
            }
        }
    }

    private func beatEveryMinute(of store: SessionStore) async {
        while !Task.isCancelled {
            await beat()
            // Also where the switch just turned on, or an iPhone just paired, gets the cards.
            await publish(store.sessions)
            try? await Task.sleep(for: .seconds(Self.heartbeatInterval))
        }
    }

    private func beatAtSleep() async {
        for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.willSleepNotification) {
            await beat(isAsleep: true)
        }
    }

    private func beatAtWake() async {
        for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
            await beat()
        }
    }

    private func cleanUpEveryHour() async {
        while !Task.isCancelled {
            await cleanUp()
            try? await Task.sleep(for: .seconds(Self.cleanupInterval))
        }
    }

    /// Deletes the records `names` of every pair of `devices`; returns whether they are gone.
    private func delete(named names: [String], for devices: [PairedDevice]) async -> Bool {
        let ids = devices.flatMap { device in names.map(Self.sealer(for: device).recordID(named:)) }
        guard !ids.isEmpty else { return true }
        do {
            try await channel.deleteRecords(ids)
            return true
        } catch {
            log.error("Record del Telecomando non cancellati: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Seals `value` for `device` and saves it; returns whether it was saved.
    @discardableResult
    private func save(_ value: some Encodable, kind: RemoteRecord.Kind, named name: String, for device: PairedDevice,
                      now: Date) async -> Bool {
        let sealer = Self.sealer(for: device)
        let id = sealer.recordID(named: name)
        do {
            try await channel.save(RemoteRecord(id: id, kind: kind, macID: macID, deviceID: device.id,
                                                expiresAt: now.addingTimeInterval(Self.recordLifetime),
                                                payload: sealer.seal(value, recordID: id)))
            return true
        } catch {
            log.error("Record \(kind.rawValue, privacy: .public) del Telecomando non scritto: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private static func cardName(of id: UUID) -> String {
        "sessionCard/\(id.uuidString)"
    }

    private static func sealer(for device: PairedDevice) -> RecordSealer {
        RecordSealer(key: SymmetricKey(data: device.recordKey))
    }
}

extension SessionStore {
    /// The files and lines the Sessione `id` changed since its branch started; `nil` when it has no copy yet or git
    /// fails.
    func diffStats(of id: UUID) async -> SessionCard.DiffStats? {
        guard let files = try? await changes(of: id) else { return nil }
        let hunks = files.flatMap(\.hunks)
        return SessionCard.DiffStats(files: files.count, addedLines: hunks.reduce(0) { $0 + $1.added },
                                     removedLines: hunks.reduce(0) { $0 + $1.removed })
    }
}
