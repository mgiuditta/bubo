import Foundation
import Testing
@testable import Bubo

/// What Sparkle needs in Bubo.app, and what it must not have.
struct UpdateBundleTests {
    @Test func theBundleHasNoXPCServices() throws {
        let app = Bundle.main.bundleURL
        let sparkle = app.appending(path: "Contents/Frameworks/Sparkle.framework")
        #expect(FileManager.default.fileExists(atPath: sparkle.path()), "Sparkle.framework manca nel bundle.")
        let files = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        let services = files.compactMap { ($0 as? URL)?.pathExtension == "xpc" ? $0 : nil }
        #expect(services.isEmpty, "Servizi XPC nel bundle: \(services)")
    }

    @Test func theInfoPlistHasTheProductionKeys() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SUEnableSystemProfiling"] as? Bool == false)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86_400)
        #expect(!(info["BuboReleaseName"] as? String ?? "").isEmpty)
    }

    /// Fails in a Release build until #220 fills in `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` in `project.yml`.
    @Test(.enabled(if: !ReleaseArea.isDebugBuild, "Solo in Release: in Debug feed e chiave possono mancare."))
    func aReleaseHasTheFeedAndTheKey() {
        #expect(UpdateEligibility.hasFeedAndKey(in: .main),
                "SUFeedURL o SUPublicEDKey vuoti: da riempire in project.yml con #220.")
    }
}
