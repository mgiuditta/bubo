import Foundation
import os

/// Ricarica plugin for the turns in progress (spec 20, #212).
///
/// Each turn is a `claude` of its own that loads the plugins when it starts, so a Sessione at rest takes the new ones at
/// its next turn: only a turn in progress can be left with the plugins of before. A generation grows at each change of
/// the plugins; a turn that started at an older one is outdated until Ricarica plugin, which asks `claude` to stop if it
/// would lose the prompt cache, and Ricarica comunque, which does not.
@Observable final class PluginReloader {
    /// Where a turn in progress is with Ricarica plugin.
    enum State: Equatable {
        /// It has the plugins of before.
        case outdated
        /// Ricarica plugin is in progress.
        case reloading
        /// `claude` did not reload, to keep the prompt cache: Ricarica comunque does, with this impact if known.
        case held(PluginReload.CacheImpact?)
    }

    /// Reloads the plugins of the turn in progress of a Sessione, forced or stopping on a cache impact.
    typealias Reload = @MainActor (_ session: UUID, _ isForced: Bool) async throws -> PluginReload
    /// The changes of the plugins on disk, with the settings of these folders.
    typealias Changes = @MainActor (_ folders: [URL]) -> AsyncStream<Void>

    /// Grows at each change of the plugins: a write of the Plugin window that succeeded, or one seen on disk.
    private(set) var generation = 0
    /// The generation each turn in progress has its plugins from, by Sessione.
    private var turns: [UUID: Int] = [:]
    /// The turns reloading, or whose reload `claude` held.
    private var reloads: [UUID: State] = [:]
    /// The folder each turn in progress works in, whose settings it loads.
    @ObservationIgnored private var folders: [UUID: URL] = [:]
    @ObservationIgnored private let reload: Reload
    @ObservationIgnored private let changes: Changes
    /// The changes on disk followed while a turn is in progress, even with the Plugin window closed (#496), and the
    /// folders whose settings they include.
    @ObservationIgnored private var watch: (folders: Set<URL>, task: Task<Void, Never>)?

    /// Creates a reloader that reloads a turn with `reload` and follows `changes` while a turn is in progress.
    init(reload: @escaping Reload = { _, _ in throw CancellationError() },
         changes: @escaping Changes = { _ in AsyncStream { $0.finish() } }) {
        self.reload = reload
        self.changes = changes
    }

    /// Whether the changes on disk are followed: only while a turn is in progress.
    var isWatching: Bool { watch != nil }

    /// The plugins changed: every turn in progress now has the plugins of before.
    func pluginsDidChange() {
        generation += 1
    }

    /// The turn of `session` started in `folder`, with the plugins as they are now.
    func turnDidStart(in session: UUID, folder: URL? = nil) {
        turns[session] = generation
        reloads[session] = nil
        folders[session] = folder
        followChanges()
    }

    /// The turn of `session` ended: the next one loads the plugins by itself.
    func turnDidEnd(in session: UUID) {
        turns[session] = nil
        reloads[session] = nil
        folders[session] = nil
        followChanges()
    }

    /// Follows the changes on disk with the settings of the turns' folders, or stops once no turn is in progress.
    private func followChanges() {
        let wanted = turns.isEmpty ? nil : Set(folders.values)
        guard wanted != watch?.folders else { return }
        watch?.task.cancel()
        watch = nil
        guard let wanted else { return }
        let changes = self.changes(wanted.sorted { $0.path < $1.path })
        watch = (wanted, Task { [weak self] in
            for await _ in changes { self?.pluginsDidChange() }
        })
    }

    /// Where the turn in progress of `session` is with Ricarica plugin; `nil` when it has the current plugins, or no
    /// turn is in progress.
    func state(of session: UUID) -> State? {
        guard let turn = turns[session], turn < generation else { return nil }
        return reloads[session] ?? .outdated
    }

    /// The Sessioni whose turn in progress has the plugins of before.
    var outdatedSessions: Set<UUID> {
        Set(turns.filter { $0.value < generation }.keys)
    }

    /// Reloads the plugins of the turn in progress of `session`: Ricarica plugin, or Ricarica comunque once `claude`
    /// held it. Nothing while it is already reloading, or once the turn ended.
    func reloadPlugins(in session: UUID) async {
        guard let state = state(of: session), state != .reloading else { return }
        let isForced = if case .held = state { true } else { false }
        let target = generation
        reloads[session] = .reloading
        do {
            let result = try await reload(session, isForced)
            guard turns[session] != nil else { return }
            if result.isHeld {
                reloads[session] = .held(result.cacheImpact)
            } else {
                turns[session] = target
                reloads[session] = nil
            }
        } catch {
            // The turn may have ended meanwhile; otherwise Ricarica plugin comes back.
            if turns[session] != nil { reloads[session] = nil }
            Logger.plugins.notice("Plugins not reloaded: \(String(describing: error), privacy: .public)")
        }
    }

    /// Ricarica tutte: reloads every turn with the plugins of before, except those `claude` held, which only their own
    /// Ricarica comunque applies.
    func reloadAllPlugins() async {
        let outdated = outdatedSessions.filter { state(of: $0) == .outdated }
        await withDiscardingTaskGroup { group in
            for session in outdated {
                group.addTask { await self.reloadPlugins(in: session) }
            }
        }
    }
}
