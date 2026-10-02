import Foundation

/// A message the page wrote to its console, or an error it did not catch (spec 15).
nonisolated struct ConsoleLine: Identifiable, Equatable, Sendable {
    /// How serious the message is, from `console.*` or from an uncaught error.
    enum Level: Sendable {
        case log, warning, error

        /// The level of `console.<name>`; an uncaught error or rejection says `error`.
        init(_ name: String) {
            switch name {
            case "warn": self = .warning
            case "error": self = .error
            default: self = .log
            }
        }
    }

    let id = UUID()
    let level: Level
    let text: String
}
