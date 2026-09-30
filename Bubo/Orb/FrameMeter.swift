import Foundation

/// Measures frames per second and GPU time per frame over half-second windows.
nonisolated struct FrameMeter {
    /// One window's measurements.
    struct Reading: Equatable {
        /// Frames drawn per second.
        var framesPerSecond: Double
        /// The mean GPU time of one frame, in seconds; `nil` if no frame reported it.
        var gpuTime: TimeInterval?
    }

    /// How long each window lasts, in seconds.
    static let window: TimeInterval = 0.5

    private var windowStart: TimeInterval?
    private var frames = 0
    private var gpuTotal: TimeInterval = 0
    private var gpuSamples = 0

    /// Counts a frame drawn at `time` and returns the reading when a window ends.
    mutating func recordFrame(at time: TimeInterval) -> Reading? {
        guard let windowStart else {
            windowStart = time
            return nil
        }
        frames += 1
        let elapsed = time - windowStart
        guard elapsed >= Self.window else { return nil }
        let reading = Reading(framesPerSecond: Double(frames) / elapsed,
                              gpuTime: gpuSamples > 0 ? gpuTotal / Double(gpuSamples) : nil)
        self = FrameMeter()
        self.windowStart = time
        return reading
    }

    /// Adds the GPU time of one completed frame to the current window.
    mutating func recordGPUTime(_ duration: TimeInterval) {
        gpuTotal += duration
        gpuSamples += 1
    }
}
