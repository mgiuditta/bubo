import Foundation
import Synchronization
import Testing
@testable import Bubo

/// An energy that tests set by hand; on the power adapter until told otherwise.
nonisolated final class FakeEnergyGauge: EnergyGauge {
    init(_ state: EnergyState = EnergyState()) {
        self.state = Mutex(state)
    }

    private let state: Mutex<EnergyState>

    var current: EnergyState {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    func change(within limit: Duration) async {
        await Task.yield()
    }
}

@Suite(.timeLimit(.minutes(1)))
struct IndexEnergyTests {
    let claude: ClaudeFolder

    init() throws {
        claude = try ClaudeFolder()
    }

    /// An Indice with a few memory files, its vectors waiting on `energy`.
    func pausedIndex(_ energy: FakeEnergyGauge) async throws -> SearchIndex {
        try claude.write("Il micio dorme sul divano.", to: "projects/-p/memory/gatto.md")
        try claude.write("La macchina va al tagliando.", to: "projects/-p/memory/auto.md")
        let index = try claude.open(energy: energy)
        await index.use(TopicEmbedder())
        await index.rescan()
        return index
    }

    @Test func vectorsPauseBelowTwentyPercentAndResumeOnTheirOwn() async throws {
        let energy = FakeEnergyGauge(EnergyState(batteryLevel: 0.15))
        let index = try await pausedIndex(energy)
        var pauses = index.pauses.makeAsyncIterator()

        #expect(await pauses.next() == .lowBattery)
        #expect(await index.vectorCount == 0)

        energy.current.batteryLevel = 0.5
        await index.vectorsComputed()

        #expect(await index.vectorCount == 2)
        #expect(await pauses.next() == .some(nil))
    }

    @Test func lowPowerModeResumesWithoutAnotherFileChange() async throws {
        let energy = FakeEnergyGauge(EnergyState(isLowPowerModeEnabled: true))
        let index = try await pausedIndex(energy)
        var pauses = index.pauses.makeAsyncIterator()

        #expect(await pauses.next() == .lowPowerMode)

        energy.current.isLowPowerModeEnabled = false
        await index.vectorsComputed()

        #expect(await index.vectorCount == 2)
    }

    @Test(arguments: [(0.19, true), (0.2, false), (0.8, false)])
    func theBatteryLevelDecidesThePause(level: Double, paused: Bool) {
        #expect((EnergyState(batteryLevel: level).pause == .lowBattery) == paused)
    }

    @Test func aMacOnItsPowerAdapterNeverPausesForTheBattery() {
        #expect(EnergyState(batteryLevel: nil).pause == nil)
    }

    @Test func wordsStayFindableDuringThePause() async throws {
        let energy = FakeEnergyGauge(EnergyState(batteryLevel: 0.1))
        let index = try await pausedIndex(energy)
        var pauses = index.pauses.makeAsyncIterator()
        #expect(await pauses.next() == .lowBattery)

        #expect(try await index.hits(for: "tagliando").map(\.text) == ["La macchina va al tagliando."])
        energy.current.batteryLevel = nil
        await index.vectorsComputed()
    }
}
