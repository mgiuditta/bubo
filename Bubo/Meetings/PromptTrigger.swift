import Foundation

/// Decides which sentences of a meeting the Suggeritore answers: a question about the past («cosa avevamo deciso su…»,
/// «chi doveva…», «quando è stato approvato…»), said by anyone.
///
/// Pure, so the rules are tested without audio: the caller passes each sentence with the time it was heard.
nonisolated struct PromptTrigger: Sendable {
    /// Why the Suggeritore answers.
    enum Reason: Equatable, Sendable {
        /// Someone asked about the past.
        case pastQuestion
        /// The user asked for an answer to the last question heard.
        case lastQuestion
        /// The user wrote the question.
        case typed
    }

    /// A question to answer.
    struct Question: Equatable, Sendable {
        var text: String
        var reason: Reason
    }

    /// The sentences heard in the last ``recentWindow``, for ``lastQuestion(at:)``.
    private var recent: [(time: Date, line: MeetingLine)] = []
    /// When each question about the past was last answered, so a repeated one is answered once.
    private var answered: [String: Date] = [:]

    /// Creates a trigger that heard nothing yet.
    init() {}

    /// The question in `line`, heard at `time`; `nil` when the Suggeritore lets it go by.
    mutating func question(in line: MeetingLine, at time: Date) -> Question? {
        recent = recent.filter { time.timeIntervalSince($0.time) < Self.recentWindow } + [(time, line)]
        guard Self.asksAboutThePast(line.text) else { return nil }
        let key = line.text.lowercased()
        if let last = answered[key], time.timeIntervalSince(last) < Self.repeatWindow { return nil }
        answered[key] = time
        return Question(text: line.text, reason: .pastQuestion)
    }

    /// The last question heard in the last minute; the last two sentences when none sounds like a question; `nil` when
    /// nothing was said.
    func lastQuestion(at time: Date) -> Question? {
        let heard = recent.filter { time.timeIntervalSince($0.time) < Self.recentWindow }.map(\.line.text)
        let asked = heard.last { Self.asksAboutThePast($0) || $0.contains("?") }
        guard let text = asked ?? (heard.isEmpty ? nil : heard.suffix(2).joined(separator: " ")) else { return nil }
        return Question(text: text, reason: .lastQuestion)
    }

    /// Whether `text` asks about something decided, said or owned before.
    static func asksAboutThePast(_ text: String) -> Bool {
        text.firstMatch(of: pastQuestion) != nil
    }

    /// A question about the past, in Italian and in English; built at each use, since a `Regex` is not `Sendable`.
    private static var pastQuestion: Regex<Substring> { #/
        \b(?:
          (?:cosa|che\ cosa|come)\ (?:avevamo|abbiamo|avete|aveva|hanno|avevano)\ (?:deciso|detto|concordato|stabilito|definito)
        | chi\ (?:doveva|deve|dovrebbe|aveva|si\ era\ preso|si\ è\ preso|se\ ne\ occupa|se\ ne\ doveva)
        | quando\ (?:abbiamo|avevamo|è\ stat[oa]|era\ stat[oa]|si\ era|si\ è)
        | (?:come|dove)\ (?:eravamo|siamo)\ rimasti
        | (?:ti|vi)\ ricord(?:i|ate)\b
        | l['’]ultima\ volta
        | (?:era|è)\ stat[oa]\ (?:deciso|decisa|approvat[oa]|concordat[oa])
        | what\ did\ we\ (?:decide|say|agree)
        | who\ (?:was\ supposed|was\ going|owns)
        | when\ did\ we
        )
        /#.ignoresCase() }

    /// How long a sentence counts for ``lastQuestion(at:)``.
    static let recentWindow: TimeInterval = 60
    /// How long the same question about the past is not answered again.
    static let repeatWindow: TimeInterval = 30
}
