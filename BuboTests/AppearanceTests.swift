import Foundation
import Testing
@testable import Bubo

struct AppearanceTests {
    /// A private `UserDefaults` per test, so tests running in parallel never share a choice.
    private let defaults = UserDefaults(suiteName: "AppearanceTests-\(UUID())")!

    @Test func reduceMotionIsOffUntilChosen() {
        #expect(!Motion.isReduced(in: defaults, system: false))
    }

    @Test func reduceMotionFollowsTheSystemEvenIfOffInAspetto() {
        defaults.set(false, forKey: Motion.reducesMotionKey)
        #expect(Motion.isReduced(in: defaults, system: true))
    }

    @Test func reduceMotionChosenInAspettoWorksWithoutTheSystem() {
        defaults.set(true, forKey: Motion.reducesMotionKey)
        #expect(Motion.isReduced(in: defaults, system: false))
    }

    @Test func vistaRawValuesStayStableForUserDefaults() {
        #expect(VistaDelleSessioni.allCases.map(\.rawValue) == ["colonna", "orbita", "striscia"])
    }
}
