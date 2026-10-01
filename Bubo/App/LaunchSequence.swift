import Foundation
import os

/// Everything that starts after `HUD interattivo`, in order: the bridge, the detection of `claude` during onboarding,
/// the Indice's FSEvents, the subscription to MetricKit, the spare `claude` of the configuration panel 10 s later, then
/// the Cronologia CLI once the launch has settled.
///
/// The only place for work after launch: before the HUD nothing heavy runs, and no `claude` ever starts here outside
/// the onboarding and the configuration panel's spare (spec 25 and 26). The Quota is not read here: the HUD shows the last one saved until a Domanda, a
/// Sessione or the user opening the HUD brings a fresh one.
final class LaunchSequence {
    /// Creates a sequence of the given steps, run once by `start()`.
    ///
    /// - Parameters:
    ///   - startBridge: Starts the bridge without asking it anything: no `claude` starts with it.
    ///   - isOnboarding: Whether onboarding is still on, read when the sequence runs.
    ///   - detectClaude: Finds `claude` and reads its version and login; only during onboarding.
    ///   - keepIndexFresh: Keeps the Indice and the Secondo cervello in step with the disk; never returns.
    ///   - subscribeToMetrics: Subscribes to MetricKit's payloads.
    ///   - startConfigurationSpare: Starts the wait before the configuration panel's spare `claude`.
    ///   - keepCLIHistoryFresh: Copies the Cronologia CLI, through the bridge, a minute after the other steps; never
    ///     returns.
    init(startBridge: @escaping () async -> Void,
         isOnboarding: @escaping () -> Bool,
         detectClaude: @escaping () async -> Void,
         keepIndexFresh: @escaping () async -> Void,
         subscribeToMetrics: @escaping () -> Void,
         startConfigurationSpare: @escaping () -> Void,
         keepCLIHistoryFresh: @escaping () async -> Void) {
        self.startBridge = startBridge
        self.isOnboarding = isOnboarding
        self.detectClaude = detectClaude
        self.keepIndexFresh = keepIndexFresh
        self.subscribeToMetrics = subscribeToMetrics
        self.startConfigurationSpare = startConfigurationSpare
        self.keepCLIHistoryFresh = keepCLIHistoryFresh
    }

    private let startBridge: () async -> Void
    private let isOnboarding: () -> Bool
    private let detectClaude: () async -> Void
    private let keepIndexFresh: () async -> Void
    private let subscribeToMetrics: () -> Void
    private let startConfigurationSpare: () -> Void
    private let keepCLIHistoryFresh: () async -> Void
    private var hasRun = false

    /// Emits `HUD interattivo` and runs the steps, the first time it is called; never again.
    ///
    /// The steps outlive the view that calls it: closing the HUD does not stop them.
    ///
    /// - Returns: The task running the steps, done once each has started.
    @discardableResult
    func start() -> Task<Void, Never> {
        Task { await run() }
    }

    /// Emits `HUD interattivo` and runs the steps in order, the first time it is called; returns once each has started.
    func run() async {
        guard !hasRun else { return }
        hasRun = true
        Signposts.markHUDInteractive()
        await Signposts.measure(.deferredLaunch) {
            await startBridge()
            if isOnboarding() {
                await detectClaude()
            }
            Task(priority: .utility) { [keepIndexFresh] in await keepIndexFresh() }
            subscribeToMetrics()
            startConfigurationSpare()
        }
        // The copy of the Cronologia CLI waits for the launch to settle.
        Task(priority: .utility) { [keepCLIHistoryFresh] in
            try? await Task.sleep(for: .seconds(60))
            await keepCLIHistoryFresh()
        }
    }
}
