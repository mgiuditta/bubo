import Foundation
import Testing
@testable import Bubo

struct MeetingDiarizerTests {
    private func turn(_ speaker: String, _ start: Int, _ end: Int) -> MeetingDiarizer.Turn {
        MeetingDiarizer.Turn(speaker: speaker, start: .seconds(start), end: .seconds(end))
    }

    private func line(_ start: Int, lasting duration: Int = 0) -> MeetingLine {
        MeetingLine(speaker: .others, start: .seconds(start), text: "…", duration: .seconds(duration))
    }

    @Test func voicesAreNumberedInTheOrderTheyFirstSpeak() {
        let turns = [turn("SPEAKER_02", 0, 10), turn("SPEAKER_00", 10, 20), turn("SPEAKER_02", 20, 30)]
        let lines = MeetingDiarizer.lines([line(1), line(12), line(25)], attributedTo: turns)
        #expect(lines.map(\.speaker) == [.participant(1), .participant(2), .participant(1)])
        #expect(lines.map(\.speaker.label) == ["Parlante 1", "Parlante 2", "Parlante 1"])
    }

    @Test func aLineGoesToTheTurnItOverlapsMost() {
        let turns = [turn("A", 0, 10), turn("B", 10, 30)]
        let lines = MeetingDiarizer.lines([line(8, lasting: 10)], attributedTo: turns)
        #expect(lines.first?.speaker == .participant(1))
        #expect(MeetingDiarizer.lines([line(0, lasting: 4), line(8, lasting: 10)], attributedTo: turns)
            .map(\.speaker) == [.participant(1), .participant(2)])
    }

    @Test func aLineBetweenTurnsGoesToTheNearest() {
        let turns = [turn("A", 0, 5), turn("B", 20, 30)]
        let lines = MeetingDiarizer.lines([line(1), line(18)], attributedTo: turns)
        #expect(lines.map(\.speaker) == [.participant(1), .participant(2)])
    }

    @Test func withoutTurnsTheLinesKeepTheOthers() {
        #expect(MeetingDiarizer.lines([line(1)], attributedTo: []).map(\.speaker) == [.others])
    }
}
