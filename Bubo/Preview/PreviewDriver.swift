import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit

/// The Swift side of the Anteprima's tools (spec 15): drives the Sessione's own ``PreviewPage``, the one the user
/// sees, with the user's cookies.
///
/// The agent goes only where the user could: the page's ``PreviewPolicy`` decides, and an external page never reaches
/// the system browser. Every action ends within ``timeout``, and a click or a key of the user in the page makes it fail
/// at once.
struct PreviewDriver {
    let preview: PreviewPage
    /// How long an action may take, loading included.
    var timeout: Duration = .seconds(10)

    /// The longest side of a screenshot, in pixels: a ceiling chosen for cost and speed.
    static let screenshotLongSide = 1568
    /// How many console lines and requests the agent gets at most.
    static let lineLimit = 200
    /// How much HTML the agent gets at most, in characters.
    static let htmlLimit = 50_000
    static let tookControl = "L'utente ha preso il controllo dell'Anteprima: azione interrotta."

    /// The world the agent's scripts and Bubo's own run in: they see the DOM, not the page's variables.
    private static let world = WKContentWorld.world(name: "bubo")

    private var page: WebPage { preview.page }

    /// Does `action` and returns what the agent gets: a failure when it takes longer than ``timeout`` or when the user
    /// takes control.
    func perform(_ action: PreviewAction) async -> PreviewReply {
        let takeover = preview.agentWillAct()
        defer { preview.agentDidAct() }
        // A race, not a task group: WebKit's calls do not stop when cancelled, and the reply cannot wait for them.
        return await withCheckedContinuation { continuation in
            let race = Race(continuation)
            race.tasks = [
                Task { race.finish(with: await run(action)) },
                Task { [timeout] in
                    try? await Task.sleep(for: timeout)
                    race.finish(with: .failure("L'azione nell'Anteprima non è finita entro 10 s."))
                },
                Task {
                    for await _ in takeover {
                        race.finish(with: .failure(Self.tookControl))
                    }
                },
            ]
        }
    }

    private func run(_ action: PreviewAction) async -> PreviewReply {
        // A page the agent's first tool just opened, or one still loading: the action works on the loaded page.
        await waitWhileLoading()
        do {
            switch action {
            case .screenshot:
                return .image(try Self.jpeg(from: await page.exported(as: .image()), longSide: Self.screenshotLongSide))
            case let .dom(selector):
                let html = try await page.callJavaScript("""
                    const element = selector ? document.querySelector(selector) : document.documentElement;
                    return element ? element.outerHTML : null;
                    """, arguments: ["selector": selector ?? ""], contentWorld: Self.world) as? String
                guard let html else { return .failure("Nessun elemento corrisponde a \(selector ?? "").") }
                return .text(html.count > Self.htmlLimit ? String(html.prefix(Self.htmlLimit)) + "\n[troncato]" : html)
            case let .console(filter):
                let lines = preview.console.map { "[\($0.level)] \($0.text)" }
                return .text(Self.lastLines(lines, containing: filter, otherwise: "Nessuna riga nella console."))
            case let .network(filter):
                // Resources from the timeline; `fetch` and XHR from the page script, which also sees their status.
                let resources = try await page.callJavaScript("""
                    return performance.getEntriesByType("resource")
                      .filter((entry) => entry.initiatorType !== "fetch" && entry.initiatorType !== "xmlhttprequest")
                      .map((entry) => `${entry.initiatorType} ${entry.name} ${entry.responseStatus ?? ""} ${Math.round(entry.duration)} ms`);
                    """, contentWorld: Self.world) as? [String] ?? []
                return .text(Self.lastLines(resources + preview.requests, containing: filter,
                                            otherwise: "Nessuna richiesta di rete."))
            case let .navigate(address):
                guard let url = URL(string: address, relativeTo: page.url ?? preview.policy.startURL)?.absoluteURL else {
                    return .failure("Indirizzo non valido: \(address).")
                }
                guard preview.policy.decision(for: url, isMainFrame: true) == .allow else { return outside(url) }
                for try await event in preview.load(url) where event == .finished { break }
                return loaded("Aperta")
            case let .click(selector):
                guard try await callInPage("""
                    const element = document.querySelector(selector);
                    if (!element) return false;
                    element.scrollIntoView({ block: "center" });
                    element.click();
                    return true;
                    """, ["selector": selector]) as? Bool == true
                else { return .failure("Nessun elemento corrisponde a \(selector).") }
                await settle()
                return loaded("Cliccato \(selector)")
            case let .fill(selector, text):
                guard try await callInPage("""
                    const element = document.querySelector(selector);
                    if (!element) return false;
                    element.focus();
                    if (element.isContentEditable) {
                      element.textContent = text;
                    } else {
                      // The prototype's setter, so that frameworks tracking the value see the change.
                      const prototype = Object.getPrototypeOf(element);
                      const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
                      if (setter) setter.call(element, text); else element.value = text;
                    }
                    element.dispatchEvent(new Event("input", { bubbles: true }));
                    element.dispatchEvent(new Event("change", { bubbles: true }));
                    return true;
                    """, ["selector": selector, "text": text]) as? Bool == true
                else { return .failure("Nessun campo corrisponde a \(selector).") }
                return .text("Compilato \(selector).")
            case let .scroll(selector, offset):
                let position = try await callInPage("""
                    if (selector) {
                      const element = document.querySelector(selector);
                      if (!element) return null;
                      element.scrollIntoView({ block: "center" });
                    } else {
                      scrollBy(0, offset || innerHeight * 0.8);
                    }
                    return Math.round(scrollY);
                    """, ["selector": selector ?? "", "offset": offset ?? 0]) as? Int
                guard let position else { return .failure("Nessun elemento corrisponde a \(selector ?? "").") }
                return .text("Pagina a \(position) px dall'alto.")
            case let .runJavaScript(code):
                let value = try await callInPage(code)
                await settle()
                if let url = preview.cancelledNavigation { return outside(url) }
                return .text(Self.json(value))
            }
        } catch {
            if let url = preview.cancelledNavigation { return outside(url) }
            return .failure("L'Anteprima non ha potuto: \(error.localizedDescription)")
        }
    }

    private func callInPage(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await page.callJavaScript(body, arguments: arguments, contentWorld: Self.world)
    }

    /// Waits for the load an action may have started: a navigation starts within a moment, or not at all.
    private func settle() async {
        let clock = ContinuousClock()
        let start = clock.now
        while !page.isLoading, clock.now - start < .milliseconds(100), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await waitWhileLoading()
    }

    private func waitWhileLoading() async {
        while page.isLoading, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// The reply after an action that may have loaded a page: where the page is, or the navigation cancelled.
    private func loaded(_ done: String) -> PreviewReply {
        if let url = preview.cancelledNavigation { return outside(url) }
        return .text("\(done). Pagina: \(page.url?.absoluteString ?? "nessuna").")
    }

    private func outside(_ url: URL) -> PreviewReply {
        .failure("\(url.absoluteString) non è un server della Sessione: l'Anteprima apre solo i suoi server localhost.")
    }

    /// The last ``lineLimit`` of `lines` containing `filter`, one per line; `otherwise` when none.
    static func lastLines(_ lines: [String], containing filter: String?, otherwise: String) -> String {
        let matching = lines.filter { filter.map($0.localizedCaseInsensitiveContains) ?? true }
        return matching.isEmpty ? otherwise : matching.suffix(lineLimit).joined(separator: "\n")
    }

    /// `value`, returned by a script, as JSON; `undefined` for nothing.
    static func json(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "undefined" }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return String(describing: value) }
        return text
    }

    /// `image` as a JPEG no longer than `longSide` pixels on either side; smaller images keep their size.
    static func jpeg(from image: Data, longSide: Int) throws -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        let output = NSMutableData()
        guard let source = CGImageSourceCreateWithData(image as CFData, nil),
              let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw PreviewDriverError.unreadableImage }
        CGImageDestinationAddImage(destination, picture, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PreviewDriverError.unreadableImage }
        return output as Data
    }
}

/// Why a screenshot could not be made.
nonisolated enum PreviewDriverError: LocalizedError {
    case unreadableImage

    var errorDescription: String? { "immagine della pagina non leggibile" }
}

/// The first of an action's tasks to finish gives the reply; the others are cancelled.
private final class Race {
    private var continuation: CheckedContinuation<PreviewReply, Never>?
    var tasks: [Task<Void, Never>] = []

    init(_ continuation: CheckedContinuation<PreviewReply, Never>) {
        self.continuation = continuation
    }

    func finish(with reply: PreviewReply) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: reply)
        tasks.forEach { $0.cancel() }
    }
}
