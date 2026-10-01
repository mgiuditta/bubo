import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import Bubo

/// The agent's tools on the Anteprima: the same page as the user, never outside the Sessione's servers, ended by a
/// click of the user or by the time limit (spec 15).
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PreviewDriverTests {
    /// An Anteprima with a server on 47198 and nothing loaded, which records what it would open in the browser.
    final class Fixture {
        let session = UUID()
        var openedInBrowser: [URL] = []
        lazy var preview = PreviewPage(sessionID: session, policy: PreviewPolicy(ports: [47_198])) { [weak self] url in
            self?.openedInBrowser.append(url)
        }

        func tearDown() async {
            preview.close()
            try? await WKWebsiteDataStore.remove(forIdentifier: session)
        }
    }

    /// A PNG of `width` × `height` pixels.
    static func png(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func size(of jpeg: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    @Test func aScreenshotIsAtMost1568PixelsOnItsLongSide() throws {
        let wide = try PreviewDriver.jpeg(from: Self.png(width: 3_136, height: 1_000), longSide: 1_568)
        #expect(try Self.size(of: wide) == (1_568, 500))
        let tall = try PreviewDriver.jpeg(from: Self.png(width: 1_000, height: 3_136), longSide: 1_568)
        #expect(try Self.size(of: tall) == (500, 1_568))
        let small = try PreviewDriver.jpeg(from: Self.png(width: 800, height: 600), longSide: 1_568)
        #expect(try Self.size(of: small) == (800, 600))
    }

    @Test func consoleAndRequestsAreTheLast200LinesThatMatchTheFilter() {
        let lines = (1...300).map { $0.isMultiple(of: 2) ? "GET /api/\($0) 200" : "img /logo.png \($0)" }
        let api = PreviewDriver.lastLines(lines, containing: "API", otherwise: "niente").split(separator: "\n")
        #expect(api.count == 150)
        let all = PreviewDriver.lastLines(lines, containing: nil, otherwise: "niente").split(separator: "\n")
        #expect(all.count == 200)
        #expect(all.first == "img /logo.png 101")
        #expect(PreviewDriver.lastLines(lines, containing: "css", otherwise: "niente") == "niente")
    }

    @Test func aScriptsValueComesBackAsJSON() {
        #expect(PreviewDriver.json(["b": 1, "a": [true]]) == #"{"a":[true],"b":1}"#)
        #expect(PreviewDriver.json("ciao") == #""ciao""#)
        #expect(PreviewDriver.json(nil) == "undefined")
        #expect(PreviewDriver.json(NSNull()) == "undefined")
    }

    @Test(arguments: [
        PreviewAction.navigate(to: "https://example.com/"),
        .navigate(to: "http://127.0.0.1:47198/"),
        .navigate(to: "http://localhost:47110/"),
        .navigate(to: "file:///etc/passwd"),
        .runJavaScript(code: "location.href = 'https://example.com/'"),
        .runJavaScript(code: "location.href = 'http://127.0.0.1:47198/'"),
        .runJavaScript(code: "const a = document.createElement('a'); a.href = 'https://example.com/'; document.documentElement.append(a); a.click()"),
    ])
    func theAgentNeverLeavesTheSessionesServers(action: PreviewAction) async {
        let fixture = Fixture()
        let reply = await PreviewDriver(preview: fixture.preview).perform(action)
        guard case let .failure(message) = reply else {
            Issue.record("The action succeeded: \(reply)")
            return
        }
        #expect(message.contains("non è un server della Sessione"))
        #expect(fixture.openedInBrowser.isEmpty)
        #expect(fixture.preview.page.url?.host() != "example.com")
        await fixture.tearDown()
    }

    @Test func aWindowTheAgentOpensGoesNowhere() async {
        let fixture = Fixture()
        _ = await PreviewDriver(preview: fixture.preview).perform(.runJavaScript(code: "window.open('https://example.com/')"))
        #expect(fixture.openedInBrowser.isEmpty)
        #expect(fixture.preview.page.url?.host() != "example.com")
        await fixture.tearDown()
    }

    @Test func screenshotsAndClicksAreFastOnThePageTheUserSees() async throws {
        let fixture = Fixture()
        let page = fixture.preview.page
        for try await _ in page.load(html: """
            <button id="b" onclick="this.dataset.count = (+this.dataset.count || 0) + 1">Invia</button>
            """, baseURL: try #require(URL(string: "http://localhost:47198/"))) {}
        let driver = PreviewDriver(preview: fixture.preview)
        let clock = ContinuousClock()
        var slowestScreenshot = Duration.zero
        var slowestClick = Duration.zero

        for _ in 1...50 {
            let start = clock.now
            let screenshot = await driver.perform(.screenshot)
            slowestScreenshot = max(slowestScreenshot, clock.now - start)
            guard case let .image(jpeg) = screenshot else {
                Issue.record("No screenshot: \(screenshot)")
                return
            }
            let size = try Self.size(of: jpeg)
            #expect(max(size.width, size.height) <= PreviewDriver.screenshotLongSide)
        }
        for _ in 1...50 {
            let start = clock.now
            #expect(await driver.perform(.click(selector: "#b")) != .failure(PreviewDriver.tookControl))
            slowestClick = max(slowestClick, clock.now - start)
        }

        #expect(slowestScreenshot < .milliseconds(500))
        #expect(slowestClick < .milliseconds(200))
        #expect(await driver.perform(.runJavaScript(code: "return document.getElementById('b').dataset.count")) == .text(#""50""#))
        await fixture.tearDown()
    }

    @Test func aClickOfTheUserEndsTheAgentsActionWithin100Milliseconds() async throws {
        let fixture = Fixture()
        let driver = PreviewDriver(preview: fixture.preview)
        let action = Task { await driver.perform(.runJavaScript(code: "return new Promise(() => {})")) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.preview.isDrivenByAgent)

        let clock = ContinuousClock()
        let interaction = clock.now
        fixture.preview.userDidInteract()
        let reply = await action.value

        #expect(reply == .failure(PreviewDriver.tookControl))
        #expect(clock.now - interaction < .milliseconds(100))
        await fixture.tearDown()
    }

    @Test func anActionEndsAtItsTimeLimit() async {
        let fixture = Fixture()
        let driver = PreviewDriver(preview: fixture.preview, timeout: .milliseconds(200))
        let clock = ContinuousClock()
        let start = clock.now

        let reply = await driver.perform(.runJavaScript(code: "return new Promise(() => {})"))

        guard case let .failure(message) = reply else {
            Issue.record("The action did not time out: \(reply)")
            return
        }
        #expect(message.contains("10 s"))
        #expect(clock.now - start < .seconds(2))
        await fixture.tearDown()
    }
}
