import Foundation

/// Runs the plugins' update check once a day, also with the Plugin window closed, when macOS finds it convenient:
/// deferrable, at utility priority, like any background maintenance (spec 20).
@MainActor final class PluginUpdateScheduler {
    private let checker: PluginUpdateChecker
    private let activity = NSBackgroundActivityScheduler(identifier: "com.mgiuditta.bubo.plugin-updates")

    /// Creates a scheduler that runs `checker`.
    init(checker: PluginUpdateChecker) {
        self.checker = checker
    }

    /// Schedules the check every day; it runs only when the last one is more than a day old, so opening the Plugin
    /// window in between does not repeat it.
    func start() {
        activity.repeats = true
        // More often than the check: a Bubo quit and launched every day would otherwise never reach a full day.
        activity.interval = PluginUpdateChecker.interval / 4
        activity.tolerance = 60 * 60
        activity.qualityOfService = .utility
        let checker = checker
        activity.schedule { completion in
            Task {
                await checker.checkIfDue()
                completion(.finished)
            }
        }
    }

    /// Stops the schedule.
    func stop() {
        activity.invalidate()
    }
}
