import Foundation
import MetricKit
import OSLog

/// Receives MetricKit's payloads and keeps them on this Mac; nothing is ever sent.
///
/// It also extends MetricKit's launch measurement from the first frame to `HUD interattivo`.
// ponytail: MXMetricManager is deprecated from the macOS 27.2 SDK; MetricManager when the target reaches 27.
nonisolated final class MetricsCollector: NSObject, MXMetricManagerSubscriber, Sendable {
    /// The collector of the app, saving into `Application Support/Bubo/Diagnostica/`.
    static let shared = MetricsCollector()

    private static let launchTask = MXLaunchTaskID(rawValue: "com.mgiuditta.bubo.hud-interattivo")

    private let store: DiagnosticsStore?

    private override init() {
        do {
            store = try DiagnosticsStore.makeDefault()
        } catch {
            Logger.diagnostics.error("Diagnostica unavailable: \(error)")
            store = nil
        }
    }

    /// Asks MetricKit to keep measuring the launch after the first frame; call it before the first frame.
    func extendLaunch() {
        do {
            try MXMetricManager.extendLaunchMeasurement(forTaskID: Self.launchTask)
        } catch {
            Logger.diagnostics.error("Launch not extended: \(error)")
        }
    }

    /// Ends the launch MetricKit measures and subscribes to its payloads; call it once, at `HUD interattivo`.
    func finishLaunch() {
        do {
            try MXMetricManager.finishExtendedLaunchMeasurement(forTaskID: Self.launchTask)
        } catch {
            Logger.diagnostics.error("Extended launch not finished: \(error)")
        }
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        Logger.diagnostics.notice("Metric payloads received: \(payloads.count)")
        for payload in payloads {
            do {
                try store?.saveMetrics(payload.jsonRepresentation(), summary: DailyMetrics(payload))
            } catch {
                Logger.diagnostics.error("Metric payload not saved: \(error)")
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Logger.diagnostics.notice("Diagnostic payloads received: \(payloads.count)")
        for payload in payloads {
            do {
                try store?.saveDiagnostics(payload.jsonRepresentation(), endingAt: payload.timeStampEnd)
            } catch {
                Logger.diagnostics.error("Diagnostic payload not saved: \(error)")
            }
        }
    }
}

nonisolated extension DailyMetrics {
    /// The summary of `payload`.
    init(_ payload: MXMetricPayload) {
        let launch = payload.applicationLaunchMetrics
        let extended = launch.map { [DurationBucket]($0.histogrammedExtendedLaunch) } ?? []
        let firstDraw = launch.map { [DurationBucket]($0.histogrammedTimeToFirstDraw) } ?? []
        let launches = extended.sampleCount > 0 ? extended : firstDraw
        let responsiveness = payload.applicationResponsivenessMetrics
        let hangs = responsiveness.map { [DurationBucket]($0.histogrammedApplicationHangTime) } ?? []
        self.init(start: payload.timeStampBegin, end: payload.timeStampEnd, meanLaunch: launches.mean,
                  launchCount: launches.sampleCount, hangCount: hangs.sampleCount, hangTime: hangs.total,
                  peakMemory: payload.memoryMetrics.map { Int64($0.peakMemoryUsage.converted(to: .bytes).value) },
                  hitchRatio: payload.animationMetrics?.hitchTimeRatio.value)
    }
}

nonisolated extension [DurationBucket] {
    /// The buckets of `histogram`.
    init(_ histogram: MXHistogram<UnitDuration>) {
        self = histogram.bucketEnumerator.compactMap { element in
            guard let bucket = element as? MXHistogramBucket<UnitDuration> else { return nil }
            return DurationBucket(start: .seconds(bucket.bucketStart.converted(to: .seconds).value),
                                  end: .seconds(bucket.bucketEnd.converted(to: .seconds).value),
                                  count: bucket.bucketCount)
        }
    }
}
