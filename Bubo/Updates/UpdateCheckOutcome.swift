import Foundation

/// What a check without windows found in the appcast.
nonisolated enum UpdateCheckOutcome: Equatable, Sendable {
    /// A newer version the Canale admits, with its build number (`sparkle:version`).
    case found(version: String)
    /// No newer version the Canale admits.
    case upToDate
    /// The check failed, with Sparkle's error code (`SUError`): an unsigned feed, no network, a broken appcast.
    case failed(code: Int)
}
