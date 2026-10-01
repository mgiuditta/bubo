import Foundation
import Testing
@testable import Bubo

/// The Variante an agent at work gives the Orb: by its tag `⟦orb:nome⟧`, or by the tool it uses (ADR 0002).
@Suite(.timeLimit(.minutes(1)))
struct OrbAtWorkTests {
    @Test func aNameOfTheCatalogoTurnsTheOrb() throws {
        let orb = OrbControls()
        orb.showWork("lente")
        #expect(orb.variante?.nome == "lente")
    }

    @Test func aNameOutsideTheCatalogoChangesNothing() {
        let orb = OrbControls()
        orb.showWork("parentesi")
        orb.showWork("drago")
        #expect(orb.variante?.nome == "parentesi")
    }

    @Test func theOrbitePlaysToItsEnd() {
        let orb = OrbControls()
        orb.playOrbite(reducesMotion: true)
        orb.showWork("lente")
        #expect(orb.variante == Orbite.variante)
    }

    /// A bridge played by `/bin/sh`: the agent turns to the code, then names a Variante Bubo does not have.
    static let bridge = #"""
        while read line; do
          id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          case "$line" in *'"orb":["'*'"lente"'*) ;; *) echo "{\"v\":4,\"type\":\"error\",\"id\":\"$id\",\"message\":\"rosa\"}"; continue;; esac
          echo "{\"v\":4,\"type\":\"variante\",\"id\":\"$id\",\"nome\":\"parentesi\"}"
          echo "{\"v\":4,\"type\":\"variante\",\"id\":\"$id\",\"nome\":\"drago\"}"
          echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"fatto\"}"
          echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
        done
        """#

    @Test func aDomandaGivesTheRosaAndFollowsTheAgent() async {
        let orb = OrbControls()
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        let model = QuestionModel(cli: cli, orb: orb, bridgeExecutable: URL(filePath: "/bin/sh"),
                                  bridgeArguments: ["-c", Self.bridge]) { nil }
        model.prompt = "correggi il Panel"

        model.ask()
        await model.answering?.value

        #expect(model.failure == nil)
        #expect(model.answer == "fatto")
        #expect(orb.variante?.nome == "parentesi")
    }

    // Reduce Motion: a Variante chosen while the Orb is still on the last one waits its 1.5 s, then fades.
    @Test func withReduceMotionAVarianteHoldsThenFades() throws {
        let catalogo = try #require(Catalogo.bundled)
        let lente = try #require(catalogo.variante(named: "lente"))
        let parentesi = try #require(catalogo.variante(named: "parentesi"))
        var director = MorphDirector()
        director.reducesMotion = true
        director.request(lente, at: 0)
        director.advance(to: MorphDirector.fadeDuration)
        director.request(parentesi, at: MorphDirector.fadeDuration + 0.1)

        director.advance(to: MorphDirector.fadeDuration + MorphDirector.minimumHold - 0.01)
        #expect(director.frame == MorphFrame(from: lente, to: lente, progress: 1, opacity: 1))

        director.advance(to: MorphDirector.fadeDuration + MorphDirector.minimumHold + MorphDirector.fadeDuration / 4)
        #expect(director.frame.morph == 1)
        #expect(director.frame.opacity < 1)
    }
}
