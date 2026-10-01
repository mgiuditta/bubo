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
        /// Whether it names the selected file or a search result rather than a folder.
        var isFile: Bool
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

    /// Called when the map must draw again: the camera, the layout or the highlights changed.
    @ObservationIgnored var onRedraw: (() -> Void)?
    /// Called when the camera starts flying, so the map draws every frame until ``isFlying`` turns false.
    @ObservationIgnored var onFlight: (() -> Void)?
    /// Grows each time the stars' data changes: the layout, the search or the selection.
    @ObservationIgnored private(set) var contentVersion = 0
    /// The signpost interval from the opening to the first image with stars.
    @ObservationIgnored private var firstImage: OSSignpostIntervalState?
    @ObservationIgnored private var flight: Flight?
    @ObservationIgnored private var hasFitted = false
    /// The files the layout was made from.
    @ObservationIgnored private var files: [String]?
    @ObservationIgnored private let cache: GalaxyCache

    /// The rows of the list: the search results, or every file when there is no search.
    var rows: [Int] {
        query.isEmpty ? Array(layout?.stars.indices ?? 0..<0) : matches
    }

    /// Whether the camera is flying, and the map must draw every frame.
    var isFlying: Bool { flight != nil }

    /// The closest the camera gets to the whole Galassia: half of what fits the view.
    var minimumScale: Float {
        GalaxyCamera.fitting(radius: layout?.radius ?? 1, in: viewSize).scale / 2
    }

    /// How large, in points on the view, a folder must be for its stars to start showing; they are fully lit at
    /// ``starsShownRadius``. The renderer's shader uses the same values.
    static let starsAppearRadius: Float = 15
    static let starsShownRadius: Float = 40
    /// The most names drawn over the map at once.
    static let labelLimit = 40

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
            self.files = files
            apply(await Self.makeLayout(files: files))
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
        self.files = files
        apply(await Self.makeLayout(files: files))
        await Self.save(files, of: project, in: cache)
    }

    /// Replaces the layout, keeping the selected file when it is still there.
    func apply(_ layout: GalaxyLayout) {
        let selected = selection.flatMap { self.layout?.stars[$0].path }
        self.layout = layout
        selection = selected.flatMap { path in layout.stars.firstIndex { $0.path == path } }
        updateMatches()
        if !hasFitted, viewSize != .zero { fit() }
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
        contentChanged()
        guard let index, let layout else { return }
        let star = layout.stars[index]
        let cluster = layout.clusters[star.cluster]
        // Close enough for the folder's stars to show well, never farther than now.
        let scale = max(camera.scale, Self.starsShownRadius * 3 / cluster.radius)
        fly(to: GalaxyCamera(center: star.position, scale: min(scale, GalaxyCamera.maximumScale)))
    }

    /// Acts on a click at `point` of the map: a file is selected and shown in the list, a folder is zoomed into.
    func click(at point: CGPoint) {
        switch hit(at: point) {
        case let .star(index):
            selection = index
            revealedInList = index
            contentChanged()
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
        for (index, star) in layout.stars.enumerated() {
            let shown = layout.clusters[star.cluster].radius * camera.scale >= Self.starsAppearRadius
            guard shown || highlighted.contains(index) || index == selection else { continue }
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

    /// Records the map's size; the first size with a layout fits the whole Galassia.
    func resize(to size: CGSize) {
        guard size != viewSize else { return }
        viewSize = size
        if !hasFitted, layout != nil, size != .zero { fit() }
        onRedraw?()
    }

    /// Shows the whole Galassia.
    func fit() {
        guard let layout, viewSize != .zero else { return }
        hasFitted = true
        flight = nil
        camera = .fitting(radius: layout.radius, in: viewSize)
    }

    /// Moves the map by `translation` points, as a drag or a two-finger scroll does.
    func pan(by translation: CGSize) {
        flight = nil
        camera.pan(by: translation)
    }

    /// Zooms by `factor` around `anchor`, as a pinch or the mouse wheel does.
    func zoom(by factor: Float, around anchor: CGPoint) {
        flight = nil
        camera.zoom(by: factor, around: anchor, in: viewSize, minimumScale: minimumScale)
    }

    /// Moves the camera to `target`: a flight, or a jump with Riduci movimento.
    func fly(to target: GalaxyCamera) {
        guard !Motion.isReduced, viewSize != .zero else {
            flight = nil
            camera = target
            return
        }
        flight = Flight(start: camera, end: target, startTime: CACurrentMediaTime())
        onFlight?()
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

    // MARK: Labels

    /// The names to draw over the map: the selected file, the search results in view, and the folders large enough
    /// to read, at most ``labelLimit``.
    func labels() -> [Label] {
        guard let layout, viewSize != .zero else { return [] }
        let bounds = CGRect(origin: .zero, size: viewSize)
        var labels: [Label] = []
        func fileLabel(_ index: Int) {
            let star = layout.stars[index]
            var point = camera.point(for: star.position, in: viewSize)
            point.y -= 10
            guard bounds.contains(point) else { return }
            labels.append(Label(id: "f" + star.path, text: (star.path as NSString).lastPathComponent, point: point,
                                isFile: true))
        }
        if let selection { fileLabel(selection) }
        for index in matches where index != selection {
            guard labels.count < 12 else { break }
            fileLabel(index)
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
            labels.append(Label(id: "c" + cluster.path, text: (cluster.path as NSString).lastPathComponent,
                                point: point, isFile: false))
        }
        return labels
    }
}
