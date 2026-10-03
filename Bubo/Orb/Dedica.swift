import CryptoKit
import Foundation

/// A greeting meant for one person: on her Mac the Orb greets with a heart and a line, instead of the owl.
///
/// Her name is kept here only as the SHA-256 of its two words, so the repository does not spell it out.
nonisolated enum Dedica {
    /// How long the heart stays, Morph into it and back included.
    static let duration: Double = 5
    /// How long the still heart stays with Reduce Motion on.
    static let stillDuration: Double = 4

    /// The line under the Orb while the heart lasts.
    static let message = LocalizedStringResource("Qualcuno ti pensa sempre.",
                                                 comment: "Line under the Orb in a greeting meant for one person.")

    /// The SHA-256 of each word of her name, lowercased and without accents.
    private static let nameWords: Set<String> = [
        "0ce93c9606f0685bf60e051265891d256381f639d05c0aec67c84eec49d33cc1",
        "ab2f597b85eb1ab86654dd8af36fd20ceecfebe9098eb94ca70f28973402393a",
    ]

    /// Whether the greeting is meant for the account named `fullName`: both words of her name appear in it,
    /// in any order, ignoring case and accents.
    static func isMeant(forFullName fullName: String) -> Bool {
        let words = fullName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter }
            .map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
        return nameWords.isSubset(of: words)
    }

    /// How long after the heart appears the Orb is asked back to the Blob, so the whole greeting lasts its duration.
    static func returnDelay(reducesMotion: Bool) -> Double {
        reducesMotion ? stillDuration : duration - MorphDirector.morphDuration
    }
}
