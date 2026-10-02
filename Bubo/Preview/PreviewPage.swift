import AppKit
import os
import WebKit

/// The Anteprima of a Sessione: one `WebPage`, with cookies of its own, that opens only the Sessione's servers
/// (spec 15).
///
/// The page runs the Progetto's code inside Bubo, so microphone and camera are always denied and the only bridge to
/// Bubo is the page script's messages: console, requests and the user's clicks and keys. It stays alive with the panel
/// closed, as the agent uses it there too; it closes when its server goes or the Sessione is Fusa or Archiviata, while
/// its cookies stay.
@Observable
final class PreviewPage {
    let sessionID: UUID
    let page: WebPage
    /// Where the page may go: updated when the Sessione's servers change.
    @ObservationIgnored var policy: PreviewPolicy
    /// The width the page is shown at, with its user agent.
    var width = PreviewWidth.desktop {
        didSet {
            guard width != oldValue else { return }
            page.customUserAgent = width.userAgent
            page.reload()
        }
    }
    /// The last lines of the page's console, oldest first.
    private(set) var console: [ConsoleLine] = []
    /// The address whose certificate is not trusted, offered to the system browser; `nil` when the page loads.
    private(set) var untrustedURL: URL?
    /// The process listening on each port, to reload the page when its server comes back.
    @ObservationIgnored var serverPIDs: [Int: pid_t] = [:]
    /// Whether the agent is using the page, for the label "L'agente usa l'anteprima".
    private(set) var isDrivenByAgent = false
    /// The last `fetch` and `XMLHttpRequest` requests of the page, oldest first.
    @ObservationIgnored private(set) var requests: [String] = []
    /// The navigation cancelled while the agent had the page, for its tool to fail; `nil` when none.
    @ObservationIgnored var cancelledNavigation: URL?

    /// How many console lines and requests are kept.
    static let consoleLimit = 200
    /// The name the console script posts to.
    private static let consoleHandlerName = "buboConsole"

    @ObservationIgnored private let contentController: WKUserContentController
    @ObservationIgnored private let openInBrowser: (URL) -> Void
    @ObservationIgnored private var navigationWatch: Task<Void, Never>?
    /// Whether the agent acted last, not the user: an external page then never reaches the system browser.
    @ObservationIgnored private var agentHasControl = false
    /// How many of the agent's actions are running.
    @ObservationIgnored private var agentActions = 0
    /// The running actions waiting to hear that the user took control.
    @ObservationIgnored private var takeoverWatchers: [AsyncStream<Void>.Continuation] = []
    /// Clears ``isDrivenByAgent`` a little after the last action, so the label does not flicker between actions.
    @ObservationIgnored private var drivingEnd: Task<Void, Never>?

    /// Creates the Anteprima of the Sessione `sessionID`, going only where `policy` allows.
    ///
    /// - Parameter openInBrowser: Opens an external page the user asked for; the system browser outside tests.
    init(sessionID: UUID, policy: PreviewPolicy, openInBrowser: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.sessionID = sessionID
        self.policy = policy
        self.openInBrowser = openInBrowser
        let configuration = Self.makeConfiguration(for: sessionID)
        contentController = configuration.userContentController
        let decider = NavigationDecider()
        page = WebPage(configuration: configuration, navigationDecider: decider)
        page.isInspectable = true
        decider.owner.value = self
        let handler = ConsoleHandler()
        handler.owner = self
        contentController.add(handler, contentWorld: .page, name: Self.consoleHandlerName)
        navigationWatch = Task { [weak self] in await self?.watchNavigations() }
    }

    /// The configuration of the Sessione `sessionID`'s page: its own cookie store, no microphone or camera, and the
    /// console script.
    static func makeConfiguration(for sessionID: UUID) -> WebPage.Configuration {
        var configuration = WebPage.Configuration()
        // A login in one Sessione does not exist in another; the store outlives the page.
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: sessionID)
        configuration.deviceSensorAuthorization = .init(decision: .deny)
        // In the page's world: in a world of its own `console` would be another copy, deaf to the page's calls.
        configuration.userContentController.addUserScript(
            WKUserScript(source: consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        return configuration
    }

    /// Opens `url`, clearing the page "Apri nel browser" of an earlier load, and returns the load's events.
    @discardableResult
    func load(_ url: URL) -> some AsyncSequence<WebPage.NavigationEvent, any Error> {
        untrustedURL = nil
        return page.load(url)
    }

    /// Loads the page again, from the server.
    func reload() {
        untrustedURL = nil
        page.reload()
    }

    /// Opens the address with the untrusted certificate in the system browser.
    func openUntrustedInBrowser() {
        guard let untrustedURL else { return }
        openInBrowser(untrustedURL)
    }

    /// Starts one of the agent's actions; the stream says when the user takes control with a click or a key.
    func agentWillAct() -> AsyncStream<Void> {
        let (takeover, watcher) = AsyncStream.makeStream(of: Void.self)
        takeoverWatchers.append(watcher)
        agentActions += 1
        agentHasControl = true
        cancelledNavigation = nil
        drivingEnd?.cancel()
        isDrivenByAgent = true
        return takeover
    }

    /// Ends one of the agent's actions.
    func agentDidAct() {
        agentActions -= 1
        guard agentActions == 0 else { return }
        takeoverWatchers.forEach { $0.finish() }
        takeoverWatchers = []
        drivingEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.isDrivenByAgent = false
        }
    }

    /// A click or a key of the user in the page: the agent's running actions fail, and the page is the user's again.
    func userDidInteract() {
        agentHasControl = false
        guard !takeoverWatchers.isEmpty else { return }
        Logger.preview.notice("The user took control of the Anteprima: agent action interrupted")
        for watcher in takeoverWatchers {
            watcher.yield()
            watcher.finish()
        }
        takeoverWatchers = []
    }

    /// Stops the page before it is let go: its cookies stay in the Sessione's store.
    func close() {
        navigationWatch?.cancel()
        drivingEnd?.cancel()
        takeoverWatchers.forEach { $0.finish() }
        page.stopLoading()
        contentController.removeAllScriptMessageHandlers()
    }

    /// What to do with a navigation to `url`, opening it in the system browser when the policy says so.
    fileprivate func decide(_ url: URL, isMainFrame: Bool, opensWindow: Bool) -> WKNavigationActionPolicy {
        switch policy.decision(for: url, isMainFrame: isMainFrame) {
        case .allow:
            // No other windows: a link to a new one opens here.
            guard opensWindow else { return .allow }
            load(url)
            return .cancel
        case .openInBrowser where !agentHasControl:
            Logger.preview.info("External navigation sent to the browser")
            openInBrowser(url)
            return .cancel
        case .openInBrowser, .cancel:
            // What the agent set off fails its tool and never reaches the browser.
            if agentHasControl { cancelledNavigation = url }
            Logger.preview.notice("Navigation outside the Sessione's servers cancelled")
            return .cancel
        }
    }

    fileprivate func log(_ line: ConsoleLine) {
        console.append(line)
        if console.count > Self.consoleLimit { console.removeFirst(console.count - Self.consoleLimit) }
    }

    fileprivate func record(request: String) {
        requests.append(request)
        if requests.count > Self.consoleLimit { requests.removeFirst(requests.count - Self.consoleLimit) }
    }

    /// Follows the page's navigations: a certificate that is not trusted shows the page "Apri nel browser".
    private func watchNavigations() async {
        while !Task.isCancelled {
            do {
                for try await event in page.navigations where event == .committed {
                    untrustedURL = nil
                }
                return
            } catch WebPage.NavigationError.pageClosed {
                return
            } catch WebPage.NavigationError.failedProvisionalNavigation(let error) {
                let error = error as NSError
                guard error.domain == NSURLErrorDomain,
                      (NSURLErrorClientCertificateRequired...NSURLErrorSecureConnectionFailed).contains(error.code)
                else { continue }
                Logger.preview.notice("Untrusted certificate: page not opened (\(error.code, privacy: .public))")
                untrustedURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? page.url
            } catch {
                continue
            }
        }
    }

    /// Wraps `console.*`, `fetch` and `XMLHttpRequest`, and reports to Bubo uncaught errors and rejections, as text
    /// only, and the user's clicks and keys: the agent's synthetic events are not trusted, so they never count.
    private static let consoleScript = """
        (() => {
          const handler = window.webkit?.messageHandlers?.\(consoleHandlerName);
          if (!handler) return;
          const send = (body) => { try { handler.postMessage(body); } catch {} };
          for (const type of ["pointerdown", "keydown"]) {
            addEventListener(type, (event) => { if (event.isTrusted) send({ kind: "input" }); }, true);
          }
          const request = (method, url, status, started) => send({ kind: "request",
            text: `${method} ${url} ${status} ${Math.round(performance.now() - started)} ms`.slice(0, 2000) });
          const originalFetch = window.fetch;
          if (originalFetch) {
            window.fetch = function (input, init) {
              const started = performance.now();
              const method = String(init?.method ?? input?.method ?? "GET").toUpperCase();
              const url = String(input?.url ?? input);
              return originalFetch.apply(this, arguments).then(
                (response) => { request(method, url, response.status, started); return response; },
                (error) => { request(method, url, "failed", started); throw error; });
            };
          }
          const opened = new WeakMap();
          const open = XMLHttpRequest.prototype.open, sendRequest = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function (method, url) {
            opened.set(this, [String(method).toUpperCase(), String(url)]);
            return open.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function () {
            const started = performance.now(), [method, url] = opened.get(this) ?? ["GET", ""];
            this.addEventListener("loadend", () => request(method, url, this.status || "failed", started));
            return sendRequest.apply(this, arguments);
          };
          const text = (value) => {
            if (typeof value === "string") return value;
            if (value instanceof Error) return value.stack || String(value);
            try { return JSON.stringify(value) ?? String(value); } catch { return String(value); }
          };
          const post = (level, values) => send({ level, text: values.map(text).join(" ").slice(0, 2000) });
          for (const level of ["log", "info", "warn", "error", "debug"]) {
            const original = console[level];
            console[level] = function (...values) { post(level, values); return original.apply(this, values); };
          }
          addEventListener("error", (event) => post("error", [event.error ?? event.message]));
          addEventListener("unhandledrejection", (event) => post("error", ["Unhandled rejection:", event.reason]));
        })();
        """
}

/// The page's policy for navigations, which asks its ``PreviewPage``.
private struct NavigationDecider: WebPage.NavigationDeciding {
    /// The Anteprima, set once it exists; weak, as the page holds the decider.
    let owner = WeakPreview()

    func decidePolicy(for action: WebPage.NavigationAction,
                      preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        guard let owner = owner.value, let url = action.request.url else { return .cancel }
        return owner.decide(url, isMainFrame: action.target?.isMainFrame ?? true, opensWindow: action.target == nil)
    }
}

/// A weak reference to an Anteprima, shared by the copies of its decider.
private final class WeakPreview {
    weak var value: PreviewPage?
}

/// Receives the page script's messages: a console line, a request or the user's input, as text, nothing else.
private final class ConsoleHandler: NSObject, WKScriptMessageHandler {
    weak var owner: PreviewPage?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let text = (body["text"] as? String).map { String($0.prefix(2_000)) }
        switch body["kind"] as? String {
        case "input":
            owner?.userDidInteract()
        case "request":
            if let text { owner?.record(request: text) }
        default:
            guard let level = body["level"] as? String, let text else { return }
            owner?.log(ConsoleLine(level: ConsoleLine.Level(level), text: text))
        }
    }
}

extension Logger {
    nonisolated static let preview = Logger(subsystem: "com.mgiuditta.bubo", category: "preview")
}
