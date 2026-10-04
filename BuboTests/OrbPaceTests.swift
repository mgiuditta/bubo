import Testing
@testable import Bubo

/// The Orb's frame rate per Stato (#519), against the budgets of spec 25.
struct OrbPaceTests {
    nonisolated private static let acting = OrbState.allCases.filter { $0 != .idle }

    private static func pace(_ state: OrbState, isMorphing: Bool = false, isSettled: Bool = false,
                             isLowPowerModeEnabled: Bool = false, reducesMotion: Bool = false) -> OrbPace {
        OrbPace(state: state, isMorphing: isMorphing, isSettled: isSettled,
                isLowPowerModeEnabled: isLowPowerModeEnabled, reducesMotion: reducesMotion)
    }

    @Test func ratesAreTheBudgets() {
        #expect(OrbPace.full.framesPerSecond == PerfBudgets.orbFrameRate)
        #expect(OrbPace.half.framesPerSecond == PerfBudgets.orbRestFrameRate)
        #expect(OrbPace.still.framesPerSecond == 0)
    }

    @Test(arguments: OrbState.allCases)
    func everyStatoIsAtSixty(state: OrbState) {
        #expect(Self.pace(state) == .full)
        #expect(Self.pace(state, reducesMotion: true) == .full)
    }

    @Test(arguments: OrbState.allCases)
    func aMorphIsAtSixty(state: OrbState) {
        #expect(Self.pace(state, isMorphing: true) == .full)
        #expect(Self.pace(state, isMorphing: true, reducesMotion: true) == .full)
    }

    @Test(arguments: OrbState.allCases, [false, true])
    func lowPowerModeIsAlwaysAtThirty(state: OrbState, isMorphing: Bool) {
        #expect(Self.pace(state, isMorphing: isMorphing, isLowPowerModeEnabled: true) == .half)
    }

    @Test(arguments: [false, true])
    func reduceMotionStopsASettledOrbInRiposo(isLowPowerModeEnabled: Bool) {
        #expect(Self.pace(.idle, isSettled: true, isLowPowerModeEnabled: isLowPowerModeEnabled,
                          reducesMotion: true) == .still)
    }

    @Test func reduceMotionKeepsDrawingUntilTheOrbSettles() {
        #expect(Self.pace(.idle, reducesMotion: true) == .full)
    }

    @Test(arguments: acting)
    func reduceMotionNeverStopsAnOrbAtWork(state: OrbState) {
        #expect(Self.pace(state, isSettled: true, reducesMotion: true) == .full)
    }

    // MARK: - What "settled" reads

    @Test func anAnimationSettlesOnItsStatoAndTinta() {
        var animation = OrbAnimation()
        #expect(animation.isSettled)

        animation.state = .working
        animation.advance(by: 1.0 / 30)
        #expect(!animation.isSettled)
        for _ in 0..<300 { animation.advance(by: 1.0 / 30) }
        #expect(animation.isSettled)

        animation.targetTinta = Tinta(for: .openAI)
        #expect(!animation.isSettled)
        for _ in 0..<60 { animation.advance(by: 1.0 / 30) }
        #expect(animation.isSettled)
    }

    @Test func theRegiaIsAtRestOnlyAfterTheReturnToTheBlob() {
        let lente = Variante(nome: "lente", forma: "lente", categoria: .ricerca, descrizione: "", parole: [])
        var director = MorphDirector()
        director.advance(to: 0)
        #expect(director.isAtRest)

        director.request(lente, at: 0)
        #expect(!director.isAtRest)
        director.advance(to: 0.5)
        #expect(director.isMorphing)
        director.advance(to: 3)
        #expect(!director.isMorphing)
        #expect(director.isAtRest)

        director.enter(.working, at: 3)
        director.enter(.idle, at: 4)
        // The return to the Blob is scheduled 5 s into Riposo.
        #expect(!director.isAtRest)
        director.advance(to: 9)
        #expect(director.isMorphing)
        director.advance(to: 11)
        #expect(director.isAtRest)
        #expect(director.destination == nil)
    }
}
