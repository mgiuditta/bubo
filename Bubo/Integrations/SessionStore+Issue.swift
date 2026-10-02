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

    /// Adds `draft` to Da iniziare, unless its issue already has a Bozza or an open Sessione on its Progetto: no
    /// doppioni. An issue whose Sessione is Archiviata or Fusa gets the Bozza, and Avvia starts a new Sessione.
    ///
    /// - Returns: Whether the Bozza was added.
    @discardableResult
    func addDraft(_ draft: Draft) -> Bool {
        if let issue = draft.issue {
            switch issue.match(in: sessions, drafts: drafts.drafts, on: draft.project) {
            case .draft, .open: return false
            case .none, .closed: break
            }
        }
        drafts.add(draft)
        return true
    }

    /// A `bubo://` link: a Bozza, never a Sessione, and only on a folder that exists. Avvia stays the user's gesture.
    ///
    /// - Returns: Whether a Bozza was added.
    @discardableResult
    func receive(_ link: DraftLink) -> Bool {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: link.project.path, isDirectory: &isFolder), isFolder.boolValue
        else { return false }
        return addDraft(Draft(title: link.title, text: link.text, project: link.project, issue: link.issue))
    }

    /// Avvia of `draft`: a Bozza from an issue reads it now with `gh issue view`, then starts like ↩ in ⌘I and is
    /// removed; any other starts as usual. Nothing when the Bozza was deleted while the issue was read.
    ///
    /// - Throws: `GitHubCLIError` when the issue cannot be read: the Bozza stays.
    func start(_ draft: Draft, readingWith cli: GitHubCLI) async throws {
        guard let number = draft.issue?.number else { return start(draft) }
        guard draft.unreachableReason == nil else { return }
        let repository = try await cli.repository(of: draft.project)
        let context = try await cli.context(ofIssue: number, in: repository)
        guard drafts.drafts.contains(where: { $0.id == draft.id }) else { return }
        do {
            try start(context.prompt(number: number), title: context.title,
                      branch: IssueLink.branch(forIssue: number, titled: context.title), in: draft.project,
                      issue: .github(number))
            drafts.remove(draft.id)
        } catch {
            // Only the checkout can be taken, and a Bozza never starts there.
            Logger.sessions.error("Bozza from an issue not started: \(String(describing: error), privacy: .public)")
        }
    }
}
