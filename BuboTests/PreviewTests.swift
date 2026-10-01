import Foundation
import Testing
import WebKit
@testable import Bubo

/// The Anteprima of a Sessione's server: it goes only to the Sessione's `localhost` servers and to the `url` of its
/// `launch.json`, keeps cookies per Sessione and opens only with a server (spec 15).
@MainActor
struct PreviewTests {
    /// A Sessione with servers on 47100 and 47101, and a `launch.json` with a local HTTPS address.
    let policy = PreviewPolicy(ports: [47_100, 47_101], launchConfigs: [
        LaunchConfig(name: "web", url: "https://app.localhost:47443/login"),
        LaunchConfig(name: "api", url: "http://127.0.0.1:47500"),
        LaunchConfig(name: "remoto", url: "https://example.com"),
    ])

    @Test(arguments: [
        "http://localhost:47100/",
        "http://localhost:47101/dashboard?tab=1",
        "http://app.localhost:47100/",
        "https://app.localhost:47443/",
        "http://localhost:47500/health",
        "about:blank",
    ])
    func theSessionesServersOpen(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(policy.decision(for: url, isMainFrame: true) == .allow)
        #expect(policy.decision(for: url, isMainFrame: false) == .allow)
    }

    @Test(arguments: [
        // Another Sessione's server, by name or by address.
        "http://localhost:47110/",
        "http://127.0.0.1:47110/",
        "http://127.0.0.1:47100/",
        "http://[::1]:47100/",
        "http://0.0.0.0:47100/",
        // Schemes that are not the web.
        "file:///etc/passwd",
        "javascript:alert(1)",
        "data:text/html,<p>ciao</p>",
    ])
    func everyOtherLocalAddressIsCancelled(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(policy.decision(for: url, isMainFrame: true) == .cancel)
        #expect(policy.decision(for: url, isMainFrame: false) == .cancel)
    }

    @Test func anExternalPageGoesToTheBrowserOnlyAsThePageItself() throws {
        let url = try #require(URL(string: "https://example.com/"))
        #expect(policy.decision(for: url, isMainFrame: true) == .openInBrowser)
        #expect(policy.decision(for: url, isMainFrame: false) == .cancel)
    }

    @Test func theAnteprimaOpensAtTheLaunchAddressOfAServerThatListensElseAtTheFirstServer() throws {
        #expect(policy.startURL == URL(string: "http://localhost:47100/"))
        let withLaunch = PreviewPolicy(ports: [47_443, 47_100], launchConfigs: [
            LaunchConfig(name: "web", url: "https://app.localhost:47443/login"),
        ])
        #expect(withLaunch.startURL == URL(string: "https://app.localhost:47443/login"))
        #expect(PreviewPolicy(ports: []).startURL == nil)
    }

    @Test func eachSessioneHasACookieStoreOfItsOwn() async throws {
        let first = UUID()
        let second = UUID()
        let firstStore = PreviewPage.makeConfiguration(for: first).websiteDataStore
        let secondStore = PreviewPage.makeConfiguration(for: second).websiteDataStore
        #expect(firstStore.identifier == first)
        #expect(secondStore.identifier == second)
        #expect(firstStore.isPersistent && secondStore.isPersistent)
        #expect(PreviewPage.makeConfiguration(for: first).websiteDataStore.identifier == first)
        try await WKWebsiteDataStore.remove(forIdentifier: first)
        try await WKWebsiteDataStore.remove(forIdentifier: second)
    }

    @Test func withoutAServerShortcutDoesNothing() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "Sessioni-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: .ferma)
        try JSONEncoder().encode([session]).write(to: file)
        let store = SessionStore(file: file, worktrees: WorktreeManager(root: FileManager.default.temporaryDirectory)) {
            throw CancellationError()
        }

        store.togglePreview()
        store.showPreview(of: session)

        #expect(store.previewSession == nil)
        #expect(!store.previews.isShown)
        #expect(store.previews.pages.isEmpty)
    }

    @Test func theAnteprimaClosesWhenItsServerGoes() async throws {
        let session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"), activity: .ferma)
        let previews = PreviewStore()
        let server = ListeningSocket(pid: 1, port: 47_199, folder: nil)

        previews.show(session, servers: [server])
        #expect(previews.isShown)
        #expect(previews.shown?.sessionID == session.id)

        previews.update(with: [session.id: [server]])
        #expect(previews.pages[session.id] != nil)

        previews.update(with: [:])
        #expect(previews.pages.isEmpty)
        #expect(!previews.isShown)
        try? await WKWebsiteDataStore.remove(forIdentifier: session.id)
    }
}
