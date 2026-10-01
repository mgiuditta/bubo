import Foundation

/// What Bubo wrote to its Orb frame log (`-orbFrameLog <path>`): one line per frame drawn, its GPU time in seconds.
///
/// Built into `BuboTests` too, which check it against what the app writes.
nonisolated struct FrameLog {
    /// The GPU time of every frame drawn, in seconds, oldest first.
    let gpuTimes: [Double]

    /// Reads the log in `text`; a last line still being written, without its newline, is left out.
    init(text: String) {
        let finished = text.lastIndex(of: "\n").map { text[...$0] } ?? ""
        gpuTimes = finished.split(separator: "\n").compactMap { Double($0) }
    }

    /// Reads the log in the file at `url`; a missing file is an empty log, since Bubo has drawn nothing yet.
    init(contentsOf url: URL) throws {
        do {
            self.init(text: try String(contentsOf: url, encoding: .utf8))
        } catch CocoaError.fileReadNoSuchFile {
            self.init(text: "")
        }
    }

    /// How many frames Bubo has drawn.
    var frameCount: Int { gpuTimes.count }
}

nonisolated extension Collection where Element == Double {
    /// The 95th percentile by nearest rank, or `nil` when the collection is empty.
    ///
    /// - Complexity: O(*n* log *n*), where *n* is the length of the collection.
    func percentile95() -> Double? {
        guard !isEmpty else { return nil }
        let rank = Int((0.95 * Double(count)).rounded(.up))
        return sorted()[rank - 1]
    }
}
