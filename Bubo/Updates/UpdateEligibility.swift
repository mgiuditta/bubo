import Foundation
import Security

/// Whether this build may update itself: only a Release build, with the feed and the EdDSA key of #220, signed with a
/// Developer ID (spec 27).
///
/// Otherwise Sparkle never starts: with no key it would show its error window at every launch.
nonisolated struct UpdateEligibility: Equatable, Sendable {
    /// Whether the build is a Debug build.
    var isDebugBuild: Bool
    /// Whether `SUFeedURL` is an HTTPS address and `SUPublicEDKey` an EdDSA public key.
    var hasFeedAndKey: Bool
    /// Whether the running app is signed with a Developer ID certificate.
    var isSignedDeveloperID: Bool

    /// Whether the build updates itself.
    var allowsUpdates: Bool { !isDebugBuild && hasFeedAndKey && isSignedDeveloperID }

    /// The eligibility of the running app.
    static var current: UpdateEligibility {
        UpdateEligibility(isDebugBuild: ReleaseArea.isDebugBuild, hasFeedAndKey: hasFeedAndKey(in: Bundle.main),
                          isSignedDeveloperID: isRunningCodeSignedDeveloperID())
    }

    /// Returns whether `bundle` names an HTTPS feed and a 32-byte EdDSA public key, the two values #220 fills in.
    static func hasFeedAndKey(in bundle: Bundle) -> Bool {
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return URL(string: feed)?.scheme == "https" && Data(base64Encoded: key)?.count == 32
    }

    /// Returns whether the running app is signed with a Developer ID Application certificate.
    ///
    /// Checks the running code, as the kernel validated it, not every file of the bundle again.
    private static func isRunningCodeSignedDeveloperID() -> Bool {
        let developerID = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(developerID as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
