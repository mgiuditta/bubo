import Foundation

/// How a `claude plugin …` command ended: the last JSON line of `--json`, or the exit code for `prune` and the
/// Marketplaces.
nonisolated struct PluginCommandResult: Sendable, Equatable {
    /// Whether the CLI reached the goal, also when it was already reached.
    let succeeded: Bool
    /// `failureCode`, such as `command_source_refused`, `already_in_goal_state` or `enabled_at_project_scope`.
    let failureCode: String?
    /// The CLI's message, in English, shown as it is.
    let message: String
    /// The command of a `command` source the CLI refused to run without confirmation.
    let shownCommand: PluginShownCommand?

    /// Creates a result.
    init(succeeded: Bool, failureCode: String? = nil, message: String = "", shownCommand: PluginShownCommand? = nil) {
        self.succeeded = succeeded
        self.failureCode = failureCode
        self.message = message
        self.shownCommand = shownCommand
    }

    /// Reads the last line of `output` that is a JSON object with `outcome`; `nil` when there is none.
    ///
    /// The lines before it are for people, such as the command a `command` source shows. Already being in the goal
    /// state counts as success: after it, the state is the one asked for.
    init?(output: String) {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            guard line.first == "{",
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let outcome = object["outcome"] as? String
            else { continue }
            let failureCode = object["failureCode"] as? String
            let shown = object["shownCommand"] as? [String: Any]
            self.init(succeeded: outcome == "ok" || failureCode == "already_in_goal_state",
                      failureCode: failureCode,
                      message: object["message"] as? String ?? "",
                      shownCommand: (shown?["command"] as? String).flatMap { command in
                          (shown?["sha256"] as? String).map { PluginShownCommand(command: command, sha256: $0) }
                      })
            return
        }
        return nil
    }

    /// Reads `marketplace add` or `marketplace remove`, which print text, not JSON: the exit code, checked against
    /// `listed`, the names `marketplace list --json` gives after it, when the command named its Marketplace.
    ///
    /// A failure carries the CLI's line, or `access_denied` when git found no credentials for the repository.
    init(marketplaceOutput output: ProcessOutput, removing name: String? = nil, listed: [String]?) {
        let text = output.standardOutput + "\n" + output.standardError
        guard output.exitCode == 0 else {
            let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            // "Adding marketplace…✘ Failed to add marketplace: …": the words after the mark.
            let message = lines.first { $0.contains("✘") }.map { $0.drop { $0 != "✘" }.dropFirst().trimmingCharacters(in: .whitespaces) }
            let lowered = text.lowercased()
            let isDenied = Self.accessDenied.contains { lowered.contains($0) }
            self.init(succeeded: false, failureCode: isDenied ? "access_denied" : nil, message: message ?? lines.last ?? "")
            return
        }
        let succeeded = switch (name, Self.addedName(in: text), listed) {
        case let (name?, _, listed?): !listed.contains(name)
        case let (nil, added?, listed?): listed.contains(added)
        default: true
        }
        self.init(succeeded: succeeded, failureCode: succeeded ? nil : "not_listed")
    }

    /// What git prints when a repository needs credentials it does not have: SSH keys, a prompt it may not show.
    private static let accessDenied = ["permission denied (publickey)", "ssh authentication failed", "authentication failed",
                                       "unable to get password", "could not read username", "could not read password",
                                       "terminal prompts disabled", "repository not found"]

    /// The name in "Successfully added marketplace: NAME (…)" or "Marketplace 'NAME' already on disk".
    private static func addedName(in text: String) -> String? {
        if let match = text.firstMatch(of: /added marketplace: (\S+)/) { return String(match.1) }
        if let match = text.firstMatch(of: /Marketplace '([^']+)' already on disk/) { return String(match.1) }
        return nil
    }

    /// Reads `configure --values-stdin --json`, which prints one JSON object over many lines: `saved` when it saved,
    /// `refused` with the CLI's message when an option is unknown or a value does not fit; `nil` without the object.
    init?(configureOutput output: String) {
        guard let start = output.firstIndex(of: "{"),
              let object = try? JSONSerialization.jsonObject(with: Data(output[start...].utf8)) as? [String: Any]
        else { return nil }
        if object["saved"] != nil {
            self.init(succeeded: true)
        } else if let refused = object["refused"] as? [String: Any] {
            self.init(succeeded: false, failureCode: "refused", message: refused["message"] as? String ?? "")
        } else {
            return nil
        }
    }

    /// Whether git had no credentials for the Marketplace's repository.
    var isAccessDenied: Bool { failureCode == "access_denied" }

    /// Whether the CLI refused to run a `command` source and showed the command to confirm.
    var needsCommandConfirmation: Bool { failureCode == "command_source_refused" && shownCommand != nil }
}
