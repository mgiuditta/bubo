import CoreServices
import Foundation
import QuartzCore
import simd

/// The Neuroni of the Secondo cervello: its notes as a graph of their links, the search, the folder filter, the
/// selected note and the notes cited in the last answer.
@Observable
final class NeuronModel {
    /// A note's name drawn over the map.
    nonisolated struct Label: Equatable, Identifiable, Sendable {
        var id: Int
        var text: String
        /// Where the label's baseline is centered, in the view's points.
        var point: CGPoint
        /// Whether it names the selected note or one cited in the last answer.
        var isStrong: Bool
    }

    /// The camera's move towards a note.
    private struct Flight {
        var start: GalaxyCamera
        var end: GalaxyCamera
        var startTime: CFTimeInterval
    }

    /// The Secondo cervello shown.
    let secondBrain: SecondBrainLocation
    /// The notes and their links; `nil` until the first reading.
    private(set) var graph: NeuronGraph?
    /// The place of each note on the plane, by index in the graph.
    @ObservationIgnored private(set) var positions: [SIMD2<Float>] = []
    /// The search on the notes' names and paths.
    var query = "" {
        didSet { if query != oldValue { updateShown() } }
    }
    /// The top folder whose notes are shown; `nil` for all of them, `""` for the notes at the top.
    var folder: String? {
        didSet { if folder != oldValue { updateShown() } }
    }
    /// The notes the list shows and the map lights: those of the folder that match the search, in path order.
    private(set) var rows: [Int] = []
    /// The selected note, by index in the graph.
    private(set) var selection: Int?
    /// The note the list should scroll to: set when the selection comes from the map.
    private(set) var revealedInList: Int?
    /// The notes cited in the last answer, by index in the graph.
    private(set) var cited: Set<Int> = []
    private(set) var camera = GalaxyCamera(tilt: 1) {
        didSet { if camera != oldValue { onRedraw?() } }
    }
    /// The size of the map, in points.
    private(set) var viewSize = CGSize.zero

    /// Called when the map must draw again.
    @ObservationIgnored var onRedraw: (() -> Void)?
    /// Called when the camera starts flying, so the map draws every frame until ``isAnimating`` turns false.
    @ObservationIgnored var onAnimation: (() -> Void)?
    /// Whether Riduci movimento is on: then the camera jumps.
    @ObservationIgnored var reducesMotion: () -> Bool = { Motion.isReduced }
    /// Grows each time what the nodes show changes: the graph, the rows, the selection or the cited notes.
    @ObservationIgnored private(set) var contentVersion = 0
    @ObservationIgnored private var isShown: [Bool] = []
    /// The shown notes, the most linked first: the names drawn after the selected, cited and found notes.
    @ObservationIgnored private var hubs: [Int] = []
    @ObservationIgnored private var flight: Flight?
    @ObservationIgnored private var fittedCamera: GalaxyCamera?
    @ObservationIgnored private var citations: [NoteCitation] = []
    @ObservationIgnored private let cache: NeuronCache

    /// The most names drawn over the map at once.
    static let labelLimit = 40

    /// Creates the Neuroni of `secondBrain`, their links and places kept in `cache`.
    init(secondBrain: SecondBrainLocation, cache: NeuronCache = .standard) {
        self.secondBrain = secondBrain
        self.cache = cache
    }

    /// Whether the camera flies, and the map must draw every frame.
    var isAnimating: Bool { flight != nil }

    // MARK: Notes

    /// Reads the notes, their links and their places, again on every change under the Secondo cervello, until the task
    /// is cancelled.
    func watch() async {
        await refresh()
        let events = FileEvents.batches(under: secondBrain.path, since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow))
        for await batch in events where batch.needsRescan || batch.paths.contains(where: { $0.hasSuffix(".md") }) {
            await refresh()
        }
    }

    /// Reads the notes again, keeping the selection when its note is still there.
    func refresh() async {
        let (graph, positions) = await Self.read(secondBrain, cache: cache)
        guard graph != self.graph || positions != self.positions else { return }
        let selected = selection.flatMap { self.graph?.notes[$0].path }
        self.graph = graph
        self.positions = positions
        selection = selected.flatMap { path in graph.notes.firstIndex { $0.path == path } }
        updateCited()
        updateShown()
        if isShowingAll { fit() }
    }

    /// Reads the notes of `secondBrain`, only those changed since the last time, and places the new ones.
    @concurrent
    static func read(_ secondBrain: SecondBrainLocation,
                     cache: NeuronCache) async -> (graph: NeuronGraph, positions: [SIMD2<Float>]) {
        let saved = cache.entries(of: secondBrain.path)
        let found = SecondBrainNotes.files(at: secondBrain.path, in: secondBrain.path,
                                           excluding: Set(secondBrain.excludedFolders)).notes
        var entries: [String: NeuronCache.Entry] = [:]
        for (file, stamp) in found where file.lowercased().hasSuffix(".md") {
            let path = String(file.dropFirst(secondBrain.path.count + 1))
            if let entry = saved[path], entry.matches(stamp) {
                entries[path] = entry
            } else {
                let text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
                entries[path] = NeuronCache.Entry(size: stamp.size, modified: stamp.modified,
                                                  links: NoteLink.links(in: text))
            }
        }
        let graph = NeuronGraph(links: entries.mapValues(\.links))
        let positions = NeuronLayout.positions(of: graph, keeping: entries.compactMapValues(\.position))
        for (note, position) in zip(graph.notes, positions) {
            entries[note.path]?.x = position.x
            entries[note.path]?.y = position.y
        }
        if entries != saved { cache.save(entries, of: secondBrain.path) }
        return (graph, positions)
    }

    /// Lights the notes `citations` name, the citations of the last answer.
    func show(citations: [NoteCitation]) {
        guard citations != self.citations else { return }
        self.citations = citations
        updateCited()
        contentChanged()
    }

    private func updateCited() {
        guard let graph else { return }
        let resolver = NoteLinkResolver(paths: graph.notes.map(\.path))
        cited = Set(citations.compactMap { resolver.note(linkedBy: NoteLink(target: $0.note, kind: .wikilink), from: "") })
    }

    private func updateShown() {
        guard let graph else { return }
        let search = query.trimmingCharacters(in: .whitespaces)
        isShown = graph.notes.map { note in
            (folder == nil || note.folder == folder) && (search.isEmpty || note.path.localizedStandardContains(search))
        }
        rows = isShown.indices.filter { isShown[$0] }
        hubs = rows.sorted { graph.notes[$0].degree > graph.notes[$1].degree }
        contentChanged()
    }

    /// Whether the note at `index` is in the folder and matches the search.
    func isShown(_ index: Int) -> Bool {
        isShown.indices.contains(index) && isShown[index]
    }

    /// The file of the note at `index`.
    func file(of index: Int) -> URL? {
        graph.map { secondBrain.url.appending(path: $0.notes[index].path) }
    }

    private func contentChanged() {
        contentVersion += 1
        onRedraw?()
    }

    // MARK: Selection

    /// Selects the note at `index` from the list, and flies the camera to it.
    func select(_ index: Int?) {
        guard index != selection else { return }
        selection = index
        contentChanged()
        guard let index else { return }
        fly(to: GalaxyCamera(center: positions[index], scale: max(camera.scale, 1.5), tilt: 1))
    }

    /// Selects the note at `point` of the map and shows it in the list; nothing when no shown note is there.
    func click(at point: CGPoint) {
        guard let index = hit(at: point) else { return }
        selection = index
        revealedInList = index
        contentChanged()
    }

    /// The shown note nearest to `point` of the map, within 10 points or its own radius.
    func hit(at point: CGPoint) -> Int? {
        guard let graph else { return nil }
        let plane = camera.plane(at: point, in: viewSize)
        var nearest: (index: Int, distance: Float)?
        for index in graph.notes.indices where isShown(index) {
            let distance = simd_length(positions[index] - plane) * camera.scale
            let reach = max(10, Self.radius(of: graph.notes[index]) * camera.scale)
            if distance <= reach, distance < nearest?.distance ?? .infinity { nearest = (index, distance) }
        }
        return nearest?.index
    }

    /// Records that the list scrolled to the note the map selected.
    func didRevealInList() {
        revealedInList = nil
    }

    /// The radius of a note on the plane: larger with more links.
    nonisolated static func radius(of note: NeuronGraph.Note) -> Float {
        min(2.5 + 1.2 * Float(note.degree).squareRoot(), 12)
    }

    // MARK: Labels

    /// The names drawn over the map, at most ``labelLimit`` and never overlapping: the selected note, the cited ones,
    /// the search results, then the notes with the most links, those in view only.
    func labels() -> [Label] {
        guard let graph, viewSize != .zero else { return [] }
        let isSearching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let first = [selection].compactMap { $0 } + cited.sorted() + (isSearching ? rows.prefix(Self.labelLimit) : [])
        var labels: [Label] = []
        var seen: Set<Int> = []
        for index in first + hubs.prefix(Self.labelLimit * 4) where labels.count < Self.labelLimit && seen.insert(index).inserted {
            let center = camera.point(for: positions[index], in: viewSize)
            let lift = CGFloat(Self.radius(of: graph.notes[index]) * camera.scale) + 4
            let point = CGPoint(x: center.x, y: center.y - lift)
            guard point.x > 0, point.x < viewSize.width, point.y > 14, point.y < viewSize.height else { continue }
            let label = Label(id: index, text: graph.notes[index].name, point: point,
                              isStrong: index == selection || cited.contains(index))
            let halfWidth = CGFloat(label.text.count) * 3.5
            guard !labels.contains(where: { abs($0.point.x - point.x) < halfWidth + CGFloat($0.text.count) * 3.5
                && abs($0.point.y - point.y) < 14 }) else { continue }
            labels.append(label)
        }
        return labels
    }

    // MARK: Camera

    /// Records the map's size; until the camera moves, the whole graph stays in view.
    func resize(to size: CGSize) {
        guard size != viewSize else { return }
        viewSize = size
        if isShowingAll { fit() }
        onRedraw?()
    }

    private var isShowingAll: Bool {
        fittedCamera == nil || camera == fittedCamera
    }

    /// The radius of the circle around the middle that holds every note.
    private var extent: (center: SIMD2<Float>, radius: Float) {
        guard let first = positions.first else { return (.zero, 1) }
        let (low, high) = positions.reduce((first, first)) { (simd_min($0.0, $1), simd_max($0.1, $1)) }
        return ((low + high) / 2, max(simd_length(high - low) / 2, 1))
    }

    /// Shows every note.
    func fit() {
        guard graph != nil, viewSize != .zero else { return }
        flight = nil
        let (center, radius) = extent
        camera = .fitting(radius: radius, around: center, in: viewSize, tilt: 1)
        fittedCamera = camera
    }

    /// Moves the map by `translation` points, as a drag or a two-finger scroll does.
    func pan(by translation: CGSize) {
        flight = nil
        camera.pan(by: translation)
    }

    /// Zooms by `factor` around `anchor`, as a pinch or the mouse wheel does.
    func zoom(by factor: Float, around anchor: CGPoint) {
        flight = nil
        let minimum = GalaxyCamera.fitting(radius: extent.radius, in: viewSize, tilt: 1).scale / 2
        camera.zoom(by: factor, around: anchor, in: viewSize, minimumScale: minimum)
    }

    private func fly(to target: GalaxyCamera) {
        guard !reducesMotion(), viewSize != .zero else {
            flight = nil
            camera = target
            return
        }
        flight = Flight(start: camera, end: target, startTime: CACurrentMediaTime())
        onAnimation?()
    }

    /// Moves a flight on to the time `now`, ending it when it arrives.
    func advance(to now: CFTimeInterval) {
        guard let flight else { return }
        let progress = (now - flight.startTime) / Motion.galaxyFlight
        camera = .interpolated(from: flight.start, to: flight.end, progress: progress)
        if progress >= 1 { self.flight = nil }
    }
}
