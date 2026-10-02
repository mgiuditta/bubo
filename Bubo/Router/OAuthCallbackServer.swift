import Foundation
import Network

/// The page OpenRouter sends the browser back to after the user authorizes Bubo: `http://localhost:<port>/callback`
/// on a free port, reachable only from this Mac.
nonisolated final class OAuthCallbackServer: Sendable {
    /// Why no code arrived.
    enum Failure: Error, Equatable {
        /// The 10 minutes an OpenRouter code lasts went by without the browser coming back.
        case timedOut
        /// The callback could not open a port on this Mac.
        case unavailable
    }

    /// Where the browser comes back.
    let url: URL
    private let listener: NWListener
    private let codes: AsyncStream<String>

    private init(listener: NWListener, port: UInt16, codes: AsyncStream<String>) {
        self.listener = listener
        self.url = URL(string: "http://localhost:\(port)/callback")!
        self.codes = codes
    }

    /// Opens the callback on a free port of the loopback interface.
    @concurrent
    static func start() async throws -> OAuthCallbackServer {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        guard let listener = try? NWListener(using: parameters, on: .any) else { throw Failure.unavailable }
        let queue = DispatchQueue(label: "com.mgiuditta.bubo.oauth-callback")
        let (codes, continuation) = AsyncStream.makeStream(of: String.self)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { data, _, _, _ in
                let code = data.flatMap { Self.code(inRequest: String(decoding: $0, as: UTF8.self)) }
                Self.reply(to: connection, found: code != nil)
                if let code { continuation.yield(code) }
            }
        }
        let (states, stateContinuation) = AsyncStream.makeStream(of: NWListener.State.self)
        listener.stateUpdateHandler = { stateContinuation.yield($0) }
        listener.start(queue: queue)
        var port: UInt16?
        for await state in states {
            switch state {
            case .ready: port = listener.port?.rawValue
            case .failed, .cancelled: port = nil
            default: continue
            }
            break
        }
        listener.stateUpdateHandler = nil
        if let port { return OAuthCallbackServer(listener: listener, port: port, codes: codes) }
        listener.cancel()
        throw Failure.unavailable
    }

    /// The first code the browser brings back, within `timeout`.
    func code(timeout: Duration = .seconds(600)) async throws -> String {
        let codes = codes
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                for await code in codes { return code }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            guard let code = try await group.next() ?? nil else { throw CancellationError() }
            return code
        }
    }

    /// Closes the port.
    func stop() {
        listener.cancel()
    }

    /// The `code` of a `GET /callback?code=…` request, from its first line; `nil` for any other request, such as the
    /// browser asking for a favicon.
    static func code(inRequest request: String) -> String? {
        let parts = request.prefix { $0 != "\r" && $0 != "\n" }.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: String(parts[1])), components.path == "/callback"
        else { return nil }
        return components.queryItems?.first { $0.name == "code" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func reply(to connection: NWConnection, found: Bool) {
        let page = String(localized: "Bubo è collegato a OpenRouter. Puoi chiudere questa pagina e tornare a Bubo.")
        let body = found ? Data("<!doctype html><meta charset=\"utf-8\"><title>Bubo</title><p>\(page)</p>".utf8) : Data()
        let head = "HTTP/1.1 \(found ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
