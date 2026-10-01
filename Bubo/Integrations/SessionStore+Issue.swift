import Foundation
import os

extension SessionStore {
    /// ↩ in ⌘I: starts a Sessione on `project` from issue `number`, read with `gh issue view` as `context`: titled like
    /// the issue, on `bubo/42-<slug>`, with the issue in its first prompt as text written by others.
    func start(issue number: Int, _ context: GitHubIssueContext, in project: URL) {
        do {
            try start(context.prompt(number: number), title: context.title,
                      branch: IssueLink.branch(forIssue: number, titled: context.title), in: project,
                      issue: .github(number))
        } catch {
            // Only the checkout can be taken, and a Sessione from an issue never starts there.
            Logger.sessions.error("Sessione from an issue not started: \(String(describing: error), privacy: .public)")
        }
    }
}
