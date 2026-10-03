import AVFoundation
import Foundation
import Testing
@testable import Bubo

@Suite(.timeLimit(.minutes(1)))
struct MeetingImportTests {
    let folder: NotesFolder
    /// The files to import, outside the Secondo cervello.
    let files: URL

    init() throws {
        folder = try NotesFolder()
        files = folder.claude.folder.appending(path: "Registrazioni", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    }

    static let vtt = """
        WEBVTT

        NOTE Esportato da Teams

        1
        00:00:03.000 --> 00:00:05.500 align:start
        <v Anna Rossi>Partiamo dal <b>budget</b> &amp; dai tempi.</v>

        2
        00:00:05.500 --> 00:00:07.000
        <v Anna Rossi>Partiamo dal <b>budget</b> &amp; dai tempi.</v>

        00:01:23.250 --> 00:02:10.000
        Taglierei il 10%.
        """

    static let srt = "1\r\n00:00:01,000 --> 00:00:02,000\r\nCiao a tutti.\r\n\r\n2\r\n01:00:00,500 --> 01:00:04,000\r\n<i>Chiudiamo.</i>\r\n"

    static let txt = "\u{FEFF}Anna: partiamo dal budget.\n\n   Marco:   va bene.  \nMarco:   va bene.\n"

    private func sample(_ text: String, named name: String) throws -> URL {
        let file = files.appending(path: name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// One second of silence at 16 kHz, in the format of `name`'s extension.
    private func silence(named name: String, settings: [String: Any]) throws -> URL {
        let file = files.appending(path: name)
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        let audio = try AVAudioFile(forWriting: file, settings: settings)
        try audio.write(from: buffer)
        return file
    }

    @Test(arguments: [("a.m4a", MeetingImportFile.Kind.audio), ("a.MP3", .audio), ("a.wav", .audio), ("a.mp4", .video),
                      ("a.mov", .video), ("a.vtt", .subtitles), ("a.srt", .subtitles), ("a.txt", .text)])
    func everyListedFormatIsKnown(name: String, kind: MeetingImportFile.Kind) {
        #expect(MeetingImportFile.kind(of: URL(filePath: "/tmp/\(name)")) == kind)
    }

    @Test func onlyRecordingsAndSubtitlesDroppedBecomeRiunioni() {
        let audio = URL(filePath: "/tmp/call.m4a")
        #expect(MeetingImportFile.isMeetingDrop([audio, URL(filePath: "/tmp/call.vtt")]))
        #expect(!MeetingImportFile.isMeetingDrop([audio, URL(filePath: "/tmp/appunti.txt")]))
        #expect(!MeetingImportFile.isMeetingDrop([URL(filePath: "/tmp/cartella/", directoryHint: .isDirectory)]))
        #expect(!MeetingImportFile.isMeetingDrop([]))
    }

    @Test func webVTTLosesItsHeadersTagsAndRepeatsAndKeepsVoicesAndTimes() {
        let (lines, end) = MeetingImportFile.lines(ofSubtitles: Self.vtt)

        #expect(lines.map(\.markdown) == ["**[0:00:03]** Anna Rossi: Partiamo dal budget & dai tempi.",
                                          "**[0:01:23]** Taglierei il 10%."])
        #expect(end == .seconds(130))
    }

    @Test func subRipIsReadWithCommasAndWindowsLineEnds() {
        let (lines, end) = MeetingImportFile.lines(ofSubtitles: Self.srt)

        #expect(lines.map(\.text) == ["Ciao a tutti.", "Chiudiamo."])
        #expect(lines.map(\.start) == [.seconds(1), .milliseconds(3_600_500)])
        #expect(end == .seconds(3604))
    }

    @Test func plainTextKeepsOneSentencePerLineWithoutTime() throws {
        let text = try MeetingImportFile.text(of: sample(Self.txt, named: "riunione.txt"))

        #expect(MeetingImportFile.lines(ofText: text).map(\.markdown) == ["Anna: partiamo dal budget.", "Marco: va bene."])
    }

    @Test func wavAndM4ATellTheirDurationAndTheAudioOfAMovieIsExported() async throws {
        let wav = try silence(named: "a.wav", settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                                                         AVNumberOfChannelsKey: 1])
        let m4a = try silence(named: "a.m4a", settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
                                                         AVNumberOfChannelsKey: 1])

        let wavDuration = try #require(await MeetingImportFile.duration(of: wav))
        #expect(abs((wavDuration - .seconds(1)) / .seconds(1)) < 0.05)
        #expect(await MeetingImportFile.duration(of: m4a) != nil)
        let exported = try await MeetingImportFile.audio(ofVideo: m4a)
        #expect(await MeetingImportFile.duration(of: exported) != nil)
        try FileManager.default.removeItem(at: exported.deletingLastPathComponent())
    }

    @Test func aFileWithoutAudioIsUnreadable() async throws {
        let movie = try sample("non è un video", named: "finto.mov")

        await #expect(throws: MeetingFailure.fileUnreadable) {
            try await MeetingImportFile.audio(ofVideo: movie)
        }
    }

    @Test func aFolderOfTrascrizioniBecomesRiunioniOnceEach() async throws {
        let defaults = try #require(UserDefaults(suiteName: "MeetingImportTests-\(UUID().uuidString)"))
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)
        let importer = MeetingImporter(secondBrain: secondBrain) { _ in
            MeetingSummary(summary: ["Budget"])
        }
        _ = try sample(Self.vtt, named: "Teams.vtt")
        _ = try sample(Self.srt, named: "Zoom.srt")
        _ = try sample(Self.txt, named: "Appunti.txt")
        _ = try sample("ignorato", named: "foto.png")

        await importer.importFiles([files])

        let first = try #require(importer.outcome)
        #expect(first.saved.map(\.lastPathComponent).sorted().map { String($0.dropFirst(11)) }
            == ["Appunti.md", "Teams.md", "Zoom.md"])
        #expect(first.failures.isEmpty && first.duplicates == 0 && !first.isCancelled)
        let note = try String(contentsOf: #require(first.saved.first { $0.lastPathComponent.hasSuffix("Teams.md") }),
                              encoding: .utf8)
        #expect(note.contains("durata: \"3 min\"\n"))
        #expect(note.contains("fonte: Riunione\nfile: \"Teams.vtt\"\nimpronta: "))
        #expect(note.contains("- Budget"))
        #expect(note.contains("**[0:01:23]** Taglierei il 10%."))
        #expect(!importer.isImporting && importer.progress == nil)

        await importer.importFiles([files])

        let second = try #require(importer.outcome)
        #expect(second.saved.isEmpty && second.duplicates == 3)
    }

    @Test func aCancelledImportSavesNothingMoreAndSaysSo() async throws {
        let defaults = try #require(UserDefaults(suiteName: "MeetingImportTests-\(UUID().uuidString)"))
        let secondBrain = SecondBrain(index: nil, defaults: defaults)
        secondBrain.choose(folder.notes)
        let importer = MeetingImporter(secondBrain: secondBrain) { _ in nil }
        _ = try sample(Self.vtt, named: "Teams.vtt")

        let importing = Task { await importer.importFiles([files]) }
        importing.cancel()
        await importing.value

        let outcome = try #require(importer.outcome)
        #expect(outcome.isCancelled && outcome.saved.isEmpty && outcome.failures.isEmpty)
    }

    @Test func withoutSecondoCervelloNothingIsImported() async throws {
        let defaults = try #require(UserDefaults(suiteName: "MeetingImportTests-\(UUID().uuidString)"))
        let importer = MeetingImporter(secondBrain: SecondBrain(index: nil, defaults: defaults)) { _ in nil }

        await importer.importFiles([try sample(Self.vtt, named: "Teams.vtt")])

        #expect(importer.outcome?.failures.map(\.reason) == [.noSecondBrain])
    }
}
