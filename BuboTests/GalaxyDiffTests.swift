import Foundation
import Testing
@testable import Bubo

/// The diff in glass of the Galassia (spec 11): the same blocchi as the revisione, `+n −m` in the list, collisions,
/// Progetti without git.
@MainActor
struct GalaxyDiffTests {
    let alpha = GalaxySession(id: UUID(), title: "Login", sign: "●", activity: .lavora,
                              writes: ["Sources/App/main.swift"], lastWrite: "Sources/App/main.swift",
                              isReviewable: true)
    let beta = GalaxySession(id: UUID(), title: "Rete", sign: "▲", activity: .attende,
                             writes: ["Sources/App/main.swift"], lastWrite: "Sources/App/main.swift",
                             isReviewable: true)

    /// The diff of `main.swift`: one blocco that adds two lines and removes one.
    static let diff = """
    diff --git a/Sources/App/main.swift b/Sources/App/main.swift
    index 1111111..2222222 100644
    --- a/Sources/App/main.swift
    +++ b/Sources/App/main.swift
    @@ -1,2 +1,3 @@
     import App
    -run()
    +setUp()
    +run()
    """

    func makeModel(sessions: [GalaxySession]) -> GalaxyModel {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.reducesMotion = { true }
        model.apply(GalaxyLayout(files: GalaxyTests.files))
        model.resize(to: CGSize(width: 800, height: 600))
        model.update(sessions: sessions)
        return model
    }

    func star(_ path: String, in model: GalaxyModel) throws -> Int {
        try #require(model.layout?.stars.firstIndex { $0.path == path })
    }

    @Test func theDiffHasTheSameBlocchiAsTheRevisione() throws {
        let model = makeModel(sessions: [alpha])
        let files = ChangedFile.files(in: Self.diff)
        model.update(changes: files, of: alpha.id)
        model.select(try star("Sources/App/main.swift", in: model))
        let diff = try #require(model.diff)
        #expect(diff.session.id == alpha.id)
        #expect(diff.content == .file(files.first))
        #expect(files.first?.hunks.map(\.id) == Review(files: files).hunkIDs)
    }

    @Test func clickingAStarFliesToItAndOpensItsDiff() throws {
        let model = makeModel(sessions: [alpha])
        model.update(changes: ChangedFile.files(in: Self.diff), of: alpha.id)
        let index = try star("Sources/App/main.swift", in: model)
        let position = try #require(model.layout?.stars[index].position)
        model.fly(to: GalaxyCamera(center: position, scale: 400))
        model.click(at: model.camera.point(for: position, in: model.viewSize))
        #expect(model.selection == index)
        #expect(model.camera.center == position)
        #expect(model.diff?.path == "Sources/App/main.swift")
    }

    @Test func aFileNoSessioneChangedHasNoPanel() throws {
        let model = makeModel(sessions: [alpha])
        model.update(changes: ChangedFile.files(in: Self.diff), of: alpha.id)
        model.select(try star("README.md", in: model))
        #expect(model.diff == nil)
    }

    @Test func theDiffWaitsForGitThenSaysWhenItCannotRead() throws {
        let model = makeModel(sessions: [alpha])
        model.select(try star("Sources/App/main.swift", in: model))
        #expect(model.diff?.content == .loading)
        model.update(changes: nil, of: alpha.id)
        #expect(model.diff?.content == .unreadable)
        model.update(changes: [], of: alpha.id)
        #expect(model.diff?.content == .file(nil))
    }

    @Test func withoutGitThereIsNoVersionBeforeAndNoDiff() throws {
        var noGit = alpha
        noGit.isReviewable = false
        let model = makeModel(sessions: [noGit])
        model.select(try star("Sources/App/main.swift", in: model))
        #expect(model.diff?.content == .noVersionBefore)
    }

    @Test func onlySessioniInGitHaveARevisione() {
        let project = URL(filePath: "/p/bubo")
        var worktree = Session(id: UUID(), title: "Login", project: project)
        worktree.workspace = Workspace(folder: URL(filePath: "/w/bubo/login"), branch: "login")
        var checkout = Session(id: UUID(), title: "Checkout", project: project)
        checkout.workspace = Workspace(folder: project)
        checkout.isOnCheckout = true
        var folder = Session(id: UUID(), title: "Cartella", project: project)
        folder.workspace = Workspace(folder: project)
        let sessions = GalaxySession.sessions(of: project, in: [worktree, checkout, folder])
        #expect(sessions.map(\.isReviewable) == [true, true, false])
        #expect(sessions.first?.folder == URL(filePath: "/w/bubo/login"))
    }

    @Test func aCollisionShowsTheFilteredSessioneThenTheOnePicked() throws {
        let model = makeModel(sessions: [alpha, beta])
        model.update(changes: ChangedFile.files(in: Self.diff), of: alpha.id)
        model.update(changes: [], of: beta.id)
        model.toggleFilter(beta.id)
        model.select(try star("Sources/App/main.swift", in: model))
        #expect(model.diff?.sessions.map(\.id) == [alpha.id, beta.id])
        #expect(model.diff?.session.id == beta.id)
        model.showDiff(of: alpha.id)
        #expect(model.diff?.session.id == alpha.id)
    }

    @Test func aClosedPanelOpensAgainOnTheNextSelection() throws {
        let model = makeModel(sessions: [alpha])
        model.update(changes: ChangedFile.files(in: Self.diff), of: alpha.id)
        let main = try star("Sources/App/main.swift", in: model)
        model.select(main)
        model.closeDiff()
        #expect(model.diff == nil)
        model.select(try star("README.md", in: model))
        model.select(main)
        #expect(model.diff != nil)
    }

    @Test func theListShowsTheLinesAddedAndRemovedPerSessione() throws {
        let model = makeModel(sessions: [alpha, beta])
        let files = ChangedFile.files(in: Self.diff)
        model.update(changes: files, of: alpha.id)
        model.update(changes: files, of: beta.id)
        let main = try star("Sources/App/main.swift", in: model)
        #expect(model.lineCounts(of: main)?.added == 4)
        #expect(model.lineCounts(of: main)?.removed == 2)
        model.toggleFilter(alpha.id)
        #expect(model.lineCounts(of: main)?.added == 2)
        #expect(model.lineCounts(of: main)?.removed == 1)
        #expect(model.lineCounts(of: try star("README.md", in: model)) == nil)
    }

    @Test func aSessioneThatGoesTakesItsChangesAlong() throws {
        let model = makeModel(sessions: [alpha, beta])
        model.update(changes: ChangedFile.files(in: Self.diff), of: alpha.id)
        model.update(sessions: [beta])
        #expect(model.changes[alpha.id] == nil)
        #expect(model.lineCounts(of: try star("Sources/App/main.swift", in: model)) == nil)
    }

    @Test func theRevisioneStartsOnTheFileFromTheGalassia() {
        let review = Review(files: ChangedFile.files(in: ReviewTests.diff))
        #expect(review.firstHunk(inFileAt: "via.txt") == review.files[2].hunks.first?.id)
        #expect(review.firstHunk(inFileAt: "altro.txt") == nil)
    }
}
