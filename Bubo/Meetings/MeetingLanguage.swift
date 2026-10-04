import Foundation

/// The main language of the Riunioni, in which they are transcribed: the Mac's unless the user chose another.
nonisolated enum MeetingLanguage {
    /// The key of the choice in the user defaults: a language code, absent for the Mac's language.
    static let defaultsKey = "meetings.language"

    /// The languages offered besides the Mac's, by code.
    static let offered = ["it", "en", "es", "fr", "de", "pt"]

    /// The language saved in `defaults`; the Mac's when none was chosen.
    static func saved(in defaults: UserDefaults = .standard) -> Locale {
        defaults.string(forKey: defaultsKey).map { Locale(identifier: $0) } ?? .current
    }
}
