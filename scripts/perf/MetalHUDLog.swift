import Foundation

/// The frames in the `metal-HUD:` lines that Metal writes to the system log with `MTL_HUD_LOG_ENABLED=1`.
///
/// A line is `metal-HUD: <frame number>,<two more header fields>,` then one pair per frame logged: the interval
/// since the previous presentation and the GPU time, both in milliseconds. Metal repeats most pairs, which leaves
/// the percentiles as they are.
nonisolated struct MetalHUDLog {
    /// One frame logged by the Metal HUD.
    struct Frame: Equatable, Sendable {
        /// The time since the previous presentation, in milliseconds.
        let presentationInterval: Double
        /// The GPU time of the frame, in milliseconds.
        let gpuTime: Double
    }

    /// The frames with a GPU time, oldest first; the first frames, before Metal times the GPU, are left out.
    let frames: [Frame]

    /// Reads the frames in `lines`; lines that are not `metal-HUD:` lines are skipped.
    init(lines: some Sequence<some StringProtocol>) {
        frames = lines.flatMap { line -> [Frame] in
            guard let start = line.range(of: Self.prefix)?.upperBound else { return [] }
            let numbers = line[start...].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let pairs = numbers.dropFirst(Self.headerFieldCount)
            return stride(from: pairs.startIndex, to: pairs.endIndex - 1, by: 2).map { index in
                Frame(presentationInterval: pairs[index], gpuTime: pairs[index + 1])
            }
        }.filter { $0.gpuTime > 0 }
    }

    /// The 95th percentile of the GPU time, in milliseconds, or `nil` without frames.
    var gpuTimePercentile95: Double? {
        frames.map(\.gpuTime).percentile95()
    }

    /// The mean frame rate from the presentation intervals, or `nil` without frames.
    var framesPerSecond: Double? {
        guard !frames.isEmpty else { return nil }
        let meanInterval = frames.map(\.presentationInterval).reduce(0, +) / Double(frames.count)
        return meanInterval > 0 ? 1000 / meanInterval : nil
    }

    private static let prefix = "metal-HUD:"
    private static let headerFieldCount = 3
}
