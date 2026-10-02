import Foundation
import QuartzCore
import Testing
@testable import Bubo

/// The Sessioni in the Galassia (spec 11): reads and writes from the tool events, comets, collisions, chips.
@MainActor
struct GalaxyActivityTests {
    let alpha = GalaxySession(id: UUID(), title: "Login", sign: "●", activity: .lavora, writes: [], lastWrite: nil)
    let beta = GalaxySession(id: UUID(), title: "Rete", sign: "▲", activity: .attende, writes: [], lastWrite: nil)

    /// A model of ``GalaxyTests/files`` with a size, the two Sessioni and motion as asked.
    func makeModel(reducesMotion: Bool = false) -> GalaxyModel {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.reducesMotion = { reducesMotion }
        model.apply(GalaxyLayout(files: GalaxyTests.files))
        model.resize(to: CGSize(width: 800, height: 600))
        model.update(sessions: [alpha, beta])
        return model
    }

    func star(_ path: String, in model: GalaxyModel) throws -> Int {
        try #require(model.layout?.stars.firstIndex { $0.path == path })
    }

    // MARK: Activity

    @Test func pathsAreRelativeToTheCopyOrTheProgetto() {
        let roots = [URL(filePath: "/w/bubo/login"), URL(filePath: "/p/bubo")]
        #expect(GalaxyActivity.relativePath(of: "/w/bubo/login/Sources/App/main.swift", in: roots)
            == "Sources/App/main.swift")
        #expect(GalaxyActivity.relativePath(of: "/p/bubo/README.md", in: roots) == "README.md")
        #expect(GalaxyActivity.relativePath(of: "/w/bubo/login-2/a.swift", in: roots) == nil)
        #expect(GalaxyActivity.relativePath(of: "/w/bubo/login", in: roots) == nil)
        #expect(GalaxyActivity.relativePath(of: "/etc/hosts", in: roots) == nil)
    }

    @Test func readsAreCountedButOnlyTheLatestStayLit() throws {
        var activity = GalaxyActivity()
        let paths = (0..<40).map { "file\($0).swift" }
        activity.recordReads(paths, by: alpha.id)
        activity.recordReads(["file0.swift"], by: alpha.id)
        let trace = try #require(activity.traces[alpha.id])
        #expect(trace.reads.count == 40)
        #expect(trace.recentReads.count == GalaxyActivity.litReads)
        #expect(trace.recentReads.last == "file0.swift")
        #expect(trace.trail.count == GalaxyActivity.trailLength)
        #expect(trace.trail.last == "file0.swift")
        #expect(trace.writes.isEmpty)
    }

    @Test func writesAreKeptOnceInTheirOrder() throws {
        var activity = GalaxyActivity()
        activity.recordWrite("b.swift", by: alpha.id)
        activity.recordWrite("a.swift", by: alpha.id)
        activity.recordWrite("b.swift", by: alpha.id)
        let trace = try #require(activity.traces[alpha.id])
        #expect(trace.writes == ["b.swift", "a.swift"])
        #expect(trace.trail == ["a.swift", "b.swift"])
    }

    @Test func theProgettosApertaSessioniGetSignsAndTheirSavedWrites() {
        let project = URL(filePath: "/p/bubo")
        var login = Session(id: UUID(), title: "Login", project: project)
        login.workspace = Workspace(folder: URL(filePath: "/w/bubo/login"))
        login.edits = [EditNote(file: "/w/bubo/login/a.swift", why: "", lines: []),
                       EditNote(file: "/w/bubo/login/b.swift", why: "", lines: [])]
        var merged = Session(id: UUID(), title: "Fusa", project: project)
        merged.phase = .fusa
        let elsewhere = Session(id: UUID(), title: "Altrove", project: URL(filePath: "/p/altro"))
        let rete = Session(id: UUID(), title: "Rete", project: project)
        let sessions = GalaxySession.sessions(of: project, in: [login, merged, elsewhere, rete])
        #expect(sessions.map(\.title) == ["Login", "Rete"])
        #expect(sessions.map(\.sign) == ["●", "▲"])
        #expect(sessions.first?.writes == ["a.swift", "b.swift"])
        #expect(sessions.first?.lastWrite == "b.swift")
    }

    @Test func theStoreRecordsToolEventsRelativeToTheSessionesCopy() throws {
        var session = Session(id: UUID(), title: "Login", project: URL(filePath: "/p/bubo"))
        session.workspace = Workspace(folder: URL(filePath: "/w/bubo/login"))
        let store = GalaxyStore(projects: { [] }, sessions: { [session] }, viewer: { nil })
        store.record(.read(files: ["/w/bubo/login/a.swift", "/tmp/elsewhere"]), by: session.id)
        store.record(.edit(file: "/w/bubo/login/b.swift", lines: []), by: session.id)
        store.record(.read(files: ["/w/bubo/login/c.swift"]), by: UUID())
        let trace = try #require(store.activity.traces[session.id])
        #expect(trace.reads == ["a.swift"])
        #expect(trace.writes == ["b.swift"])
        #expect(store.activity.traces.count == 1)
    }

    // MARK: Map

    @Test func aToolEventLightsItsStarAtOnce() throws {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        let files = GalaxyTests.manyFiles(10_000)
        model.apply(GalaxyLayout(files: files))
        model.update(sessions: [alpha])
        var redraws = 0
        model.onRedraw = { redraws += 1 }
        var activity = GalaxyActivity()
        activity.recordWrite(files[1234], by: alpha.id)
        let start = ContinuousClock.now
        model.update(activity: activity)
        let lit = model.litStars()
        #expect(ContinuousClock.now - start < .milliseconds(100))
        let index = try #require(model.layout?.stars.firstIndex { $0.path == files[1234] })
        #expect(lit.map(\.index) == [index])
        #expect(redraws == 1)
    }

    @Test func readsAreFaintAndWritesRise() throws {
        let model = makeModel()
        var activity = GalaxyActivity()
        activity.recordReads(["README.md"], by: alpha.id)
        activity.recordWrite("docs/a.md", by: alpha.id)
        model.update(activity: activity)
        let readme = try star("README.md", in: model)
        let doc = try star("docs/a.md", in: model)
        let lit = model.litStars()
        #expect(lit.first { $0.index == readme }?.isWritten == false)
        #expect(lit.first { $0.index == doc }?.isWritten == true)
        #expect(model.lift(of: "docs/a.md") == GalaxyModel.writeLift)
        #expect(model.lift(of: "README.md") == 0)
    }

    @Test func twoSessioniOnOneFileAreACollisionBeforeAnyMerge() throws {
        let model = makeModel()
        var saved = alpha
        saved.writes = ["Sources/Core/Store.swift"]
        model.update(sessions: [saved, beta])
        var activity = GalaxyActivity()
        activity.recordWrite("Sources/Core/Store.swift", by: beta.id)
        model.update(activity: activity)
        let store = try star("Sources/Core/Store.swift", in: model)
        #expect(model.litStars().first { $0.index == store }?.isCollision == true)
        #expect(model.sessionsWriting(store).map(\.title) == ["Login", "Rete"])
    }

    @Test func writesGoWhenTheSessioneIsFusaOrArchiviata() {
        let model = makeModel()
        var activity = GalaxyActivity()
        activity.recordWrite("docs/a.md", by: alpha.id)
        model.update(activity: activity)
        model.update(sessions: [beta])
        #expect(model.litStars().isEmpty)
        #expect(model.writers.isEmpty)
    }

    @Test func aCometMovesOnlyOnANewFileAndLands() throws {
        let model = makeModel()
        var animations = 0
        model.onAnimation = { animations += 1 }
        var activity = GalaxyActivity()
        activity.recordReads(["README.md"], by: alpha.id)
        model.update(activity: activity)
        // A comet appears where its Sessione is; it does not fly in from nowhere.
        #expect(!model.isAnimating)
        activity.recordWrite("docs/a.md", by: alpha.id)
        model.update(activity: activity)
        #expect(model.isAnimating)
        #expect(animations == 1)
        let comet = try #require(model.comets(at: CACurrentMediaTime()).first)
        #expect(comet.tail.map(\.position) == [model.layout?.stars[try star("README.md", in: model)].position])
        model.advance(to: .greatestFiniteMagnitude)
        #expect(!model.isAnimating)
        let landed = try #require(model.comets(at: .greatestFiniteMagnitude).first)
        #expect(landed.head == model.layout?.stars[try star("docs/a.md", in: model)].position)
        #expect(landed.headLift == GalaxyModel.writeLift)
        // The same file again moves nothing: no work at rest.
        model.update(activity: activity)
        #expect(!model.isAnimating)
    }

    @Test func withReduceMotionCometsHaveNoTailAndNeverMove() throws {
        let model = makeModel(reducesMotion: true)
        var activity = GalaxyActivity()
        activity.recordReads(["README.md"], by: alpha.id)
        model.update(activity: activity)
        activity.recordWrite("docs/a.md", by: alpha.id)
        model.update(activity: activity)
        #expect(!model.isAnimating)
        let comet = try #require(model.comets(at: CACurrentMediaTime()).first)
        #expect(comet.tail.isEmpty)
        #expect(comet.head == model.layout?.stars[try star("docs/a.md", in: model)].position)
    }

    @Test func aCometMovingOnAMapWithNoVisibleWindowDrawsNoFrames() {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.reducesMotion = { false }
        let map = GalaxyMapNSView(model: model)
        model.apply(GalaxyLayout(files: GalaxyTests.files))
        map.setFrameSize(CGSize(width: 800, height: 600))
        model.update(sessions: [alpha])
        var activity = GalaxyActivity()
        activity.recordReads(["README.md"], by: alpha.id)
        model.update(activity: activity)
        activity.recordReads(["docs/a.md"], by: alpha.id)
        model.update(activity: activity)
        #expect(model.isAnimating)
        #expect(!map.isDrawingContinuously)
        #expect(map.isPaused)
    }

    @Test func theCometsLabelSaysItsSignNameAndAttivita() {
        let model = makeModel()
        var activity = GalaxyActivity()
        activity.recordReads(["README.md"], by: beta.id)
        model.update(activity: activity)
        let comet = model.labels().first { $0.kind == .comet(isWaiting: true) }
        #expect(comet?.text == "▲ Rete · \(String(localized: Session.Activity.attende.title))")
    }

    // MARK: Chips

    @Test func aChipFiltersTheListAndTheCameraFollowsItsComet() throws {
        let model = makeModel()
        var activity = GalaxyActivity()
        activity.recordWrite("docs/b.md", by: alpha.id)
        activity.recordWrite("README.md", by: alpha.id)
        activity.recordReads(["Package.swift", "docs/a.md"], by: alpha.id)
        activity.recordWrite("Tests/AppTests.swift", by: beta.id)
        model.update(activity: activity)

        model.toggleFilter(alpha.id)
        #expect(model.filter == alpha.id)
        #expect(model.isFollowing)
        #expect(model.rows == [try star("README.md", in: model), try star("docs/b.md", in: model)].sorted())
        #expect(model.readCount(of: alpha.id) == 2)

        model.advance(to: .greatestFiniteMagnitude)
        activity.recordWrite("Sources/App/main.swift", by: alpha.id)
        model.update(activity: activity)
        #expect(model.isFlying)
        model.advance(to: .greatestFiniteMagnitude)
        #expect(model.camera.center == model.layout?.stars[try star("Sources/App/main.swift", in: model)].position)

        // A drag lets the comet go; the list stays filtered.
        model.pan(by: CGSize(width: 10, height: 0))
        #expect(!model.isFollowing)
        activity.recordWrite("docs/adr/0001.md", by: alpha.id)
        model.update(activity: activity)
        #expect(!model.isFlying)
        #expect(model.filter == alpha.id)

        model.toggleFilter(alpha.id)
        #expect(model.filter == nil)
        #expect(model.rows.count == GalaxyTests.files.count)
    }

    @Test func showInGalaxyBeforeTheMapIsReadyFliesToTheCometOnceItIs() throws {
        let model = GalaxyModel(project: URL(filePath: "/tmp/progetto"))
        model.reducesMotion = { true }
        var login = alpha
        login.lastWrite = "README.md"
        model.follow(login.id)
        model.apply(GalaxyLayout(files: GalaxyTests.files))
        model.update(sessions: [login, beta])
        #expect(model.filter == login.id)
        #expect(model.camera.center != model.layout?.stars[try star("README.md", in: model)].position)

        model.resize(to: CGSize(width: 800, height: 600))
        #expect(model.isFollowing)
        #expect(model.camera.center == model.layout?.stars[try star("README.md", in: model)].position)
    }

    @Test func showInGalaxyNeverTurnsTheFilterOff() {
        let model = makeModel()
        model.follow(alpha.id)
        model.follow(alpha.id)
        #expect(model.filter == alpha.id)
        model.follow(beta.id)
        #expect(model.filter == beta.id)
        #expect(model.isFollowing)
    }

    @Test func theOrbFollowsTheFilteredSessioneOnlyWhileItsGalassiaIsInFocus() {
        let project = URL(filePath: "/tmp/progetto").standardizedFileURL
        let store = GalaxyStore(projects: { [] }, viewer: { nil })
        var focus: [UUID?] = []
        store.focusOrb = { focus.append($0) }
        let model = GalaxyModel(project: project)
        model.update(sessions: [alpha, beta])
        model.follow(alpha.id)

        store.filterChanged(in: model)
        #expect(focus.isEmpty)
        store.focusChanged(to: true, in: project)
        store.filterChanged(in: model)
        store.focusChanged(to: false, in: URL(filePath: "/tmp/altro"))
        store.focusChanged(to: false, in: project)
        #expect(focus == [nil, alpha.id, nil])
    }

    @Test func filesOnlyASessioneWroteGetAStar() async throws {
        let folder = URL.temporaryDirectory.appending(path: "galassia-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appending(path: "Sources"), withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "Sources/Old.swift"))
        let model = GalaxyModel(project: folder, cache: GalaxyCache(folder: folder.appending(path: "cache")))
        var session = alpha
        session.writes = ["Sources/New.swift"]
        model.update(sessions: [session])
        await model.load()
        let paths = model.layout?.stars.map(\.path) ?? []
        #expect(paths.contains("Sources/Old.swift"))
        #expect(paths.contains("Sources/New.swift"))
    }
}
