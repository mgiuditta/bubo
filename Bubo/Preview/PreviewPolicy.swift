import Foundation

/// Where the Anteprima of a Sessione may go (spec 15): its `localhost` servers, and the `url` of its
/// `.claude/launch.json` when that is local too. Every other navigation is cancelled; an external page the user asked
/// for opens in the system browser.
nonisolated struct PreviewPolicy: Equatable, Sendable {
    /// What happens to a navigation.
    enum Decision: Equatable, Sendable {
        case allow
        case cancel
        /// Cancelled in the Anteprima, opened in the system browser instead.
        case openInBrowser
    }

    /// The ports the Sessione's servers listen on.
    var ports: Set<Int>
    /// The local addresses of `launch.json`, as `localhost` URLs.
    var launchURLs: [URL]

    /// The policy for the servers on `ports` and the servers of `launchConfigs`.
    init(ports: some Sequence<Int>, launchConfigs: [LaunchConfig] = []) {
        self.ports = Set(ports)
        launchURLs = launchConfigs.compactMap { $0.url.flatMap(URL.init(string:)).flatMap(Self.localURL(for:)) }
    }

    /// Where the Anteprima opens first: the address of `launch.json` for a server that listens, else the first server.
    var startURL: URL? {
        if let url = launchURLs.first(where: { $0.port.map(ports.contains) == true }) { return url }
        return ports.min().flatMap { URL(string: "http://localhost:\($0)/") }
    }

    /// What to do with a navigation to `url`, in the page itself when `isMainFrame`, else in one of its frames.
    func decision(for url: URL, isMainFrame: Bool) -> Decision {
        if url.scheme == "about" { return .allow }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false)?.lowercased()
        else { return .cancel }
        if Self.isLocalhost(host) {
            if ports.contains(url.port ?? (scheme == "https" ? 443 : 80)) { return .allow }
            return launchURLs.contains { Self.sameOrigin($0, url) } ? .allow : .cancel
        }
        // `127.0.0.1` and the other addresses of this Mac may be another Sessione's servers: never opened.
        if Self.isLoopbackAddress(host) { return .cancel }
        // An external frame, an embedded video or an advert, stays out without opening the browser.
        return isMainFrame ? .openInBrowser : .cancel
    }

    /// `url` with `localhost` in place of a loopback address; `nil` when it is not a local address.
    static func localURL(for url: URL) -> URL? {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        if isLocalhost(host) { return url }
        guard isLoopbackAddress(host), var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.host = "localhost"
        return components.url
    }

    /// Whether `host` is `localhost` or one of its subdomains, as `app.localhost`.
    private static func isLocalhost(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".localhost")
    }

    /// Whether `host` is a loopback or unspecified address, IPv4 or IPv6.
    private static func isLoopbackAddress(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return bare.hasPrefix("127.") || bare == "0.0.0.0" || bare == "::1" || bare == "::"
    }

    private static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        first.scheme?.lowercased() == second.scheme?.lowercased()
            && first.host(percentEncoded: false)?.lowercased() == second.host(percentEncoded: false)?.lowercased()
            && first.port == second.port
    }
}
