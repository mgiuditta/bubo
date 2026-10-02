import Foundation
import os
import Synchronization

/// What Bubo remembers about the plugins' updates between launches: the last check, the commits of the git sources,
/// the versions `claude plugin update` left as they were, and the code on the Mac each plugin had when last seen.
///
/// Kept in Bubo's Application Support folder, never in `~/.claude`, which only `claude` writes.
nonisolated final class PluginUpdateStore: Sendable {
    /// The remembered state.
    struct State: Codable, Equatable, Sendable {
        /// When the last daily check started.
        var lastCheck: Date?
        /// The commit each git source points to, by ``PluginUpdateChecker/tipKey(for:)``, from `git ls-remote`.
        var tips: [String: String] = [:]
        /// The version `claude plugin update` left as it was, by plugin: the author did not change it.
        var dismissed: [String: String] = [:]
        /// The components running code on the Mac each installed plugin had when last seen, by plugin.
        var seenExecutables: [String: [String]] = [:]
    }

    /// The JSON file; `nil` to keep the state in memory only, as the tests do.
    let file: URL?
    private let state: Mutex<State>

    /// Creates a store kept in `file`, reading what it has; an unreadable file starts empty.
    init(file: URL?) {
        self.file = file
        var initial = State()
        if let file, let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            initial = (try? decoder.decode(State.self, from: data)) ?? State()
        }
        state = Mutex(initial)
    }

    /// The store in Bubo's Application Support folder.
    static let standard = PluginUpdateStore(file: URL.applicationSupportDirectory.appending(path: "Bubo/Aggiornamenti dei plugin.json"))

    /// A store in memory only.
    static func inMemory() -> PluginUpdateStore { PluginUpdateStore(file: nil) }

    /// The state now.
    var current: State { state.withLock { $0 } }

    /// Changes the state with `body` and saves it.
    func change(_ body: (inout State) -> Void) {
        let changed = state.withLock { state in
            body(&state)
            return state
        }
        save(changed)
    }

    /// Records `now` as the start of a check, when the last one started more than `interval` before.
    ///
    /// - Returns: Whether the caller is the one to check: two callers at once never both get `true`.
    func claimCheck(at now: Date, interval: TimeInterval) -> Bool {
        let claimed: State? = state.withLock { state in
            if let last = state.lastCheck, now.timeIntervalSince(last) < interval, now >= last { return nil }
            state.lastCheck = now
            return state
        }
        if let claimed { save(claimed) }
        return claimed != nil
    }

    private func save(_ state: State) {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: file, options: .atomic)
        } catch {
            Logger.plugins.error("Plugin update state not saved: \(String(describing: error), privacy: .public)")
        }
    }
}
