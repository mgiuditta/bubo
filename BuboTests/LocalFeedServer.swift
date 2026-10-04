import Foundation
import Network

/// An HTTP server on 127.0.0.1, at a port the system picks, that answers every request with the same body: Sparkle
/// downloads only over http or https, never `file://`.
nonisolated final class LocalFeedServer: Sendable {
    /// The address of the body.
    let url: URL
    private let listener: NWListener

    /// Starts serving `body` at a fresh `appcast.xml` address.
    init(body: Data) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "LocalFeedServer")
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.answer(connection, with: body)
        }
        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, any Error>) in
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    listener?.stateUpdateHandler = nil
                    continuation.resume(returning: listener?.port?.rawValue ?? 0)
                case .failed(let error):
                    listener?.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
        // A fresh path: a later server may get the same port, and nothing cached from this one must answer for it.
        url = URL(string: "http://127.0.0.1:\(port)/\(UUID().uuidString)/appcast.xml")!
    }

    /// Stops listening.
    func stop() {
        listener.cancel()
    }

    /// Reads the request head, answers with `body` and closes.
    private static func answer(_ connection: NWConnection, with body: Data, received: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            let request = received + (data ?? Data())
            guard request.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if isComplete || error != nil { connection.cancel() } else { answer(connection, with: body, received: request) }
                return
            }
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/xml\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
