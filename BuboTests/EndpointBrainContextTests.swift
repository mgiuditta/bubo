import Foundation
import Testing
@testable import Bubo

/// What an OpenAI-compatible endpoint receives of the Secondo cervello with a Domanda (#678).
@Suite(.timeLimit(.minutes(1)))
struct EndpointBrainContextTests {
    let folder: NotesFolder
    let defaults: UserDefaults
    let settings: EndpointSettings
    let cloud = OpenAICompatibleEndpoint.custom(named: "Cloud", at: URL(string: "https://cloud.test/v1")!)
    let onMac = OpenAICompatibleEndpoint.custom(named: "Ollama", at: URL(string: "http://localhost:11434/v1")!)

    init() throws {
        folder = try NotesFolder()
        defaults = try #require(UserDefaults(suiteName: "EndpointBrainContextTests-\(UUID().uuidString)"))
        settings = EndpointSettings(defaults: defaults)
        try folder.write("Matteo, sviluppatore a Torino.", to: "Bubo/Profilo.md")
        try folder.write("Rispondi in breve.", to: "Bubo/Regole.md")
        try folder.write("# Viaggio\n\nPrenotare il traghetto per la Sardegna.", to: "Viaggi/Sardegna.md")
    }

    /// A Domanda model with the test's endpoints, and the test's Secondo cervello when `hasSecondBrain`.
    func model(hasSecondBrain: Bool = true) -> QuestionModel {
        let secondBrain = SecondBrain(index: nil, defaults: defaults,
                                      journal: BrainJournal(file: folder.claude.folder.appending(path: "journal.json")))
        if hasSecondBrain { secondBrain.choose(folder.notes) }
        return QuestionModel(secondBrain: secondBrain, endpoints: settings)
    }

    @Test func withoutASecondBrainOnlyTheTextGoes() async {
        let asked = await model(hasSecondBrain: false).withSecondBrain("Domanda", about: "traghetto", for: onMac)

        #expect(asked == "Domanda")
    }

    @Test func aCloudWithoutTheNotesConsentGetsOnlyTheText() async {
        settings.grantConsent(to: cloud)

        let asked = await model().withSecondBrain("Domanda", about: "traghetto", for: cloud)

        #expect(asked == "Domanda")
    }

    @Test func aCloudWithTheNotesConsentGetsProfiloRegoleAndTheNotesFound() async {
        settings.grantConsent(to: cloud)
        settings.grantNotesConsent(to: cloud)

        let asked = await model().withSecondBrain("Domanda", about: "traghetto", for: cloud)

        #expect(asked.contains("Matteo, sviluppatore a Torino."))
        #expect(asked.contains("Rispondi in breve."))
        #expect(asked.contains("Prenotare il traghetto"))
        #expect(asked.contains("[[Viaggi/Sardegna]]"))
        #expect(asked.hasSuffix("Domanda"))
    }

    @Test func theModelloLocaleGetsTheNotesWithoutAnyConsent() async {
        let asked = await model().withSecondBrain("Domanda", about: "traghetto", for: onMac)

        #expect(asked.contains("Matteo, sviluppatore a Torino."))
        #expect(asked.contains("Prenotare il traghetto"))
    }

    @Test func revokingTheCloudsConsentTakesBackTheNotesToo() {
        settings.grantConsent(to: cloud)
        settings.grantNotesConsent(to: cloud)

        settings.revokeConsent(of: cloud)

        #expect(!EndpointBrainContext.allowsNotes(to: cloud, consents: settings.consents))
    }

    @Test func theNotesFoundAreCutToTheirLimit() {
        let found = String(repeating: "a", count: EndpointBrainContext.notesLimit * 2)

        let asked = EndpointBrainContext.prompt("Domanda", in: folder.notes, found: found)

        #expect(asked.count < EndpointBrainContext.notesLimit + EndpointBrainContext.basicsLimit)
        #expect(asked.contains("[…] Il resto non entra qui."))
    }
}
