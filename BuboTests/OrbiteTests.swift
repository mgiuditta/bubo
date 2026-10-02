import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct OrbiteTests {
    /// A bridge played by `/bin/sh` that answers every Domanda at once.
    static let bridge = #"""
        while read line; do
          id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"risposta\"}"
          echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
        done
        """#

    static func model(orb: OrbControls) -> QuestionModel {
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        return QuestionModel(cli: cli, orb: orb, bridgeExecutable: URL(filePath: "/bin/sh"),
                             bridgeArguments: ["-c", bridge], apiKey: { nil }, onDevice: .off)
    }

    @Test(arguments: ["twelfth", "Twelfth", "  TWELFTH \n"])
    func theWordAlonePlaysTheOrbite(prompt: String) {
        #expect(Orbite.isPlayed(by: prompt))
    }

    @Test(arguments: ["twelfth night", "what is twelfth", "twelve", "twelfths", ""])
    func anyOtherPromptDoesNotPlayIt(prompt: String) {
        #expect(!Orbite.isPlayed(by: prompt))
    }

    @Test func theWordPlaysTheOrbiteAndAsksNothing() {
        let orb = OrbControls()
        let model = Self.model(orb: orb)
        model.prompt = " Twelfth "

        model.ask()

        #expect(orb.variante == Orbite.variante)
        #expect(model.answering == nil)
        #expect(!model.isAnswering)
        #expect(model.prompt.isEmpty)
    }

    @Test func theWordInsideASentenceGoesToTheModel() async {
        let orb = OrbControls()
        let model = Self.model(orb: orb)
        model.prompt = "what is twelfth"

        model.ask()
        #expect(model.isAnswering)
        await model.answering?.value

        #expect(orb.variante == nil)
        #expect(model.answer == "risposta")
    }

    @Test func theOrbiteHasNoVarianteInTheCatalogo() throws {
        let catalogo = try Catalogo(bundle: .main)
        #expect(!catalogo.formaNames.contains(Orbite.variante.forma))
        #expect(Forma(rawValue: Orbite.variante.forma) == .orbite)
    }

    @Test func theOrbiteLastsAboutSixSeconds() {
        let back = Orbite.returnDelay(reducesMotion: false) + MorphDirector.morphDuration
        #expect(back == Orbite.duration)
    }

    // Reduce Motion: no Morph and no motion, the diagram fades in still and stays 3 s.
    @Test func withReduceMotionTheDiagramFadesInStill() {
        var director = MorphDirector()
        director.reducesMotion = true
        director.request(Orbite.variante, at: 0)
        director.advance(to: MorphDirector.fadeDuration * 0.75)

        #expect(director.frame.forma == .orbite)
        #expect(director.frame.morph == 1)
        #expect(director.frame.opacity < 1)
        #expect(Orbite.returnDelay(reducesMotion: true) == Orbite.stillDuration)
        #expect(Orbite.diagramTime(since: 0, at: 2.5, reducesMotion: true) == 0)
        #expect(Orbite.diagramTime(since: 0, at: 2.5, reducesMotion: false) == 2.5)
    }
}
