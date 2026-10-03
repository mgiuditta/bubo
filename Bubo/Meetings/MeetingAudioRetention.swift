import Foundation

/// How long the audio of a Riunione stays on the Mac, in Application Support and never in the Secondo cervello.
nonisolated enum MeetingAudioRetention: String, CaseIterable, Identifiable, Sendable {
    /// Thirty days from the recording, then deleted at the next launch or Riunione.
    case thirtyDays
    /// Deleted as soon as the note is written.
    case afterTranscription

    var id: Self { self }

    /// The key of the choice in the user defaults.
    static let defaultsKey = "meetings.audioRetention"

    /// The choice saved in `defaults`; thirty days when none was made.
    static func saved(in defaults: UserDefaults) -> MeetingAudioRetention {
        defaults.string(forKey: defaultsKey).flatMap(MeetingAudioRetention.init(rawValue:)) ?? .thirtyDays
    }
}
