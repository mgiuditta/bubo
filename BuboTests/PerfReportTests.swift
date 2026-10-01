import Foundation
import Testing

struct BudgetReportTests {
    private func row(_ id: BudgetID, in report: BudgetReport) throws -> BudgetReport.Row {
        try #require(report.rows.first { $0.budget.id == id })
    }

    @Test func aReadingWithinTheBudgetKeepsIt() throws {
        let report = BudgetReport(measurements: [PerfMeasurement(.warmLaunch, value: 420, from: "test")])

        #expect(try row(.warmLaunch, in: report).outcome == .kept)
        #expect(report.isWithinBudgets)
    }

    @Test func theWorstReadingCounts() throws {
        let report = BudgetReport(measurements: [
            PerfMeasurement(.orbGPUTime, value: 3, from: "test"),
            PerfMeasurement(.orbGPUTime, value: 4.5, from: "Metal HUD"),
        ])

        let orb = try row(.orbGPUTime, in: report)
        #expect(orb.value == 4.5)
        #expect(orb.outcome == .exceeded)
        #expect(orb.notes == ["Metal HUD", "test"])
        #expect(!report.isWithinBudgets)
    }

    @Test func onlyTwiceTheBudgetBlocksAPullRequest() throws {
        let report = BudgetReport(measurements: [
            PerfMeasurement(.warmLaunch, value: 900, from: "test"),
            PerfMeasurement(.idleMemory, value: 250, from: "test"),
        ])

        #expect(try !row(.warmLaunch, in: report).blocksPullRequest)
        #expect(try row(.idleMemory, in: report).blocksPullRequest)
    }

    @Test func aLaunchOf1200MillisecondsBlocksThePullRequest() {
        let report = BudgetReport(measurements: [PerfMeasurement(.warmLaunch, value: 1200, from: "test")])

        #expect(report.blocksPullRequest)
        #expect(report.workflowAnnotations.contains("::error title=Prestazioni::Avvio caldo, p95: 1200 ms, budget ≤ 500 ms, blocca la PR"))
    }

    @Test func aLaunchOf600MillisecondsPassesWithAWarning() {
        let report = BudgetReport(measurements: [PerfMeasurement(.warmLaunch, value: 600, from: "test")])

        #expect(!report.blocksPullRequest)
        #expect(report.workflowAnnotations.contains("::warning title=Prestazioni::Avvio caldo, p95: 600 ms, budget ≤ 500 ms, entro 2× il budget"))
        #expect(!report.workflowAnnotations.contains { $0.hasPrefix("::error") })
    }

    @Test func aSkippedFrameTestLeavesAWarning() {
        let report = BudgetReport(measurements: [
            PerfMeasurement(skipping: .framesWhileCovered, because: "Nessun Metal"),
        ])

        #expect(!report.blocksPullRequest)
        #expect(report.workflowAnnotations.contains("::warning title=Prestazioni::Orb coperto, fotogrammi non misurato: Nessun Metal"))
    }

    @Test func budgetsOfTheReferenceMacAreNotAnnotated() {
        let report = BudgetReport(measurements: [PerfMeasurement(.coldLaunch, value: 5000, from: "test")])

        #expect(!report.workflowAnnotations.contains { $0.contains("Avvio freddo") })
    }

    @Test func anInvariantBreaksAtTheFirstFrame() throws {
        let report = BudgetReport(measurements: [PerfMeasurement(.framesWhileCovered, value: 1, from: "test")])

        let covered = try row(.framesWhileCovered, in: report)
        #expect(covered.outcome == .broken)
        #expect(covered.blocksPullRequest)
    }

    @Test func budgetsNotMeasuredDoNotFail() throws {
        let report = BudgetReport(measurements: [PerfMeasurement(skipping: .galaxyFramesWhileStill, because: "Niente Galassia")])

        #expect(try row(.galaxyFramesWhileStill, in: report).notes == ["Niente Galassia"])
        #expect(try row(.coldLaunch, in: report).outcome == .notMeasured)
        #expect(report.rows.count == PerfBudgets.reported.count)
        #expect(report.isWithinBudgets)
    }

    @Test func theJSONReportReadsBack() throws {
        let report = BudgetReport(measurements: [PerfMeasurement(.warmLaunch, value: 420, from: "test")],
                                  date: Date(timeIntervalSince1970: 0))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BudgetReport.self, from: report.json())

        #expect(decoded.rows == report.rows)
    }

    @Test func everyBudgetIsReportedOnce() {
        let ids = PerfBudgets.reported.map(\.id)

        #expect(Set(ids) == Set(BudgetID.allCases))
        #expect(ids.count == BudgetID.allCases.count)
    }
}

struct MetalHUDLogTests {
    /// A line from Bubo's Orb, cut short: frame number, two header fields, then interval and GPU time pairs.
    private let line = "metal-HUD: 93,26.64,243.67,16.67,1.65,16.67,1.65,16.66,4.00,16.67,0.00"

    @Test func readsThePairsAfterTheHeader() {
        let log = MetalHUDLog(lines: [line])

        #expect(log.frames.map(\.gpuTime) == [1.65, 1.65, 4.00])
        #expect(log.frames.first?.presentationInterval == 16.67)
    }

    @Test func skipsOtherLines() {
        #expect(MetalHUDLog(lines: ["Bubo started", ""]).frames.isEmpty)
        #expect(MetalHUDLog(lines: ["Bubo started"]).gpuTimePercentile95 == nil)
    }

    @Test func measuresGPUTimeAndFrameRate() throws {
        let log = MetalHUDLog(lines: [line])

        #expect(log.gpuTimePercentile95 == 4.00)
        #expect(try #require(log.framesPerSecond).rounded() == 60)
    }
}
