import Foundation
import Synchronization
@testable import Bubo

/// A stand-in OpenAI-compatible server, in process: it answers each address with a fixed reply and keeps every request
/// it receives, body included, so a test can tell exactly what left the Mac. No real provider is ever called.
nonisolated final class FakeChatServer: URLProtocol {
    /// A reply: an HTTP status and the body, such as a server-sent stream.
    struct Reply: Sendable {
        var status = 200
        var body: String
        /// Fails as with no network instead of replying.
        var isOffline = false
        var headers: [String: String] = [:]
    }

    /// A request as the server received it.
    struct Received: Sendable {
        let url: URL
        let headers: [String: String]
        let body: Data
    }

    private static let replies = Mutex<[String: Reply]>([:])
    private static let received = Mutex<[String: [Received]]>([:])
    private static let pathReplies = Mutex<[String: Reply]>([:])

    /// A session whose requests all reach this server.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeChatServer.self]
        return URLSession(configuration: configuration)
    }()

    /// Serves `reply` at a fresh address and returns it; on the Mac with `onMac`, in a cloud otherwise.
    static func serve(_ reply: Reply, onMac: Bool = false) -> URL {
        let url = onMac ? URL(string: "http://localhost:\(Int.random(in: 20_000...60_000))/v1")!
                        : URL(string: "https://fake-\(UUID().uuidString.lowercased()).test/v1")!
        replies.withLock { $0[key(url)] = reply }
        return url
    }

    /// Serves `reply` at `path` of the address `url` was served at, such as `/api/tags`, instead of its usual reply.
    static func serve(_ reply: Reply, at path: String, of url: URL) {
        pathReplies.withLock { $0[key(url) + path] = reply }
    }

    /// The requests received at the address `url` was served at.
    static func requests(at url: URL) -> [Received] {
        received.withLock { $0[key(url)] ?? [] }
    }

    /// A server-sent stream that says `pieces` one by one, then counts the tokens and ends.
    static func stream(_ pieces: [String], input: Int = 7, output: Int = 3) -> String {
        let chunks = pieces.map { piece in
            let data = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": piece]]]])
            return "data: \(String(decoding: data, as: UTF8.self))\n\n"
        }
        return chunks.joined()
            + "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":\(input),\"completion_tokens\":\(output)}}\n\n"
            + "data: [DONE]\n\n"
    }

    private static func key(_ url: URL) -> String {
        "\(url.host() ?? ""):\(url.port ?? 0)"
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let key = Self.key(url)
        Self.received.withLock {
            $0[key, default: []].append(Received(url: url, headers: request.allHTTPHeaderFields ?? [:],
                                                 body: Self.body(of: request)))
        }
        let reply = Self.pathReplies.withLock { $0[key + url.path()] } ?? Self.replies.withLock { $0[key] }
            ?? Reply(status: 404, body: "")
        if reply.isOffline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                                              headerFields: reply.headers.merging(["Content-Type": "text/event-stream"]) { kept, _ in kept })!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// The body as sent: a URL protocol gets it as a stream, not as `httpBody`.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
