import Foundation
import os

/// The Bozze of every Progetto, kept in a JSON file next to the Sessioni's.
@Observable
final class DraftStore {
    /// The Bozze, oldest first.
    private(set) var drafts: [Draft] = []

    @ObservationIgnored private let file: URL?

    /// Creates a store kept in `file`; `nil` keeps the Bozze only in memory.
    init(file: URL? = nil) {
        self.file = file
        guard let file else { return }
        do {
            drafts = try JSONDecoder().decode([Draft].self, from: Data(contentsOf: file))
        } catch CocoaError.fileReadNoSuchFile {
        } catch {
            Logger.sessions.error("Bozze unreadable: \(error)")
        }
    }

    /// Adds `draft`, at the end.
    func add(_ draft: Draft) {
        drafts.append(draft)
        save()
    }

    /// Removes the Bozza `id`, if it is still there.
    func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(drafts).write(to: file, options: .atomic)
        } catch {
            Logger.sessions.error("Bozze not saved: \(error)")
        }
    }
}

extension SessionStore {
    /// Avvia: starts `draft` as a Sessione in Aperta · Lavora, in a worktree on its branch or `bubo/<slug>` of its
    /// title, with its issue, and removes it. Nothing when its Progetto is not reachable: the Bozza stays.
    ///
    /// The trust dialog, when the Progetto is not trusted, comes before: like for ⌘N, it is the view's.
    func start(_ draft: Draft) {
        guard draft.unreachableReason == nil else { return }
        do {
            try start(draft.prompt, title: draft.title, branch: draft.branch ?? Session.proposedBranch(for: draft.title),
                      in: draft.project, issue: draft.issue)
            drafts.remove(draft.id)
        } catch {
            // Only the checkout can be taken, and a Bozza never starts there.
            Logger.sessions.error("Bozza not started: \(String(describing: error), privacy: .public)")
        }
    }
}
