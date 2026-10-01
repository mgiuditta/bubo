import Foundation

/// What Impostazioni › Diagnostica shows of the latest MetricKit day: launch, hangs, peak memory and hitches.
///
/// Read from the payload when it arrives and saved next to its JSON, so the section never parses Apple's JSON.
nonisolated struct DailyMetrics: Codable, Equatable, Sendable {
    /// The start of the day the metrics cover.
    var start: Date
    /// The end of the day the metrics cover.
    var end: Date
    /// The mean launch, up to `HUD interattivo` when MetricKit measured the extended launch; `nil` with no launch.
    var meanLaunch: Duration?
    /// The launches measured.
    var launchCount: Int
    /// The hangs of the main thread.
    var hangCount: Int
    /// The time the hangs lasted in all.
    var hangTime: Duration
    /// The peak memory, in bytes; `nil` when MetricKit did not report it.
    var peakMemory: Int64?
    /// The share of animation time spent hitching, from 0 to 1; `nil` when MetricKit did not report it.
    var hitchRatio: Double?
}

/// One bucket of a MetricKit histogram of durations.
nonisolated struct DurationBucket: Equatable, Sendable {
    /// The lower bound of the bucket.
    var start: Duration
    /// The upper bound of the bucket.
    var end: Duration
    /// The samples that fell in the bucket.
    var count: Int
}

nonisolated extension [DurationBucket] {
    /// The samples in all the buckets.
    var sampleCount: Int {
        reduce(0) { $0 + $1.count }
    }

    /// The sum of the samples, each counted at the middle of its bucket.
    var total: Duration {
        reduce(.zero) { $0 + ($1.start + $1.end) / 2 * $1.count }
    }

    /// The mean of the samples, each counted at the middle of its bucket; `nil` with no samples.
    var mean: Duration? {
        sampleCount > 0 ? total / sampleCount : nil
    }
}
