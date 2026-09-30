import Synchronization
import XCTest

/// Measurements reported by the recording metrics, kept so a test can compare
/// them with `PerfBudgets` after `measure` returns.
///
/// XCTest copies a metric for each iteration, so the copies share this store
/// instead of their own state.
nonisolated enum RecordedMeasurements {
    private static let storage = Mutex<[RecordedMeasurement]>([])

    /// Forgets every measurement recorded so far.
    static func reset() {
        storage.withLock { $0.removeAll() }
    }

    /// Records the measurements of one iteration.
    static func append(_ measurements: [XCTPerformanceMeasurement]) {
        let recorded = measurements.map {
            RecordedMeasurement(identifier: $0.identifier, value: $0.value.value)
        }
        storage.withLock { $0.append(contentsOf: recorded) }
    }

    /// The values recorded under `identifier`, one per iteration, oldest first.
    ///
    /// May start with a warm-up iteration that XCTest leaves out of its
    /// results, so take the last `iterationCount` values.
    static func values(for identifier: String) -> [Double] {
        storage.withLock { $0.filter { $0.identifier == identifier }.map(\.value) }
    }
}

/// One value reported by a metric, in its own unit.
nonisolated struct RecordedMeasurement: Sendable {
    /// The metric's identifier, such as `com.apple.dt.XCTMetric_Memory.physical`.
    let identifier: String
    /// The value, in the unit the metric reports it in.
    let value: Double
}

/// A metric that reports what another metric reports, and records it.
///
/// XCTest metrics cannot be subclassed outside XCTest, and XCTest talks to its
/// own metrics through private methods too, so every message this class does
/// not implement goes to the wrapped metric.
nonisolated final class RecordingMetric: NSObject, XCTMetric {
    private let base: any XCTMetric

    /// Creates a metric that records what `base` reports.
    init(_ base: any XCTMetric) {
        self.base = base
    }

    func copy(with zone: NSZone? = nil) -> Any {
        RecordingMetric(base.copy(with: zone) as! any XCTMetric)
    }

    func reportMeasurements(
        from startTime: XCTPerformanceMeasurementTimestamp,
        to endTime: XCTPerformanceMeasurementTimestamp
    ) throws -> [XCTPerformanceMeasurement] {
        let measurements = try base.reportMeasurements(from: startTime, to: endTime)
        RecordedMeasurements.append(measurements)
        return measurements
    }

    func willBeginMeasuring() {
        base.willBeginMeasuring?()
    }

    func didStopMeasuring() {
        base.didStopMeasuring?()
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (base as AnyObject).responds(to: selector)
    }

    override func conforms(to aProtocol: Protocol) -> Bool {
        super.conforms(to: aProtocol) || (base as AnyObject).conforms(to: aProtocol)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        base
    }
}
