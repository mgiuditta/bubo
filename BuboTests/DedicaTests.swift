import Foundation
import Testing
@testable import Bubo

@MainActor
struct DedicaTests {
    @Test(arguments: ["Elena Manca", "elena manca", "MANCA Elena", "Elena Maria Manca", "Eléna Manca"])
    func isMeantForBothWordsOfHerName(fullName: String) {
        #expect(Dedica.isMeant(forFullName: fullName))
    }

    @Test(arguments: ["Elena Rossi", "Mario Manca", "Elenamanca", "", "Matteo Giuditta"])
    func isNotMeantForAnyoneElse(fullName: String) {
        #expect(!Dedica.isMeant(forFullName: fullName))
    }

    @Test func herGreetingIsTheHeartWithItsLine() throws {
        let orb = OrbControls()

        orb.greet(fullName: "Elena Manca", reducesMotion: true)

        #expect(orb.variante == Catalogo.bundled?.variante(named: "cuore"))
        #expect(orb.isShowingDedica)
    }

    @Test func everyoneElseIsGreetedByTheOwl() {
        let orb = OrbControls()

        orb.greet(fullName: "Mario Rossi", reducesMotion: true)

        #expect(orb.variante == Gufo.variante)
        #expect(!orb.isShowingDedica)
    }
}
