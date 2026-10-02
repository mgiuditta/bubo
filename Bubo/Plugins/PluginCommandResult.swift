import Foundation

/// How a `claude plugin …` command ended: the last JSON line of `--json`, or the exit code for `prune`.
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

    /// Whether the CLI refused to run a `command` source and showed the command to confirm.
    var needsCommandConfirmation: Bool { failureCode == "command_source_refused" && shownCommand != nil }
}
