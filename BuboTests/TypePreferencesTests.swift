import Foundation
import Testing
@testable import Bubo

struct TypePreferencesTests {
    let defaults = UserDefaults(suiteName: "TypePreferencesTests-\(UUID().uuidString)")!

    @Test func preferencesSurviveARelaunchAndCanBeRemoved() {
        let preferences = TypePreferences(defaults: defaults)
        preferences.set(.claude(Scala.Step(family: .opus, effort: .high)), for: .writing)
        preferences.set(.endpoint(id: "ollama"), for: .summary)
        preferences.remove(for: .summary)

        let relaunched = TypePreferences(defaults: defaults)

        #expect(relaunched.choices == [.writing: .claude(Scala.Step(family: .opus, effort: .high))])
    }
}
