import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct SecondBrainBasicsTests {
    let folder: NotesFolder

    init() throws {
        folder = try NotesFolder()
    }

    @Test func withoutTheProfiloAndTheRegoleNothingComesIn() {
        #expect(SecondBrainBasics.prompt(in: folder.notes, savesOnItsOwn: true) == nil)
    }

    @Test func theProfiloAndTheRegoleComeInWithWhatToSave() throws {
        try folder.write("Si chiama Matteo.", to: "Bubo/Profilo.md")
        try folder.write("Le ricette vanno in Cucina/.", to: "Bubo/Regole.md")

        let prompt = try #require(SecondBrainBasics.prompt(in: folder.notes, savesOnItsOwn: true))

        #expect(prompt.contains("## Bubo/Profilo.md\n\nSi chiama Matteo."))
        #expect(prompt.contains("## Bubo/Regole.md\n\nLe ricette vanno in Cucina/."))
        #expect(prompt.contains("Salva da solo"))
        #expect(!prompt.contains("usa cerca per il resto"))
        // The notes come as the user's data, after Bubo's own instructions, which they never change.
        let data = try #require(prompt.range(of: "<note-utente>"))
        #expect(prompt[data.upperBound...].contains("Si chiama Matteo."))
        #expect(!prompt[..<data.lowerBound].contains("Si chiama Matteo."))
        #expect(prompt.hasSuffix("</note-utente>"))
    }

    @Test func withSalvaDaSoloOffItSavesOnlyWhenAsked() throws {
        try folder.write("Si chiama Matteo.", to: "Bubo/Profilo.md")

        let prompt = try #require(SecondBrainBasics.prompt(in: folder.notes, savesOnItsOwn: false))

        #expect(prompt.contains("solo quando l'utente te lo chiede"))
        #expect(!prompt.contains("Salva da solo"))
    }

    @Test func aProfiloThatIsALinkDoesNotComeIn() throws {
        try "segreto fuori".write(to: folder.claude.folder.appending(path: "fuori.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: folder.notes.appending(path: "Bubo"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder.notes.appending(path: "Bubo/Profilo.md"),
                                                   withDestinationURL: folder.claude.folder.appending(path: "fuori.md"))

        #expect(SecondBrainBasics.prompt(in: folder.notes, savesOnItsOwn: true) == nil)
    }

    @Test func pastTheLimitOnlyTheBeginningComesInWithCercaForTheRest() throws {
        try folder.write(String(repeating: "parola ", count: 3_000), to: "Bubo/Profilo.md")

        let prompt = try #require(SecondBrainBasics.prompt(in: folder.notes, savesOnItsOwn: true))

        #expect(prompt.contains("usa cerca per il resto.\n</note-utente>"))
        #expect(prompt.count < SecondBrainBasics.characterLimit + 1_000)
    }

    @Test func theProfiloAndTheRegoleReachEveryTurnOfTheBridge() async throws {
        try folder.write("Si chiama Matteo.", to: "Bubo/Profilo.md")
        let defaults = try #require(UserDefaults(suiteName: "SecondBrainBasicsTests-\(UUID().uuidString)"))
        let secondBrain = SecondBrain(index: nil, defaults: defaults,
                                      journal: BrainJournal(file: folder.claude.folder.appending(path: "journal.json")))
        secondBrain.choose(folder.notes)
        // The bridge answers with the command's `brain`, or exits without it.
        let bridge = AgentBridge(executable: URL(filePath: "/bin/sh"), arguments: ["-c", #"""
            read line
            case "$line" in *'Si chiama Matteo.'*) ;; *) exit 3 ;; esac
            id=$(echo "$line" | sed 's/.*"id":"\([^"]*\)".*/\1/')
            echo "{\"v\":4,\"type\":\"text\",\"id\":\"$id\",\"text\":\"ok\"}"
            echo "{\"v\":4,\"type\":\"done\",\"id\":\"$id\"}"
            read _
            """#], environment: ["PATH": "/usr/bin:/bin"], basics: secondBrain.basics) { _, _, _ in "" }

        let answer = try await bridge.ask("x", in: URL(filePath: "/tmp")).reduce("", +)

        #expect(answer == "ok")
    }
}
