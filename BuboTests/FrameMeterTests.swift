import Testing
@testable import Bubo

struct FrameMeterTests {
    @Test func noReadingBeforeTheWindowEnds() {
        var meter = FrameMeter()
        let first = meter.recordFrame(at: 10)
        let second = meter.recordFrame(at: 10.1)
        #expect(first == nil)
        #expect(second == nil)
    }

    @Test func countsFramesPerSecondOverTheWindow() throws {
        var meter = FrameMeter()
        var reading: FrameMeter.Reading?
        for frame in 0...30 {
            reading = meter.recordFrame(at: 10 + Double(frame) / 60) ?? reading
        }
        let framesPerSecond = try #require(reading).framesPerSecond
        #expect(abs(framesPerSecond - 60) < 0.5)
    }

    @Test func averagesTheGPUTimeOfTheWindow() throws {
        var meter = FrameMeter()
        _ = meter.recordFrame(at: 0)
        meter.recordGPUTime(0.001)
        meter.recordGPUTime(0.002)
        let reading = meter.recordFrame(at: 1)
        let gpuTime = try #require(reading?.gpuTime)
        #expect(abs(gpuTime - 0.0015) < 1e-9)
    }

    @Test func gpuTimeIsUnknownWithoutSamples() throws {
        var meter = FrameMeter()
        _ = meter.recordFrame(at: 0)
        let reading = meter.recordFrame(at: 1)
        #expect(try #require(reading).gpuTime == nil)
    }

    @Test func eachWindowStartsAfresh() throws {
        var meter = FrameMeter()
        _ = meter.recordFrame(at: 0)
        meter.recordGPUTime(0.004)
        _ = meter.recordFrame(at: 1)
        _ = meter.recordFrame(at: 1.5)
        let last = meter.recordFrame(at: 2)
        let reading = try #require(last)
        #expect(reading.framesPerSecond == 2)
        #expect(reading.gpuTime == nil)
    }
}
