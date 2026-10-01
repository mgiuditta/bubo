import Foundation
import os

/// Finds the Sessioni's servers after an event, never at rest (spec 15).
///
/// An event, a `localhost` URL or an OSC 133 mark in a terminal, the end of the agent's Bash, or the exit of a server
/// already found, starts a burst of ``ListeningSocket/scan()`` that thins out over 8 s. With no event, nothing runs.
@Observable
final class PortWatcher {
    /// The servers of each Sessione, by port.
    private(set) var servers: [UUID: [ListeningSocket]] = [:]
    /// How many scans ran, for the tests: 0 at rest.
    @ObservationIgnored private(set) var scanCount = 0

    /// The Sessioni that can own a server, read at each scan.
    @ObservationIgnored var owners: () -> [ServerAttribution.Owner] = { [] }
    /// Called with the servers of each Sessione when they change.
    @ObservationIgnored var onChange: ([UUID: [ListeningSocket]]) -> Void = { _ in }
    /// Reads the listening sockets; the kernel's outside tests.
    @ObservationIgnored var scan: @Sendable () -> [ListeningSocket] = ListeningSocket.scan

    /// When to scan after the last event: close at first, for a port within 1 s, then sparser for slow servers.
    static let schedule: [Duration] = [.milliseconds(50), .milliseconds(250), .milliseconds(500), .seconds(1),
                                       .seconds(2), .seconds(4), .seconds(8)]
    /// The shortest gap between two scans, while a server keeps writing URLs.
    static let minimumGap = Duration.milliseconds(250)

    @ObservationIgnored private var lastEvent: ContinuousClock.Instant?
    @ObservationIgnored private var lastScan: ContinuousClock.Instant?
    @ObservationIgnored private var burst: Task<Void, Never>?
    /// The exits of the servers found, which may restart.
    @ObservationIgnored private var exits: [pid_t: any DispatchSourceProcess] = [:]

    /// Something may have started or stopped a server: scans again over the next seconds.
    func notice() {
        lastEvent = .now
        burst?.cancel()
        burst = Task { await scanUntilQuiet() }
    }

    private func scanUntilQuiet() async {
        while let lastEvent {
            let scanned = lastScan ?? lastEvent - .seconds(1)
            guard let next = Self.schedule.lazy.map({ lastEvent + $0 }).first(where: { $0 > scanned }) else { break }
            do { try await Task.sleep(until: max(next, scanned + Self.minimumGap)) } catch { return }
            let sockets = await Self.scan(with: scan)
            // A newer event started another burst while this scan ran: its sockets may predate the event.
            if Task.isCancelled { return }
            lastScan = .now
            scanCount += 1
            update(with: sockets)
        }
        burst = nil
    }

    @concurrent
    private static func scan(with scan: @Sendable () -> [ListeningSocket]) async -> [ListeningSocket] {
        scan()
    }

    private func update(with sockets: [ListeningSocket]) {
        let found = ServerAttribution.servers(sockets, among: owners())
        if found != servers {
            Logger.servers.debug("Servers: \(found.mapValues { $0.map(\.port) }, privacy: .public)")
            servers = found
            onChange(found)
        }
        watchExits(of: Set(found.values.joined().map(\.pid)))
    }

    /// Watches the exit of each server's process, which starts a burst: it may come back, or its label goes.
    private func watchExits(of pids: Set<pid_t>) {
        for (pid, source) in exits where !pids.contains(pid) {
            source.cancel()
            exits[pid] = nil
        }
        for pid in pids where exits[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.exits.removeValue(forKey: pid)?.cancel()
                    self?.notice()
                }
            }
            source.activate()
            exits[pid] = source
        }
    }
}

extension Logger {
    nonisolated static let servers = Logger(subsystem: "com.mgiuditta.bubo", category: "servers")
}
