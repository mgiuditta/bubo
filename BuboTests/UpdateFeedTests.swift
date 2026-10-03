import CryptoKit
import Foundation
import Sparkle
import Testing
@testable import Bubo

/// Sparkle against a local appcast, signed as `sign_update` signs it, with a key pair made for the test (spec 27).
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct UpdateFeedTests {
    /// The appcast of the tests: the stable at build 2, the beta at build 3.
    private static let items = [(version: "2", channel: nil), (version: "3", channel: Optional(UpdateController.betaChannel))]

    @Test func stableChannelIgnoresTheBeta() async throws {
        let app = try await FakeApp(build: "1", items: Self.items)
        defer { app.remove() }
        let outcome = await app.check(receivingBeta: false)
        #expect(outcome == .found(version: "2"))
    }

    @Test func receivingBetaFindsTheBeta() async throws {
        let app = try await FakeApp(build: "1", items: Self.items)
        defer { app.remove() }
        let outcome = await app.check(receivingBeta: true)
        #expect(outcome == .found(version: "3"))
    }

    @Test func turningBetaOffNeverOffersAnOlderVersion() async throws {
        let app = try await FakeApp(build: "3", items: Self.items)
        defer { app.remove() }
        let outcome = await app.check(receivingBeta: false)
        #expect(outcome == .upToDate)
    }

    @Test func anUnsignedFeedIsRefused() async throws {
        let app = try await FakeApp(build: "1", items: Self.items, signsFeed: false)
        defer { app.remove() }
        let outcome = await app.check(receivingBeta: true)
        #expect(outcome != .upToDate)
        if case .found = outcome { Issue.record("Un feed senza firma ha proposto una versione.") }
    }
}

/// An app bundle in a temporary folder with the production `SU*` keys, a test EdDSA key and a local appcast.
@MainActor
private struct FakeApp {
    let folder: URL
    let bundle: Bundle
    let defaults: UserDefaults
    let server: LocalFeedServer
    private let suiteName: String

    init(build: String, items: [(version: String, channel: String?)], signsFeed: Bool = true) async throws {
        folder = URL.temporaryDirectory.appending(path: "UpdateFeedTests-\(UUID().uuidString)")
        let contents = folder.appending(path: "Fake.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let key = Curve25519.Signing.PrivateKey()

        let enclosure = Data("not an app".utf8)
        // Never downloaded: a check without windows reads only the appcast.
        let enclosureURL = "https://example.com/Fake.zip"
        let enclosureSignature = try key.signature(for: enclosure).base64EncodedString()
        let entries = items.map { item in
            """
            <item>
              <title>\(item.version)</title>
              <sparkle:version>\(item.version)</sparkle:version>
              <sparkle:shortVersionString>0.\(item.version)</sparkle:shortVersionString>
              \(item.channel.map { "<sparkle:channel>\($0)</sparkle:channel>" } ?? "")
              <enclosure url="\(enclosureURL)" length="\(enclosure.count)" type="application/octet-stream" sparkle:edSignature="\(enclosureSignature)"/>
            </item>
            """
        }
        var feed = Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel><title>Bubo</title>
            \(entries.joined(separator: "\n"))
            </channel></rss>

            """.utf8)
        if signsFeed {
            // The signing block of `sign_update` 2.10.0 (common_cli/Signing.swift).
            let signature = try key.signature(for: feed).base64EncodedString()
            feed.append(Data("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: \(feed.count)\n-->\n".utf8))
        }
        server = try await LocalFeedServer(body: feed)

        let identifier = "com.mgiuditta.bubo.tests.update-\(UUID().uuidString)"
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier, "CFBundleName": "Fake", "CFBundleExecutable": "Fake",
            "CFBundlePackageType": "APPL", "CFBundleVersion": build, "CFBundleShortVersionString": "0.\(build)",
            "SUFeedURL": server.url.absoluteString, "SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString(),
            "SUEnableAutomaticChecks": false, "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
            "SUEnableSystemProfiling": false,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        bundle = try #require(Bundle(url: folder.appending(path: "Fake.app")))
        suiteName = "UpdateFeedTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        self.identifier = identifier
    }

    private let identifier: String

    /// Checks the appcast without windows, with "Ricevi le beta" as given.
    func check(receivingBeta: Bool) async -> UpdateCheckOutcome {
        let updates = UpdateController(hostBundle: bundle, defaults: defaults, isEnabled: true)
        updates.receivesBeta = receivingBeta
        return await updates.checkForUpdateInformation()
    }

    /// Removes the bundle, the defaults of the test and the ones Sparkle wrote for the bundle.
    func remove() {
        server.stop()
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removePersistentDomain(forName: identifier)
    }
}
