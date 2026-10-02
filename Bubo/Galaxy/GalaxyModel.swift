import CoreServices
import Foundation
import os
import QuartzCore
import simd

/// One Progetto's Galassia: its layout, the search, the selected file and the camera (spec 11).
@Observable
final class GalaxyModel {
    /// A name drawn over the map.
    nonisolated struct Label: Equatable, Identifiable, Sendable {
        var id: String
        var text: String
        /// Where the label's baseline is centered, in the view's points.
        var point: CGPoint
        var kind: Kind

        /// Whether this label and `other` would overlap on screen, estimating each text at 7 points a character.
        func covers(_ other: Label) -> Bool {
            let halfWidths = CGFloat(text.count + other.text.count) * 7 / 2
            return abs(point.x - other.point.x) < halfWidths && abs(point.y - other.point.y) < 14
        }

        /// What a label names.
        enum Kind: Equatable, Sendable {
            /// A folder large enough to read.
            case folder
            /// The selected file, a search result or a file a Sessione wrote.
            case file
            /// A Sessione's comet, with its sign and Attività; `isWaiting` in Attende te.
            case comet(isWaiting: Bool)
        }
    }

    /// What a click on the map lands on.
    nonisolated enum Hit: Equatable, Sendable {
        /// A file, by index in the layout's stars.
        case star(Int)
        /// A folder, by index in the layout's clusters.
        case cluster(Int)
    }

    /// The camera's move towards a file or a folder.
    private struct Flight {
        var start: GalaxyCamera
        var end: GalaxyCamera
        var startTime: CFTimeInterval
    }

    /// A comet's head on its way from where it was to the file its Sessione touched last.
    struct CometMove {
        var start: SIMD2<Float>
        var startLift: Float
        var startTime: CFTimeInterval
    }

    /// The Progetto shown.
    let project: URL
    /// The layout; `nil` until the cache or the first listing gives one.
    private(set) var layout: GalaxyLayout?
    /// Whether the Progetto's files are being listed.
    private(set) var isListing = true
    /// The search on the files' names and paths; its results light up on the map.
    var query = "" {
        didSet { if query != oldValue { updateMatches() } }
    }
    /// The stars matching ``query``, in name order; empty when there is no search.
    private(set) var matches: [Int] = []
    /// The selected file, by index in the layout's stars.
    private(set) var selection: Int?
    /// The file the list should scroll to: set when the selection comes from the map.
    private(set) var revealedInList: Int?
    private(set) var camera = GalaxyCamera() {
        didSet { if camera != oldValue { onRedraw?() } }
    }
    /// The size of the map, in points.
    private(set) var viewSize = CGSize.zero
    /// The Aperta Sessioni of the Progetto, oldest first: one comet each.
    private(set) var sessions: [GalaxySession] = []
    /// What their agents read and wrote since launch.
    private(set) var activity = GalaxyActivity()
    /// The Sessione whose files the list shows and whose comet the camera follows; `nil` for all of them.
    private(set) var filter: UUID?
    /// The Sessioni that wrote each file, by path from the Progetto, oldest Sessione first.
    private(set) var writers: [String: [UUID]] = [:]
    /// What each Sessione changed, as its revisione shows it: the files by path from the Progetto. Missing until read.
    private(set) var changes: [UUID: [String: ChangedFile]] = [:]
    /// The Sessioni whose changes git could not read.
    private(set) var unreadableChanges: Set<UUID> = []
    /// The Sessione whose diff the panel shows, when the user picked one among those that changed the file.
    private(set) var diffChoice: UUID?
    /// Whether the user closed the diff panel; selecting a file opens it again.
    private(set) var isDiffClosed = false

    /// Called when the map must draw again: the camera, the layout or the highlights changed.
    @ObservationIgnored var onRedraw: (() -> Void)?
    /// Whether Riduci movimento is on: then the camera jumps and the comets have no tail and never move.
    @ObservationIgnored var reducesMotion: () -> Bool = { Motion.isReduced }
    /// Called when the camera starts flying or a comet starts moving, so the map draws every frame until
    /// ``isAnimating`` turns false.
    @ObservationIgnored var onAnimation: (() -> Void)?
    /// Grows each time the stars' data changes: the layout, the search or the selection.
    @ObservationIgnored private(set) var contentVersion = 0
    /// Grows each time the files the Sessioni touched change, or the layout they sit on.
    @ObservationIgnored private(set) var activityVersion = 0
    /// Whether the camera follows the filtered Sessione's comet; a drag lets it go.
    @ObservationIgnored private(set) var isFollowing = false
    /// The comets moving now, by Sessione.
    @ObservationIgnored private(set) var cometMoves: [UUID: CometMove] = [:]
    /// The index of each file's star, by path.
    @ObservationIgnored private var starIndex: [String: Int] = [:]
    /// The files the Sessioni wrote that the listing does not have, such as new files in their copies: they get a
    /// star too.
    @ObservationIgnored private var writtenOnly: [String] = []
    @ObservationIgnored private var listed: Set<String> = []
    /// Grows with each layout asked for, so an older one finishing late is dropped.
    @ObservationIgnored private var layoutGeneration = 0
    /// The signpost interval from the opening to the first image with stars.
    @ObservationIgnored private var firstImage: OSSignpostIntervalState?
    @ObservationIgnored private var flight: Flight?
    /// The camera that last showed the whole Galassia; while the camera is still there, a new size or layout shows the
    /// whole Galassia again.
    @ObservationIgnored private var fittedCamera: GalaxyCamera?
    /// The files the layout was made from.
    @ObservationIgnored private var files: [String]?
    @ObservationIgnored private let cache: GalaxyCache

    /// The rows of the list: the files the filtered Sessione wrote, or every file; only the search results when
    /// there is a search.
    var rows: [Int] {
        if let filter {
            let written = writtenStars(by: filter)
            return query.isEmpty ? written : written.filter(Set(matches).contains)
        }
        return query.isEmpty ? Array(layout?.stars.indices ?? 0..<0) : matches
    }

    /// Whether the camera is flying.
    var isFlying: Bool { flight != nil }

    /// Whether the camera flies or a comet moves, and the map must draw every frame.
    var isAnimating: Bool { flight != nil || !cometMoves.isEmpty }

    /// The closest the camera gets to the whole Galassia: half of what fits the view.
    var minimumScale: Float {
        GalaxyCamera.fitting(radius: layout?.radius ?? 1, in: viewSize).scale / 2
    }

    /// How large a radius, in points on the view, a folder's core disc must have for its stars to start showing; they
    /// are fully lit at ``starsShownRadius``. The renderer's shader uses the same values.
    static let starsAppearRadius: Float = 4
    static let starsShownRadius: Float = 10
    /// The most names drawn over the map at once.
    static let labelLimit = 40
    /// How high, in points on the view, a written file rises over the plane.
    static let writeLift: Float = 6

    /// Creates the Galassia of `project`, its files kept in `cache`.
    init(project: URL, cache: GalaxyCache = .standard) {
        self.project = project
        self.cache = cache
        firstImage = Signposts.beginInterval(.galaxyFirstImage)
    }

    // MARK: Files

    /// Shows the cached files at once, then lists the files again and lays them out anew if they changed.
    func load() async {
        if layout == nil, let files = await Self.cachedFiles(of: project, in: cache) {
            setFiles(files)
            await layOut()
        }
        await refresh()
        isListing = false
    }

    /// Lists the files again on every change FSEvents reports under the Progetto, until the task is cancelled.
    func watch() async {
        let events = FileEvents.batches(under: project.path, since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow))
        for await batch in events {
            // What git writes in its own folder changes no file of the Progetto.
            guard batch.needsRescan || batch.paths.contains(where: { !$0.contains("/.git/") }) else { continue }
            await refresh()
        }
    }

    /// Lists the files and, when they changed, lays them out again and saves them.
    func refresh() async {
        let files = await GalaxyFiles.list(in: project)
        guard files != self.files else { return }
        setFiles(files)
        await layOut()
        await Self.save(files, of: project, in: cache)
    }

    private func setFiles(_ files: [String]) {
        self.files = files
        listed = Set(files)
        writtenOnly = Set(writers.keys).subtracting(listed).sorted()
    }

    /// Lays out the listed files and those only the Sessioni wrote, unless a newer layout was asked for meanwhile.
    private func layOut() async {
        guard let files else { return }
        layoutGeneration += 1
        let generation = layoutGeneration
        let layout = await Self.makeLayout(files: files + writtenOnly)
        guard generation == layoutGeneration else { return }
        apply(layout)
    }

    /// Replaces the layout, keeping the selected file when it is still there.
    func apply(_ layout: GalaxyLayout) {
        let selected = selection.flatMap { self.layout?.stars[$0].path }
        self.layout = layout
        starIndex = Dictionary(layout.stars.enumerated().map { ($1.path, $0) }) { first, _ in first }
        selection = selected.flatMap { starIndex[$0] }
        cometMoves = [:]
        activityVersion += 1
        updateMatches()
        if isShowingAll { fit() }
    }

    @concurrent
    private static func cachedFiles(of project: URL, in cache: GalaxyCache) async -> [String]? {
        cache.files(of: project)
    }

    @concurrent
    private static func save(_ files: [String], of project: URL, in cache: GalaxyCache) async {
        cache.save(files, of: project)
    }

    @concurrent
    private static func makeLayout(files: [String]) async -> GalaxyLayout {
        GalaxyLayout(files: files)
    }

    private func updateMatches() {
        let query = query.trimmingCharacters(in: .whitespaces)
        if query.isEmpty || layout == nil {
            matches = []
        } else {
            matches = layout?.stars.indices.filter { layout?.stars[$0].path.localizedStandardContains(query) == true }
                ?? []
        }
        contentChanged()
    }

    private func contentChanged() {
        contentVersion += 1
        onRedraw?()
    }

    // MARK: Selection

    /// Selects the file at `index` from the list, and flies the camera to it.
    func select(_ index: Int?) {
        guard index != selection else { return }
        selection = index
        reopenDiff()
        contentChanged()
        guard let index, let layout else { return }
        fly(to: camera(showing: index, in: layout))
    }

    /// The camera on the star at `index`: close enough for its folder's stars to show well, never farther than now.
    func camera(showing index: Int, in layout: GalaxyLayout) -> GalaxyCamera {
        let star = layout.stars[index]
        let scale = max(camera.scale, Self.starsShownRadius * 3 / GalaxyLayout.coreRadius)
        return GalaxyCamera(center: star.position, scale: min(scale, GalaxyCamera.maximumScale))
    }

    /// Acts on a click at `point` of the map: a file is selected, shown in the list and flown to, with its diff; a
    /// folder is zoomed into.
    func click(at point: CGPoint) {
        switch hit(at: point) {
        case let .star(index):
            selection = index
            revealedInList = index
            reopenDiff()
            contentChanged()
            if let layout { fly(to: camera(showing: index, in: layout)) }
        case let .cluster(index):
            guard let cluster = layout?.clusters[index] else { return }
            fly(to: .fitting(radius: cluster.radius, around: cluster.center, in: viewSize))
        case nil:
            break
        }
    }

    /// What is at `point` of the map: the nearest visible star within 10 points, else the smallest folder there.
    func hit(at point: CGPoint) -> Hit? {
        guard let layout else { return nil }
        let plane = camera.plane(at: point, in: viewSize)
        var nearest: (index: Int, distance: Float)?
        let highlighted = Set(matches)
        // Every core disc has the same radius: the stars show all together or not at all.
        let shown = GalaxyLayout.coreRadius * camera.scale >= Self.starsAppearRadius
        for (index, star) in layout.stars.enumerated() {
            guard shown || highlighted.contains(index) || index == selection || writers[star.path] != nil
            else { continue }
            let distance = Self.screenDistance(star.position - plane, scale: camera.scale)
            if distance <= 10, distance < nearest?.distance ?? .infinity { nearest = (index, distance) }
        }
        if let nearest { return .star(nearest.index) }
        let inside = layout.clusters.indices.dropFirst().filter { index in
            let cluster = layout.clusters[index]
            return simd_length(cluster.center - plane) <= cluster.radius
        }
        return inside.max { layout.clusters[$0].depth < layout.clusters[$1].depth }.map(Hit.cluster)
    }

    private static func screenDistance(_ offset: SIMD2<Float>, scale: Float) -> Float {
        simd_length(SIMD2(offset.x * scale, offset.y * scale * GalaxyCamera.tilt))
    }

    /// Records that the list scrolled to the file the map selected.
    func didRevealInList() {
        revealedInList = nil
    }

    // MARK: Camera

    /// Records the map's size; until the camera moves, the whole Galassia stays in view.
    func resize(to size: CGSize) {
        guard size != viewSize else { return }
        viewSize = size
        if isShowingAll { fit() }
        onRedraw?()
    }

    /// Whether the camera shows the whole Galassia as ``fit()`` left it, or has not been placed yet.
    private var isShowingAll: Bool {
        fittedCamera == nil || camera == fittedCamera
    }

    /// Shows the whole Galassia.
    func fit() {
        guard let layout, viewSize != .zero else { return }
        flight = nil
        camera = .fitting(radius: layout.radius, around: layout.center, in: viewSize)
        fittedCamera = camera
    }

    /// Whether the stars are fully lit at the camera's zoom: every folder's core disc has a radius of at least
    /// ``starsShownRadius`` points on the view.
    var areStarsLit: Bool {
        GalaxyLayout.coreRadius * camera.scale >= Self.starsShownRadius
    }

    /// Moves the map by `translation` points, as a drag or a two-finger scroll does; the camera stops following a
    /// comet.
    func pan(by translation: CGSize) {
        flight = nil
        isFollowing = false
        camera.pan(by: translation)
    }

    /// Zooms by `factor` around `anchor`, as a pinch or the mouse wheel does.
    func zoom(by factor: Float, around anchor: CGPoint) {
        flight = nil
        camera.zoom(by: factor, around: anchor, in: viewSize, minimumScale: minimumScale)
    }

    /// Moves the camera to `target`: a flight, or a jump with Riduci movimento.
    func fly(to target: GalaxyCamera) {
        guard !reducesMotion(), viewSize != .zero else {
            flight = nil
            camera = target
            return
        }
        flight = Flight(start: camera, end: target, startTime: CACurrentMediaTime())
        onAnimation?()
    }

    /// Moves the flight and the comets on to the time `now`, ending those that arrived.
    func advance(to now: CFTimeInterval) {
        advanceFlight(to: now)
        cometMoves = cometMoves.filter { now - $0.value.startTime < Motion.galaxyComet }
    }

    /// Moves a flight on to the time `now`, ending it when it arrives.
    func advanceFlight(to now: CFTimeInterval) {
        guard let flight else { return }
        let progress = (now - flight.startTime) / Motion.galaxyFlight
        camera = .interpolated(from: flight.start, to: flight.end, progress: progress)
        if progress >= 1 { self.flight = nil }
    }

    /// Records that the map drew; the first image with stars ends the opening's signpost.
    func didDraw() {
        guard layout != nil, let firstImage else { return }
        Signposts.endInterval(.galaxyFirstImage, firstImage)
        self.firstImage = nil
    }

    // MARK: Sessioni

    /// A comet as the map draws it at one moment: its head, and the tail through the files touched before.
    struct Comet {
        let id: UUID
        var head: SIMD2<Float>
        /// How high the head is over the plane, in points.
        var headLift: Float
        /// The files touched before the head, oldest first, each with its lift; empty with Riduci movimento.
        var tail: [(position: SIMD2<Float>, lift: Float)]
    }

    /// Shows the comets of `sessions`, the Aperta Sessioni of the Progetto; a filter on a Sessione that is gone goes.
    func update(sessions: [GalaxySession]) {
        guard sessions != self.sessions else { return }
        let before = heads()
        self.sessions = sessions
        if let filter, !sessions.contains(where: { $0.id == filter }) {
            self.filter = nil
            isFollowing = false
        }
        let ids = Set(sessions.map(\.id))
        if changes.keys.contains(where: { !ids.contains($0) }) { changes = changes.filter { ids.contains($0.key) } }
        unreadableChanges.formIntersection(ids)
        touchesChanged(headsBefore: before)
    }

    /// Lights the files in `activity`, and moves the comets of the Sessioni that touched a new file.
    func update(activity: GalaxyActivity) {
        guard activity != self.activity else { return }
        let before = heads()
        self.activity = activity
        touchesChanged(headsBefore: before)
    }

    /// Filters the list on the Sessione `id`, and makes the camera follow its comet; on the filtered Sessione,
    /// shows every Sessione again.
    func toggleFilter(_ id: UUID) {
        guard id != filter else {
            showAllSessions()
            return
        }
        filter = id
        isFollowing = true
        guard let layout, let session = sessions.first(where: { $0.id == id }),
              let index = head(of: session).flatMap({ starIndex[$0] })
        else { return }
        fly(to: camera(showing: index, in: layout))
    }

    /// Shows the files of every Sessione, and stops following a comet.
    func showAllSessions() {
        filter = nil
        isFollowing = false
    }

    /// The stars of the files the Sessione `id` wrote, in the list's order.
    func writtenStars(by id: UUID) -> [Int] {
        guard let session = sessions.first(where: { $0.id == id }) else { return [] }
        let paths = session.writes.union(activity.traces[id]?.writes ?? [])
        return paths.compactMap { starIndex[$0] }.sorted()
    }

    /// How many files the agent of the Sessione `id` read since launch.
    func readCount(of id: UUID) -> Int {
        activity.traces[id]?.reads.count ?? 0
    }

    /// The Sessioni that wrote the file of the star at `index`, oldest first; more than one is a collision.
    func sessionsWriting(_ index: Int) -> [GalaxySession] {
        guard let path = layout?.stars[index].path, let ids = writers[path] else { return [] }
        return sessions.filter { ids.contains($0.id) }
    }

    /// The files lit on the map: those the Sessioni read lately, and those they wrote, which rise.
    func litStars() -> [(index: Int, isWritten: Bool, isCollision: Bool)] {
        var lit: [Int: (isWritten: Bool, isCollision: Bool)] = [:]
        for session in sessions {
            for path in activity.traces[session.id]?.recentReads ?? [] {
                if let index = starIndex[path] { lit[index] = (false, false) }
            }
        }
        for (path, ids) in writers {
            if let index = starIndex[path] { lit[index] = (true, ids.count > 1) }
        }
        return lit.sorted { $0.key < $1.key }.map { ($0.key, $0.value.isWritten, $0.value.isCollision) }
    }

    /// The comets at the time `now`, one for each Sessione that touched a file with a star.
    func comets(at now: CFTimeInterval) -> [Comet] {
        guard let layout else { return [] }
        let showsTail = !reducesMotion()
        return sessions.compactMap { session in
            guard let path = head(of: session), let index = starIndex[path] else { return nil }
            var head = layout.stars[index].position
            var headLift = lift(of: path)
            if let move = cometMoves[session.id] {
                let progress = Float(min(max((now - move.startTime) / Motion.galaxyComet, 0), 1))
                let eased = progress * progress * (3 - 2 * progress)
                head = simd_mix(move.start, head, SIMD2(repeating: eased))
                headLift = move.startLift + (headLift - move.startLift) * eased
            }
            let trail = showsTail ? activity.traces[session.id]?.trail.dropLast() ?? [] : []
            let tail = trail.compactMap { path in
                starIndex[path].map { (position: layout.stars[$0].position, lift: lift(of: path)) }
            }
            return Comet(id: session.id, head: head, headLift: headLift, tail: tail)
        }
    }

    /// The file the Sessione touched last: where its comet's head is.
    func head(of session: GalaxySession) -> String? {
        activity.traces[session.id]?.trail.last ?? session.lastWrite
    }

    /// How high the file at `path` rises over the plane, in points: only written files do.
    func lift(of path: String) -> Float {
        writers[path] == nil ? 0 : Self.writeLift
    }

    /// Where each comet's head is drawn now, by Sessione.
    private func heads() -> [UUID: (path: String?, position: SIMD2<Float>, lift: Float)] {
        let drawn = Dictionary(uniqueKeysWithValues: comets(at: CACurrentMediaTime()).map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: sessions.map { session in
            (session.id, (head(of: session), drawn[session.id]?.head ?? .zero, drawn[session.id]?.headLift ?? 0))
        })
    }

    /// Works out who wrote what, lays out files only the Sessioni have, and starts the comets that moved.
    private func touchesChanged(headsBefore before: [UUID: (path: String?, position: SIMD2<Float>, lift: Float)]) {
        var writers: [String: [UUID]] = [:]
        for session in sessions {
            for path in session.writes.union(activity.traces[session.id]?.writes ?? []) {
                writers[path, default: []].append(session.id)
            }
        }
        self.writers = writers
        let written = Set(writers.keys).subtracting(listed).sorted()
        if files != nil, written != writtenOnly {
            writtenOnly = written
            Task { await layOut() }
        }
        let now = CACurrentMediaTime()
        var isMoving = false
        for session in sessions {
            guard let path = head(of: session), let index = starIndex[path],
                  let previous = before[session.id], previous.path != path
            else { continue }
            if session.id == filter, isFollowing, let layout { fly(to: camera(showing: index, in: layout)) }
            // A comet appears where it is; it moves only from one file to the next, and never with Riduci movimento.
            guard previous.path.flatMap({ starIndex[$0] }) != nil, !reducesMotion(), viewSize != .zero else { continue }
            cometMoves[session.id] = CometMove(start: previous.position, startLift: previous.lift, startTime: now)
            isMoving = true
        }
        activityVersion += 1
        onRedraw?()
        if isMoving { onAnimation?() }
    }

    // MARK: Diff

    /// The diff of the selected file, as the glass panel over the map shows it.
    struct Diff: Equatable {
        /// What the panel shows of the file.
        enum Content: Equatable {
            /// Outside git: there is no version from before the Sessione to compare with.
            case noVersionBefore
            case loading
            case unreadable
            /// The file as the Sessione's revisione shows it; `nil` when the revisione does not have it.
            case file(ChangedFile?)
        }

        /// The file's path from the Progetto.
        let path: String
        /// The Sessioni that wrote or changed the file, oldest first.
        let sessions: [GalaxySession]
        /// The Sessione whose diff is shown.
        let session: GalaxySession
        let content: Content
    }

    /// The diff of the selected file: of the Sessione picked in the panel, else of the filtered one, else of the
    /// oldest that wrote or changed it. `nil` when no Sessione did, or the panel is closed.
    var diff: Diff? {
        guard !isDiffClosed, let selection, let path = layout?.stars[selection].path else { return nil }
        let concerned = sessions.filter { writers[path]?.contains($0.id) == true || changes[$0.id]?[path] != nil }
        guard let session = concerned.first(where: { $0.id == diffChoice })
            ?? concerned.first(where: { $0.id == filter }) ?? concerned.first
        else { return nil }
        let content: Diff.Content = if !session.isReviewable {
            .noVersionBefore
        } else if unreadableChanges.contains(session.id) {
            .unreadable
        } else if let files = changes[session.id] {
            .file(files[path])
        } else {
            .loading
        }
        return Diff(path: path, sessions: concerned, session: session, content: content)
    }

    /// Records the changes of the Sessione `id` as its revisione reads them; `nil` when git could not read them.
    func update(changes files: [ChangedFile]?, of id: UUID) {
        guard let files else {
            unreadableChanges.insert(id)
            return
        }
        let byPath = Dictionary(files.map { ($0.path, $0) }) { first, _ in first }
        unreadableChanges.remove(id)
        if changes[id] != byPath { changes[id] = byPath }
    }

    /// Shows in the panel the diff of the Sessione `id`.
    func showDiff(of id: UUID) {
        diffChoice = id
    }

    /// Closes the diff panel until a file is selected again.
    func closeDiff() {
        isDiffClosed = true
    }

    private func reopenDiff() {
        isDiffClosed = false
        diffChoice = nil
    }

    /// The lines added and removed in the file of the star at `index` by the filtered Sessione, or by all of them;
    /// `nil` when none changed it.
    func lineCounts(of index: Int) -> (added: Int, removed: Int)? {
        guard let path = layout?.stars[index].path else { return nil }
        let ids = filter.map { [$0] } ?? sessions.map(\.id)
        let files = ids.compactMap { changes[$0]?[path] }
        guard !files.isEmpty else { return nil }
        let hunks = files.flatMap(\.hunks)
        return (hunks.reduce(0) { $0 + $1.added }, hunks.reduce(0) { $0 + $1.removed })
    }

    // MARK: Labels

    /// The names to draw over the map: the selected file, the search results in view, and the folders large enough
    /// to read, at most ``labelLimit``.
    func labels() -> [Label] {
        guard let layout, viewSize != .zero else { return [] }
        let bounds = CGRect(origin: .zero, size: viewSize)
        var labels: [Label] = []
        var named = Set<Int>()
        func fileLabel(_ index: Int) {
            guard named.insert(index).inserted else { return }
            let star = layout.stars[index]
            var point = camera.point(for: star.position, in: viewSize)
            point.y -= 10 + CGFloat(lift(of: star.path))
            guard bounds.contains(point) else { return }
            labels.append(Label(id: "f" + star.path, text: (star.path as NSString).lastPathComponent, point: point,
                                kind: .file))
        }
        for session in sessions {
            guard let path = head(of: session), let index = starIndex[path] else { continue }
            var point = camera.point(for: layout.stars[index].position, in: viewSize)
            point.y -= 14 + CGFloat(lift(of: path))
            guard bounds.insetBy(dx: -40, dy: 0).contains(point) else { continue }
            let text = "\(session.sign) \(session.title) · \(String(localized: session.activity.title))"
            labels.append(Label(id: "s" + session.id.uuidString, text: text, point: point,
                                kind: .comet(isWaiting: session.activity == .attende)))
            named.insert(index)
        }
        if let selection { fileLabel(selection) }
        for index in matches where !named.contains(index) {
            guard labels.count < 12 else { break }
            fileLabel(index)
        }
        // The names of the files the Sessioni wrote are always there, within the same limit.
        for path in writers.keys.sorted() {
            guard labels.count < 24 else { break }
            if let index = starIndex[path] { fileLabel(index) }
        }
        let folders = layout.clusters.indices.dropFirst().filter { index in
            let cluster = layout.clusters[index]
            let radius = cluster.radius * camera.scale
            return radius >= (cluster.depth == 1 ? 30 : 90)
        }
        .sorted { layout.clusters[$0].radius > layout.clusters[$1].radius }
        for index in folders {
            guard labels.count < Self.labelLimit else { break }
            let cluster = layout.clusters[index]
            var point = camera.point(for: cluster.center, in: viewSize)
            point.y -= CGFloat(cluster.radius * camera.scale * GalaxyCamera.tilt) + 4
            guard bounds.insetBy(dx: -40, dy: 0).contains(point) else { continue }
            // A folder holding one large subfolder has its name over the subfolder's: only the larger one's shows.
            let label = Label(id: "c" + cluster.path, text: (cluster.path as NSString).lastPathComponent,
                              point: point, kind: .folder)
            guard !labels.contains(where: { $0.kind == .folder && $0.covers(label) }) else { continue }
            labels.append(label)
        }
        return labels
    }
}
