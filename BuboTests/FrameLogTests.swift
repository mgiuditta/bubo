import Foundation
import Testing
@testable import Bubo

struct FrameLogTests {
    private let url = URL.temporaryDirectory.appending(path: "orb-frames-\(UUID().uuidString).log")

    @Test func readsWhatTheOrbWrites() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try OrbFrameLog(url: url)
        writer.record(gpuTime: 0.001)
        writer.record(gpuTime: 0.0025)

        let log = try FrameLog(contentsOf: url)

        #expect(log.gpuTimes == [0.001, 0.0025])
    }

    @Test func aNewLogEmptiesTheFile() throws {
        defer { try? FileManager.default.removeItem(at: url) }
        try OrbFrameLog(url: url).record(gpuTime: 0.001)

        _ = try OrbFrameLog(url: url)

        #expect(try FrameLog(contentsOf: url).frameCount == 0)
    }

    @Test func aMissingFileHasNoFrames() throws {
        #expect(try FrameLog(contentsOf: url).frameCount == 0)
    }

    @Test func leavesOutALineStillBeingWritten() {
        #expect(FrameLog(text: "0.001\n0.002\n0.00").gpuTimes == [0.001, 0.002])
        #expect(FrameLog(text: "0.001").frameCount == 0)
    }

    @Test func percentile95IsByNearestRank() {
        let times = (1...600).map(Double.init).shuffled()
        #expect(times.percentile95() == 570)
        #expect([4.0].percentile95() == 4)
        #expect([Double]().percentile95() == nil)
    }
}
