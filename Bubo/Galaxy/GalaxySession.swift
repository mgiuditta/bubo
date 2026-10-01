import Foundation

/// An Aperta Sessione of the Progetto, as its Galassia shows it: a comet with a name, a sign and its Attività.
nonisolated struct GalaxySession: Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    /// The sign that tells its comet from the others without a color: ●, ▲, ■ and so on.
    var sign: String
    var activity: Session.Activity
    /// The files it wrote, relative to the Progetto, as its revisione remembers them: they last across launches.
    var writes: Set<String>
    /// The file it wrote last, relative to the Progetto: where its comet waits before a new tool event.
    var lastWrite: String?

    /// The signs given to the Sessioni in the order they started; after the last one they start again.
    static let signs = ["●", "▲", "■", "◆", "✦", "✚"]

    /// The Aperta Sessioni of `project` among `sessions`, oldest first, each with its sign.
    static func sessions(of project: URL, in sessions: [Session]) -> [GalaxySession] {
        let project = project.standardizedFileURL
        let open = sessions.filter { $0.phase == .aperta && $0.project.standardizedFileURL == project }
        return open.enumerated().map { index, session in
            let roots = roots(of: session)
            let writes = session.edits.compactMap { GalaxyActivity.relativePath(of: $0.file, in: roots) }
            return GalaxySession(id: session.id, title: session.title, sign: signs[index % signs.count],
                                 activity: session.activity, writes: Set(writes), lastWrite: writes.last)
        }
    }

    /// Where the files of `session` are: its copy first, then the Progetto's folder, which its agent may read too.
    static func roots(of session: Session) -> [URL] {
        [session.workspace?.folder, session.project].compactMap(\.self)
    }
}
