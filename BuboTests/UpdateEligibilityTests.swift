import Foundation
import Testing
@testable import Bubo

/// Only a Release build with the feed and the key of #220, signed Developer ID, updates itself.
struct UpdateEligibilityTests {
    @Test(arguments: [false, true], [false, true])
    func onlyAReleaseWithFeedKeyAndDeveloperIDUpdates(isDebugBuild: Bool, hasFeedAndKey: Bool) {
        for isSigned in [false, true] {
            let eligibility = UpdateEligibility(isDebugBuild: isDebugBuild, hasFeedAndKey: hasFeedAndKey,
                                                isSignedDeveloperID: isSigned)
            #expect(eligibility.allowsUpdates == (!isDebugBuild && hasFeedAndKey && isSigned))
        }
    }

    @Test(arguments: [
        ("https://mgiuditta.github.io/bubo-releases/appcast.xml", String(repeating: "A", count: 43) + "=", true),
        ("", String(repeating: "A", count: 43) + "=", false),
        ("http://mgiuditta.github.io/bubo-releases/appcast.xml", String(repeating: "A", count: 43) + "=", false),
        ("https://mgiuditta.github.io/bubo-releases/appcast.xml", "", false),
        ("https://mgiuditta.github.io/bubo-releases/appcast.xml", "non è una chiave", false),
    ])
    func feedAndKeyMustBothBeFilledIn(feed: String, key: String, isValid: Bool) throws {
        let folder = URL.temporaryDirectory.appending(path: "UpdateEligibilityTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let contents = folder.appending(path: "Fake.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "com.mgiuditta.bubo.tests.eligibility", "SUFeedURL": feed, "SUPublicEDKey": key]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        let bundle = try #require(Bundle(url: folder.appending(path: "Fake.app")))
        #expect(UpdateEligibility.hasFeedAndKey(in: bundle) == isValid)
    }

    @Test func aDebugBuildNeverUpdates() {
        #expect(UpdateEligibility.current.isDebugBuild == ReleaseArea.isDebugBuild)
        if ReleaseArea.isDebugBuild { #expect(!UpdateEligibility.current.allowsUpdates) }
    }
}
