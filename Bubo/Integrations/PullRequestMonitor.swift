import Foundation

/// Reads the open pull requests of the Sessioni (spec 16): only while Bubo is in front, at once when it comes back
/// and then every ``interval``; never at rest nor in the background, so no `gh` runs then.
@Observable
final class PullRequestMonitor {
    /// How long between two readings while Bubo is in front.
    static let interval = Duration.seconds(30)

    /// What was last read of each Sessione's open pull request.
    private(set) var statuses: [UUID: PullRequestStatus] = [:]
    /// Why the last Aggiorna PR of each Sessione failed, with the command that fixes it when there is one.
    private(set) var updateFailures: [UUID: (message: String, remedy: String?)] = [:]
    /// The Sessioni whose Aggiorna PR is in progress.
    private(set) var updating: Set<UUID> = []
    /// The user's `gh`, which reads the pull requests.
    @ObservationIgnored var cli = GitHubCLI()
    /// The readings while Bubo is in front; `nil` otherwise.
    @ObservationIgnored private var polling: Task<Void, Never>?

    /// Whether the readings go on: only while Bubo is in front.
    var isPolling: Bool { polling != nil }

    /// Starts `read` at once and every ``interval`` while `isForeground`; stops it otherwise.
    func follow(isForeground: Bool, read: @escaping () async -> Void) {
        polling?.cancel()
        polling = nil
        guard isForeground else { return }
        polling = Task {
            while !Task.isCancelled {
                await read()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// Keeps `status` as what was last read of the pull request of the Sessione `id`.
    func record(_ status: PullRequestStatus, for id: UUID) {
        if statuses[id] != status { statuses[id] = status }
    }

    /// Notes that the Sessione `id` has nothing its pull request lacks, after Aggiorna PR.
    func markUpToDate(_ id: UUID) {
        statuses[id]?.isBehind = false
    }

    /// Notes that Aggiorna PR of the Sessione `id` started, or ended with `failure`.
    func noteUpdate(of id: UUID, isRunning: Bool, failure: (message: String, remedy: String?)? = nil) {
        if isRunning { updating.insert(id) } else { updating.remove(id) }
        updateFailures[id] = failure
    }

    /// Forgets the pull request of the Sessione `id`, merged, closed or gone.
    func forget(_ id: UUID) {
        statuses[id] = nil
        updateFailures[id] = nil
    }

    /// Forgets every pull request but those of `ids`.
    func keep(only ids: Set<UUID>) {
        for id in statuses.keys where !ids.contains(id) { forget(id) }
    }
}
