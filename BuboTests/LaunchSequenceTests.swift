import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct LaunchSequenceTests {
    /// The steps the sequence ran, in order.
    final class Steps {
        var names: [String] = []
        var metricsSubscriptions = 0
        var spareStarts = 0
        /// Resumed when the Indice's step runs, which happens in a task of its own.
        var indexStarted: CheckedContinuation<Void, Never>?
    }

    static func sequence(_ steps: Steps, isOnboarding: Bool) -> LaunchSequence {
        LaunchSequence {
            steps.names.append("ponte")
        } isOnboarding: {
            isOnboarding
        } detectClaude: {
            steps.names.append("claude")
        } keepIndexFresh: {
            steps.names.append("FSEvents")
            steps.indexStarted?.resume()
        } subscribeToMetrics: {
            steps.metricsSubscriptions += 1
        } startConfigurationSpare: {
            steps.spareStarts += 1
        } keepCLIHistoryFresh: {
        }
    }

    static func runUntilIndexStarts(_ sequence: LaunchSequence, _ steps: Steps) async {
        await withCheckedContinuation { continuation in
            steps.indexStarted = continuation
            Task { await sequence.run() }
        }
    }

    @Test func duringOnboardingTheStepsRunInTheSpecOrder() async {
        let steps = Steps()
        let sequence = Self.sequence(steps, isOnboarding: true)

        await Self.runUntilIndexStarts(sequence, steps)

        #expect(steps.names == ["ponte", "claude", "FSEvents"])
    }

    // Spec 26: after onboarding no `claude` starts at launch.
    @Test func afterOnboardingClaudeIsNotDetected() async {
        let steps = Steps()
        let sequence = Self.sequence(steps, isOnboarding: false)

        await Self.runUntilIndexStarts(sequence, steps)

        #expect(steps.names == ["ponte", "FSEvents"])
    }

    // Spec 25: MetricKit is subscribed to in the sequence, after the other steps have started.
    @Test func metricKitIsSubscribedToOnceTheStepsHaveStarted() async {
        let steps = Steps()
        let sequence = Self.sequence(steps, isOnboarding: true)

        await sequence.run()

        #expect(steps.metricsSubscriptions == 1)
        #expect(steps.names.starts(with: ["ponte", "claude"]))
    }

    // Spec 25: the configuration panel's spare waits for the launch, then its own delay.
    @Test func theConfigurationSpareStartsWithTheSequence() async {
        let steps = Steps()
        let sequence = Self.sequence(steps, isOnboarding: false)

        await sequence.run()
        await sequence.run()

        #expect(steps.spareStarts == 1)
    }

    // Later appearances of the HUD are not launches.
    @Test func theStepsRunOnlyOnce() async {
        let steps = Steps()
        let sequence = Self.sequence(steps, isOnboarding: false)

        await Self.runUntilIndexStarts(sequence, steps)
        await sequence.run()

        #expect(steps.names == ["ponte", "FSEvents"])
        #expect(steps.metricsSubscriptions == 1)
    }
}
