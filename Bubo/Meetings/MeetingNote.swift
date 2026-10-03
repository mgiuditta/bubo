import Foundation

/// A Riunione as a note of the Secondo cervello: properties for Obsidian, the summary, then the trascrizione.
nonisolated struct MeetingNote: Equatable, Sendable {
    var title: String
    /// When the recording started.
    var start: Date
    var duration: Duration
    /// The name of the app whose audio was recorded; `nil` with the microphone only.
    var app: String?
    /// The participants' names; empty until the user writes them, as Bubo cannot tell them.
    var participants: [String] = []
    /// The summary; `nil` when no engine could write it.
    var summary: MeetingSummary?
    var transcript: [MeetingLine]

    /// The whole note, with the day and the hour of `timeZone`.
    func markdown(in timeZone: TimeZone) -> String {
        let day = start.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = start.formatted(Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: timeZone, calendar: calendar))
        let minutes = Int((duration / .seconds(60)).rounded(.up))
        let properties = [
            "---",
            "titolo: \(SummaryProperties.quoted(title))",
            "data: \(day)",
            "ora: \(SummaryProperties.quoted(time))",
            "durata: \(SummaryProperties.quoted("\(minutes) min"))",
            "app: \(SummaryProperties.quoted(app ?? ""))",
            "partecipanti: [\(participants.map(SummaryProperties.quoted).joined(separator: ", "))]",
            "fonte: Riunione",
            "---",
        ]
        let summary = summary?.markdown ?? "## Riassunto\n\nNon scritto: nessun modello era disponibile."
        let lines = transcript.isEmpty ? "Nessuna parola riconosciuta." : transcript.map(\.markdown).joined(separator: "\n\n")
        return properties.joined(separator: "\n") + "\n\n" + summary + "\n\n## Trascrizione\n\n" + lines + "\n"
    }
}
