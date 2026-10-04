import Foundation

/// Why a `.bubo` file does not open. Each case is one error sheet of the recipient (spec 24, Errori).
public enum DeliveryError: Error, Equatable, Sendable {
    /// The file cannot be read.
    case unreadable
    /// The file is not a `.bubo`.
    case notBubo
    /// A newer Bubo wrote the file, in this format version.
    case unsupportedVersion(UInt8)
    /// The file is a `.bubo` of the other kind.
    case wrongKind
    /// The Consegna is encrypted for another Macchina's key.
    case otherRecipient
    /// The Consegna was made with another key than the sender's one passed to open it.
    case otherSender
    /// The authentication does not pass: the file was changed, truncated or damaged, or made by another key.
    case damaged
}
