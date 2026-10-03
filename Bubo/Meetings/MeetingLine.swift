import Foundation

/// A sentence of a Riunione's trascrizione: who said it, when from the start, and what.
nonisolated struct MeetingLine: Equatable, Sendable {
    /// Whose track the sentence comes from: the two tracks already tell the user from the others.
    enum Speaker: Equatable, Sendable {
        /// The microphone: the user.
        case me
        /// The app's audio: the other participants.
        case others
        /// One of the other participants, numbered by ``MeetingDiarizer`` in the order they first speak.
        case participant(Int)

        /// The label in the note, fixed in Italian as the note's sections.
        var label: String {
            switch self {
            case .me: "Io"
            case .others: "Altri"
            case let .participant(number): "Parlante \(number)"
            }
        }
    }

    /// Who said it; `nil` in an imported Riunione, whose file does not tell.
    var speaker: Speaker?
    /// The time from the start of the recording; `nil` in an imported trascrizione without times.
    var start: Duration?
    var text: String
    /// How long the sentence lasts; zero when unknown.
    var length: Duration = .zero

    /// The line in the note, such as `**[0:01:23] Io:** Partiamo dal budget.`, `**[0:01:23]** Anna: Partiamo.`, or
    /// the text alone without time nor speaker.
    var markdown: String {
        let time = start.map { "[\($0.formatted(.time(pattern: .hourMinuteSecond)))]" }
        let heading = [time, speaker.map { "\($0.label):" }].compactMap(\.self).joined(separator: " ")
        return heading.isEmpty ? text : "**\(heading)** \(text)"
    }

    /// The lines of every track in the order they were said; at the same time, the user first.
    static func merged(_ tracks: [MeetingLine]...) -> [MeetingLine] {
        tracks.joined()
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.start ?? .zero, $0.speaker == .me ? 0 : 1) < ($1.start ?? .zero, $1.speaker == .me ? 0 : 1) }
    }
}
