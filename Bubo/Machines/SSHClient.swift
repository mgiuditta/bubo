import Foundation

/// Runs the system's `ssh`, with Bubo's askpass helper answering OpenSSH's questions.
///
/// Injected so tests replace OpenSSH with a fake that records the arguments: no test connects to a host.
nonisolated struct SSHClient: Sendable {
    /// What an `ssh` run left behind.
    struct Run: Sendable {
        var output: ProcessOutput
        /// Whether the user refused one of OpenSSH's questions.
        var refusedQuestion = false
    }

    /// Runs `ssh` with `arguments`, passing each question of OpenSSH to `ask`; a `nil` answer refuses.
    var run: @Sendable (_ arguments: [String], _ ask: @escaping @Sendable (AskpassQuestion) async -> String?)
        async throws -> Run

    /// The system's OpenSSH, with a private askpass folder for each run.
    static let live = SSHClient { arguments, ask in
        let askpass = try Askpass.make()
        defer { askpass.remove() }
        let environment = SSHCommand.environment(askpass: askpass, from: ProcessInfo.processInfo.environment)
        let runner = ProcessRunner.live(environment: environment)
        return try await withThrowingTaskGroup(of: Part.self) { group in
            group.addTask { .output(try await runner.run(SSHCommand.executable, arguments)) }
            group.addTask { .refused(await relayQuestions(of: askpass, to: ask)) }
            var run = Run(output: ProcessOutput(exitCode: -1, standardOutput: ""))
            for try await part in group {
                switch part {
                case .output(let output):
                    run.output = output
                    group.cancelAll() // stops the relay
                case .refused(let refused):
                    run.refusedQuestion = refused
                }
            }
            return run
        }
    }

    private enum Part: Sendable {
        case output(ProcessOutput)
        case refused(Bool)
    }
}

/// Hands each question of the helper to `ask` and its answer back, until cancelled; whether one was refused.
private nonisolated func relayQuestions(of askpass: Askpass,
                                        to ask: @escaping @Sendable (AskpassQuestion) async -> String?) async -> Bool {
    var refused = false
    while !Task.isCancelled {
        for question in askpass.takeQuestions() {
            let answer = await ask(AskpassQuestion(question.text))
            if answer == nil { refused = true }
            await askpass.answer(question.id, with: answer)
        }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return refused
}
