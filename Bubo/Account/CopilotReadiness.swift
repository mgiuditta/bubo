import Foundation

/// Whether the user's `copilot` can answer, asked to `copilot` itself (ADR 0011, ADR 0012).
///
/// `copilot` has no `auth status` command: Bubo starts it as the Copilot SDK does (`--headless --stdio`) and sends three
/// JSON-RPC requests that carry no credential: `status.get`, `auth.getStatus` and `account.getQuota`. It never sends
/// the ones that return a token (`account.getCurrentAuth`, `account.getAllUsers`), and never reads the Keychain or
/// `~/.copilot`. The login stays the one the user made with `copilot login`.
nonisolated enum CopilotReadiness: Equatable, Sendable {
    /// No `copilot`, or one that does not answer: the guide is `brew install copilot-cli`.
    case missing
    /// `copilot` has no login: the guide is `copilot login` in Terminal.
    case signedOut(version: String)
    /// Signed in on Copilot Free, which offers only the automatic model choice: not supported (ADR 0011).
    case free(version: String, account: String?)
    /// Signed in on a paid plan; `account` is the GitHub login, when `copilot` says it.
    case ready(version: String, account: String?)

    /// The arguments that start `copilot` as a JSON-RPC server on its standard input and output, without updating
    /// itself.
    static let serverArguments = ["--headless", "--no-auto-update", "--stdio"]

    /// The methods asked, in order; none of them returns a credential.
    static let methods = ["status.get", "auth.getStatus", "account.getQuota"]

    /// The requests written to `copilot`'s standard input, which is then closed: `copilot` answers them all and exits.
    static let requests: Data = methods.enumerated().reduce(into: Data()) { data, request in
        data.append(RPCFrames.frame(#"{"jsonrpc":"2.0","id":\#(request.offset + 1),"method":"\#(request.element)","params":{}}"#))
    }

    /// The `copilot` that runs by default: disclaimed, without GitHub tokens in its environment, given ``requests``.
    static let defaultRunner = ProcessRunner { copilot, arguments in
        try await ProcessRunner.disclaimed(environment: ChildEnvironment.makeForCopilot(copilot: copilot),
                                           input: requests).run(copilot, arguments)
    }

    /// Finds `copilot` with `locator` and asks it for its version, login and plan.
    ///
    /// - Parameters:
    ///   - runner: Runs `copilot` with ``serverArguments``; its standard input gets ``requests``.
    ///   - timeout: How long `copilot` may take: the plan comes from GitHub.
    static func detect(locator: CopilotLocator = CopilotLocator(), runner: ProcessRunner = defaultRunner,
                       timeout: Duration = .seconds(15)) async -> CopilotReadiness {
        guard let copilot = await locator.executableURL(),
              let output = await runner.run(copilot, serverArguments, timeout: timeout)
        else { return .missing }
        let answers = RPCFrames.answers(in: Data(output.standardOutput.utf8))
        let decoder = JSONDecoder()
        guard let status = answers[1].flatMap({ try? decoder.decode(Status.self, from: $0) }) else { return .missing }
        guard let auth = answers[2].flatMap({ try? decoder.decode(AuthStatus.self, from: $0) }), auth.isAuthenticated
        else { return .signedOut(version: status.version) }
        let quota = answers[3].flatMap { try? decoder.decode(Quota.self, from: $0) }
        return quota?.isFree == true
            ? .free(version: status.version, account: auth.login)
            : .ready(version: status.version, account: auth.login)
    }

    /// The answer to `status.get`.
    private struct Status: Decodable {
        let version: String
    }

    /// The answer to `auth.getStatus`.
    private struct AuthStatus: Decodable {
        let isAuthenticated: Bool
        let login: String?
    }

    /// The answer to `account.getQuota`.
    private struct Quota: Decodable {
        struct Snapshot: Decodable {
            let isUnlimitedEntitlement: Bool
        }

        let quotaSnapshots: [String: Snapshot]

        /// Whether the plan is Copilot Free: the only one whose chat or completions are limited; the paid plans limit
        /// only the premium requests. An unknown quota counts as paid, and the first request tells.
        var isFree: Bool {
            ["chat", "completions"].contains { quotaSnapshots[$0]?.isUnlimitedEntitlement == false }
        }
    }
}

/// The `Content-Length` framing of JSON-RPC over standard input and output, as the Copilot SDK speaks it.
nonisolated enum RPCFrames {
    /// `json` with its header.
    static func frame(_ json: String) -> Data {
        let body = Data(json.utf8)
        return Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
    }

    /// The `result` of every answer in `stream`, by request id; answers with an error, and notifications, are left out.
    static func answers(in stream: Data) -> [Int: Data] {
        var answers: [Int: Data] = [:]
        var rest = stream[...]
        let separator = Data("\r\n\r\n".utf8)
        while let end = rest.firstRange(of: separator) {
            let header = String(decoding: rest[..<end.lowerBound], as: UTF8.self)
            guard let length = header.split(whereSeparator: \.isNewline)
                .first(where: { $0.lowercased().hasPrefix("content-length:") })
                .flatMap({ Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }),
                  rest.distance(from: end.upperBound, to: rest.endIndex) >= length
            else { break }
            let body = rest[end.upperBound..<rest.index(end.upperBound, offsetBy: length)]
            if let object = try? JSONSerialization.jsonObject(with: Data(body)) as? [String: Any],
               let id = object["id"] as? Int, let result = object["result"],
               let data = try? JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed) {
                answers[id] = data
            }
            rest = rest[body.endIndex...]
        }
        return answers
    }
}
