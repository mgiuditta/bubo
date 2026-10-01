import Foundation
import os

/// Decides when the bridge keeps a `claude` ready for the panel of the configuration, so that it opens within 1 s (#311).
///
/// The spare (~250 MB) starts only `launchDelay` after the HUD is interactive, never during launch (spec 25), and only
/// once there is a Progetto to inspect. It has the settings of the Progetto last shown in the panel, or else of the
/// newest Sessione's. Each read of the panel uses it up, so another starts right after. Under memory pressure it is
/// closed, and it comes back once the pressure is over.
final class ConfigurationSpare {
    /// How long after the HUD is interactive the first spare may start.
    static let launchDelay = Duration.seconds(10)

    /// Creates the policy; nothing starts before ``startAfterLaunch()``.
    ///
    /// - Parameters:
    ///   - delay: How long ``startAfterLaunch()`` waits before the first spare.
    ///   - project: The Progetto to keep a spare for when the panel has not been opened yet; `nil` for none.
    ///   - warm: Starts a spare with the settings of a Progetto, replacing the one before.
    ///   - cool: Closes the spare.
    init(delay: Duration = launchDelay, project: @escaping () -> URL?,
         warm: @escaping (URL) async throws -> Void, cool: @escaping () async throws -> Void) {
        self.delay = delay
        self.project = project
        self.warm = warm
        self.cool = cool
    }

    private let delay: Duration
    private let project: () -> URL?
    private let warm: (URL) async throws -> Void
    private let cool: () async throws -> Void
    /// The wait from the HUD interactive to the first spare; `nil` until ``startAfterLaunch()``.
    private(set) var launch: Task<Void, Never>?
    /// The last `warm` or `cool` sent; each waits for the one before, so they reach the bridge in order.
    private(set) var lastCommand: Task<Void, Never>?
    private var isLaunched = false
    private var isMemoryLow = false
    /// The Progetto of the spare asked for, `nil` when none should be running.
    private var spareProject: URL?
    /// The Progetto last shown in the panel.
    private var shownProject: URL?
    private var memoryPressure: (any DispatchSourceMemoryPressure)?

    /// Starts the first spare `delay` from now; call it when the HUD is interactive. Later calls do nothing.
    func startAfterLaunch() {
        guard launch == nil else { return }
        launch = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            isLaunched = true
            watchMemoryPressure()
            update()
        }
    }

    /// The configuration of `project`, read by `read` with the spare if it has the same settings; then a new spare.
    func configuration(of project: URL, read: (URL) async throws -> ClaudeConfiguration) async throws
        -> ClaudeConfiguration {
        shownProject = project
        // Used up by this read, or replaced by one with the settings of `project`.
        defer {
            spareProject = nil
            update()
        }
        return try await read(project)
    }

    /// Closes the spare while the memory is under pressure, and allows it again once `event` is `.normal`.
    func memoryPressureChanged(to event: DispatchSource.MemoryPressureEvent) {
        isMemoryLow = !event.isDisjoint(with: [.warning, .critical])
        update()
    }

    private func watchMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let event = self.memoryPressure?.data else { return }
                self.memoryPressureChanged(to: event)
            }
        }
        source.activate()
        memoryPressure = source
    }

    /// Asks the bridge for the spare that should run now, if it is not the one already asked for.
    private func update() {
        let wanted = isLaunched && !isMemoryLow ? shownProject ?? project() : nil
        guard wanted != spareProject else { return }
        spareProject = wanted
        let previous = lastCommand
        lastCommand = Task { [warm, cool] in
            await previous?.value
            do {
                if let wanted { try await warm(wanted) } else { try await cool() }
            } catch {
                Logger.agent.notice("Configuration spare not updated: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
