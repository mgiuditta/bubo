import CryptoKit
import Foundation

/// The 12-digit code of a pair of Macchine, read aloud to check that a Biglietto came from who it says (spec 24).
///
/// The SHA-256 of `"bubo-biglietto-v1" ‖ min(A, B) ‖ max(A, B)` over the two public keys in x9.63 form, ordered as
/// byte strings; its first 5 bytes as a big-endian integer modulo 10¹². The same on both Macs, whichever key is
/// whose.
public struct VerificationCode: Hashable, Sendable, CustomStringConvertible {
    /// The 12 digits, with leading zeros.
    public let digits: String

    /// The code of the pair of `key` and `otherKey`, in either order.
    public init(_ key: P256.KeyAgreement.PublicKey, _ otherKey: P256.KeyAgreement.PublicKey) {
        let first = key.x963Representation
        let second = otherKey.x963Representation
        let (low, high) = first.lexicographicallyPrecedes(second) ? (first, second) : (second, first)
        var hash = SHA256()
        hash.update(data: Data("bubo-biglietto-v1".utf8))
        hash.update(data: low)
        hash.update(data: high)
        let number = hash.finalize().prefix(5).reduce(UInt64(0)) { $0 << 8 | UInt64($1) } % 1_000_000_000_000
        let text = String(number)
        digits = String(repeating: "0", count: 12 - text.count) + text
    }

    /// The 3 groups of 4 digits, as the code is shown and read.
    public var groups: [String] {
        stride(from: 0, to: 12, by: 4).map { start in
            let begin = digits.index(digits.startIndex, offsetBy: start)
            return String(digits[begin..<digits.index(begin, offsetBy: 4)])
        }
    }

    /// The code in groups, `4821 0937 5562`.
    public var description: String {
        groups.joined(separator: " ")
    }
}
