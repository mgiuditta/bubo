import Foundation
import Testing
@testable import Bubo

/// A Domanda asked by voice: the Sintesi parlata is said with the Orb in Parla and shown as subtitles (spec 08).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SpokenAnswerTests {
    /// A voice with no audio: it records what it says and the Orb's Stato meanwhile.
    final class FakeSpeaker: VoiceSpeaker {
        var hasOnlyDefaultVoices = true
        private(set) var said: [String] = []
        private(set) var statesWhileSpeaking: [OrbState?] = []
        private(set) var stops = 0
        /// Whether `speak` goes on until `stop`, like a long Sintesi parlata.
        var speaksUntilStopped = false
        private var stopped: CheckedContinuation<Void, Never>?
        let orb: OrbControls

        init(orb: OrbControls) {
            self.orb = orb
        }

        func speak(_ text: String, level: @escaping (Float) -> Void) async {
            said.append(text)
            statesWhileSpeaking.append(orb.questionState)
            level(0.5)
            if speaksUntilStopped {
                await withCheckedContinuation { stopped = $0 }
            }
        }

        func stop() {
            stops += 1
            stopped?.resume()
            stopped = nil
        }
    }

    /// A bridge played by `/bin/sh`: with the instruction of the voice it writes the Sintesi parlata first; without, the
    /// answer alone.
    static let bridge = #"""
        while read line; do
          id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
          case "$line" in
            *'Domanda fatta a voce'*)
              echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"Sintesi parlata: A Lima sono\"}"
              printf '%s\n' "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\" le sette.\\nEcco i dettagli.\"}";;
            *) echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"Ecco i dettagli.\"}";;
          esac
          echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
        done
        """#

    let orb = OrbControls()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let speaker: FakeSpeaker
    let model: QuestionModel

    init() {
        speaker = FakeSpeaker(orb: orb)
        let cli = ClaudeCLI(isOnline: { true }, locator: ClaudeLocator(isExecutable: { _ in true }))
        model = QuestionModel(cli: cli, orb: orb, intake: IntakePipeline(orb: orb, makeClassifier: { nil }),
                              bridgeExecutable: URL(filePath: "/bin/sh"), bridgeArguments: ["-c", Self.bridge],
                              defaults: defaults, apiKey: { nil }, speaker: speaker)
    }

    func ask(_ prompt: String, byVoice: Bool) async {
        model.prompt = prompt
        if byVoice { model.askByVoice() } else { model.ask() }
        await model.answering?.value
        await model.speaking?.value
    }

    @Test func aDomandaByVoiceSaysTheSintesiParlataInParla() async {
        await ask("Che ore sono a Lima?", byVoice: true)

        #expect(model.failure == nil)
        #expect(speaker.said == ["A Lima sono le sette."])
        #expect(speaker.statesWhileSpeaking == [.speaking])
        #expect(model.answer == "Ecco i dettagli.")
        #expect(model.subtitle == nil)
        #expect(orb.questionState == nil)
        #expect(orb.voiceLevel == nil)
    }

    @Test func stoppingTheVoiceLeavesParlaAndKeepsTheVariante() async {
        let lente = Variante(nome: "lente", forma: "lente", categoria: .ricerca, descrizione: "", parole: [])
        orb.variante = lente
        speaker.speaksUntilStopped = true
        model.prompt = "Che ore sono a Lima?"
        model.askByVoice()
        await model.answering?.value
        while speaker.statesWhileSpeaking.isEmpty { await Task.yield() }
        #expect(orb.questionState == .speaking)
        #expect(model.subtitle != nil)

        let speaking = model.speaking
        model.stopSpeaking()
        await speaking?.value

        #expect(speaker.stops == 1)
        #expect(orb.questionState == nil)
        #expect(orb.voiceLevel == nil)
        #expect(model.subtitle == nil)
        #expect(model.answer == "Ecco i dettagli.")
        #expect(orb.variante == lente)
    }

    @Test func stoppingWithNothingSaidDoesNothing() {
        model.stopSpeaking()
        #expect(speaker.stops == 0)
    }

    @Test func aWrittenDomandaIsNotSaid() async {
        await ask("Che ore sono a Lima?", byVoice: false)

        #expect(model.answer == "Ecco i dettagli.")
        #expect(speaker.said.isEmpty)
        #expect(!model.invitesBetterVoice)
    }

    @Test func aBasicVoiceInvitesABetterOneUntilClosed() async {
        await ask("Che ore sono a Lima?", byVoice: true)
        #expect(model.invitesBetterVoice)

        model.dismissBetterVoice()
        await ask("E a Tokyo?", byVoice: true)
        #expect(!model.invitesBetterVoice)
    }

    @Test func aBetterVoiceIsNotInvited() async {
        speaker.hasOnlyDefaultVoices = false
        await ask("Che ore sono a Lima?", byVoice: true)
        #expect(!model.invitesBetterVoice)
    }
}
