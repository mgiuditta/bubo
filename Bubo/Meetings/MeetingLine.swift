import Foundation

/// A sentence of a Riunione's trascrizione: who said it, when from the start, and what.
nonisolated struct MeetingLine: Equatable, Sendable {
    /// Whose track the sentence comes from: the two tracks already tell the user from the others.
    enum Speaker: Sendable {
        /// The microphone: the user.
        case me
        /// The app's audio: the other participants.
        case others

        /// The label in the note, fixed in Italian as the note's sections.
        var label: String {
            switch self {
            case .me: "Io"
            case .others: "Altri"
            }
        }
    }

    var speaker: Speaker
    /// The time from the start of the recording.
    var start: Duration
    var text: String

    /// The line in the note, such as `**[0:01:23] Io:** Partiamo dal budget.`
    var markdown: String {
        "**[\(start.formatted(.time(pattern: .hourMinuteSecond)))] \(speaker.label):** \(text)"
    }

    /// The lines of every track in the order they were said; at the same time, the user first.
    static func merged(_ tracks: [MeetingLine]...) -> [MeetingLine] {
        tracks.joined()
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.start, $0.speaker == .me ? 0 : 1) < ($1.start, $1.speaker == .me ? 0 : 1) }
    }
}
