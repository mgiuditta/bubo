import AppKit
import os
import WebKit

/// The Anteprima of a Sessione: one `WebPage`, with cookies of its own, that opens only the Sessione's servers
/// (spec 15).
///
/// The page runs the Progetto's code inside Bubo, so microphone and camera are always denied and the only bridge to
/// Bubo is the console's messages. It stays alive with the panel closed; it closes when its server goes or the
/// Sessione is Fusa or Archiviata, while its cookies stay.
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

    /// How many console lines are kept.
    static let consoleLimit = 200
    /// The name the console script posts to.
    private static let consoleHandlerName = "buboConsole"

    @ObservationIgnored private let contentController: WKUserContentController
    @ObservationIgnored private let openInBrowser: (URL) -> Void
    @ObservationIgnored private var navigationWatch: Task<Void, Never>?

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

    /// Opens `url`, clearing the page "Apri nel browser" of an earlier load.
    func load(_ url: URL) {
        untrustedURL = nil
        page.load(url)
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

    /// Stops the page before it is let go: its cookies stay in the Sessione's store.
    func close() {
        navigationWatch?.cancel()
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
        case .openInBrowser:
            Logger.preview.info("External navigation sent to the browser")
            openInBrowser(url)
            return .cancel
        case .cancel:
            Logger.preview.notice("Navigation outside the Sessione's servers cancelled")
            return .cancel
        }
    }

    fileprivate func log(_ line: ConsoleLine) {
        console.append(line)
        if console.count > Self.consoleLimit { console.removeFirst(console.count - Self.consoleLimit) }
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

    /// Wraps `console.*` and reports uncaught errors and rejections to Bubo, as text only.
    private static let consoleScript = """
        (() => {
          const handler = window.webkit?.messageHandlers?.\(consoleHandlerName);
          if (!handler) return;
          const text = (value) => {
            if (typeof value === "string") return value;
            if (value instanceof Error) return value.stack || String(value);
            try { return JSON.stringify(value) ?? String(value); } catch { return String(value); }
          };
          const post = (level, values) => {
            try { handler.postMessage({ level, text: values.map(text).join(" ").slice(0, 2000) }); } catch {}
          };
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

/// Receives the console script's messages: a level and a text, nothing else.
private final class ConsoleHandler: NSObject, WKScriptMessageHandler {
    weak var owner: PreviewPage?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let level = body["level"] as? String,
              let text = body["text"] as? String
        else { return }
        owner?.log(ConsoleLine(level: ConsoleLine.Level(level), text: String(text.prefix(2_000))))
    }
}

extension Logger {
    nonisolated static let preview = Logger(subsystem: "com.mgiuditta.bubo", category: "preview")
}
