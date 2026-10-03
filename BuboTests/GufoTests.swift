import Foundation
import Testing
@testable import Bubo

@MainActor
struct GufoTests {
    @Test func theOrbGreetsAsTheOwlOnlyOnce() {
        let orb = OrbControls()

        orb.greet(reducesMotion: true)
        #expect(orb.variante == Gufo.variante)

        orb.variante = nil
        orb.greet(reducesMotion: true)
        #expect(orb.variante == nil)
    }

    @Test func theGreetingLeavesAVarianteAtWorkAlone() throws {
        let orb = OrbControls()
        let lente = try #require(Catalogo.bundled?.variante(named: "lente"))
        orb.variante = lente

        orb.greet(reducesMotion: true)

        #expect(orb.variante == lente)
    }

    @Test func theOrbIsTheOwlOnlyWhileThePointerIsOnIt() {
        let orb = OrbControls()

        orb.hover(isPointerInside: true)
        #expect(orb.variante == Gufo.variante)

        orb.hover(isPointerInside: false)
        #expect(orb.variante == nil)
    }

    @Test func theHoverLeavesAVarianteAtWorkAlone() throws {
        let orb = OrbControls()
        let lente = try #require(Catalogo.bundled?.variante(named: "lente"))
        orb.variante = lente

        orb.hover(isPointerInside: true)
        orb.hover(isPointerInside: false)

        #expect(orb.variante == lente)
    }

    @Test func theOwlHasNoVarianteInTheCatalogo() throws {
        let catalogo = try Catalogo(bundle: .main)
        #expect(!catalogo.formaNames.contains(Gufo.variante.forma))
        #expect(Forma(rawValue: Gufo.variante.forma) == .gufo)
    }
}
