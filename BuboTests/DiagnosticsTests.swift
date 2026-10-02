import Foundation
import Testing
@testable import Bubo

struct DiagnosticsTests {
    let store = DiagnosticsStore(folder: URL.temporaryDirectory.appending(path: "Diagnostica-\(UUID().uuidString)"))

    /// MXMetricPayload has no public initializer: the fake payload is its JSON and the summary read from it.
    static let payload = Data(#"{"timeStampBegin":"2026-09-30 00:00:00","timeStampEnd":"2026-09-30 23:59:00"}"#.utf8)

    static func day(ending end: Date) -> DailyMetrics {
        DailyMetrics(start: end.addingTimeInterval(-86_400), end: end, meanLaunch: .milliseconds(420), launchCount: 3,
                     hangCount: 1, hangTime: .milliseconds(300), peakMemory: 80_000_000, hitchRatio: 0.004)
    }

    @Test func aFakePayloadIsSavedAndShown() throws {
        let day = Self.day(ending: .now)
        try store.saveMetrics(Self.payload, summary: day)
        let files = try FileManager.default.contentsOfDirectory(at: store.folder, includingPropertiesForKeys: nil)
        let saved = try #require(files.first { $0.lastPathComponent.hasPrefix("metriche-") })
        #expect(try Data(contentsOf: saved) == Self.payload)
        #expect(store.latestDay() == day)
        #expect(store.hasReports)
    }

    @Test func anOlderDayDoesNotReplaceTheLatest() throws {
        let latest = Self.day(ending: .now)
        try store.saveMetrics(Self.payload, summary: latest)
        try store.saveMetrics(Self.payload, summary: Self.day(ending: latest.end.addingTimeInterval(-86_400)))
        #expect(store.latestDay() == latest)
    }

    @Test func aDiagnosticPayloadIsSavedWithoutADay() throws {
        try store.saveDiagnostics(Self.payload, endingAt: .now)
        #expect(store.hasReports)
        #expect(store.latestDay() == nil)
    }

    @Test func anEmptyFolderHasNoReports() {
        #expect(!store.hasReports)
        #expect(store.latestDay() == nil)
    }

    @Test func reportsOlderThanThirtyDaysAreDeleted() throws {
        let now = Date.now
        try store.saveDiagnostics(Self.payload, endingAt: now.addingTimeInterval(-40 * 86_400))
        try store.saveDiagnostics(Self.payload, endingAt: now)
        let files = try FileManager.default.contentsOfDirectory(at: store.folder, includingPropertiesForKeys: nil)
        let old = try #require(files.sorted { $0.lastPathComponent < $1.lastPathComponent }.first)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-31 * 86_400)],
                                              ofItemAtPath: old.path(percentEncoded: false))
        store.removeExpiredReports(now: now)
        let left = try FileManager.default.contentsOfDirectory(at: store.folder, includingPropertiesForKeys: nil)
        #expect(left.map(\.lastPathComponent) == files.map(\.lastPathComponent).filter { $0 != old.lastPathComponent })
    }

    @Test func aHistogramCountsEachSampleAtTheMiddleOfItsBucket() {
        let buckets = [DurationBucket(start: .milliseconds(100), end: .milliseconds(200), count: 2),
                       DurationBucket(start: .milliseconds(400), end: .milliseconds(600), count: 1)]
        #expect(buckets.sampleCount == 3)
        #expect(buckets.total == .milliseconds(800))
        #expect(buckets.mean == .milliseconds(800) / 3)
        #expect([DurationBucket]().mean == nil)
    }
}
