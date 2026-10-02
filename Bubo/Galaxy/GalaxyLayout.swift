import Foundation
import simd

/// Where every folder and file of a Progetto sits on the Galassia's plane (spec 11).
///
/// A folder is an ammasso: a core disc with its files, its subfolders packed tight around it in name order, all inside
/// the smallest circle that holds them. An ammasso's size comes from its subfolders only, never from how many files it
/// holds, so adding or removing files never moves an ammasso: only the stars inside the folder that changed rearrange.
/// A subfolder's place depends only on the subfolders before it, so a new folder never moves those. The same files
/// always give the same layout.
nonisolated struct GalaxyLayout: Equatable, Sendable {
    /// A folder on the plane.
    nonisolated struct Cluster: Equatable, Sendable {
        /// The folder's path from the Progetto, `""` for the Progetto itself.
        var path: String
        /// The middle of the circle around the whole folder.
        var center: SIMD2<Float>
        var radius: Float
        /// The middle of its core disc, where its own files are; the Progetto's is at the origin.
        var core: SIMD2<Float>
        /// 0 for the Progetto, 1 for its top-level folders.
        var depth: Int
        /// The files in the folder and all its subfolders.
        var fileCount: Int
    }

    /// A file on the plane.
    nonisolated struct Star: Equatable, Sendable {
        /// The file's path from the Progetto.
        var path: String
        var position: SIMD2<Float>
        /// The room each star of its folder has, as a distance on the plane.
        var spacing: Float
        /// The index of its folder in ``clusters``.
        var cluster: Int
    }

    /// The folders, each before its subfolders, in name order; the first is the Progetto.
    var clusters: [Cluster]
    /// The files, folder by folder in the order of ``clusters``, in name order inside each folder.
    var stars: [Star]

    /// The radius of the whole Galassia.
    var radius: Float { clusters.first?.radius ?? 0 }
    /// The middle of the whole Galassia.
    var center: SIMD2<Float> { clusters.first?.center ?? .zero }

    /// The radius of every folder's core disc, where its own files are.
    static let coreRadius: Float = 1
    /// The empty space between two ammassi.
    static let gap: Float = 0.3

    /// Creates the layout of `files`, paths relative to the Progetto separated by `/`.
    ///
    /// - Complexity: O(*n* log *n*) in the number of files and folders.
    init(files: [String]) {
        var builder = Builder()
        for file in Set(files).sorted() { builder.insert(file) }
        builder.sortChildren()
        clusters = []
        stars = []
        let radii = builder.radii()
        // The Progetto's core stays at the origin, wherever the circle around it all falls.
        place(builder, node: 0, at: -radii.core[0], radii: radii)
    }

    private mutating func place(_ builder: Builder, node index: Int, at center: SIMD2<Float>, radii: Radii) {
        let node = builder.nodes[index]
        let cluster = clusters.count
        let core = center + radii.core[index]
        clusters.append(Cluster(path: node.path, center: center, radius: radii.radius[index], core: core,
                                depth: node.depth, fileCount: radii.fileCount[index]))
        let phase = Self.phase(of: node.path)
        let spacing = Self.coreRadius / Float(node.files.count).squareRoot()
        for (offset, file) in node.files.enumerated() {
            // A sunflower inside the core disc: even density whatever the number of files.
            let distance = Self.coreRadius * 0.92 * ((Float(offset) + 0.5) / Float(node.files.count)).squareRoot()
            let angle = phase + Float(offset) * 2.399_963
            stars.append(Star(path: file, position: core + distance * SIMD2(cos(angle), sin(angle)),
                              spacing: spacing, cluster: cluster))
        }
        for child in node.children {
            place(builder, node: child, at: core + radii.offset[child], radii: radii)
        }
    }

    /// A stable angle in [0, 2π) for `path`: the same on every Mac and every launch, unlike `Hasher`.
    static func phase(of path: String) -> Float {
        Float(fnv1a(path) % 6_283) / 1_000
    }

    /// The 64-bit FNV-1a hash of `text`'s UTF-8 bytes.
    static func fnv1a(_ text: String, seed: UInt64 = 0xcbf2_9ce4_8422_2325) -> UInt64 {
        text.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}

nonisolated private extension GalaxyLayout {
    /// The folders of the Progetto as a tree, children and files in name order.
    struct Builder {
        struct Node {
            var path: String
            var depth: Int
            var children: [Int] = []
            var files: [String] = []
        }

        var nodes = [Node(path: "", depth: 0)]
        private var index: [String: Int] = ["": 0]

        /// Puts every folder's subfolders in name order.
        mutating func sortChildren() {
            let paths = nodes.map(\.path)
            for index in nodes.indices {
                nodes[index].children.sort { paths[$0] < paths[$1] }
            }
        }

        /// Adds `file`; files must come in name order, so each folder's files stay in name order.
        mutating func insert(_ file: String) {
            let parts = file.split(separator: "/", omittingEmptySubsequences: true)
            guard !parts.isEmpty else { return }
            var parent = 0
            var path = ""
            for part in parts.dropLast() {
                path = path.isEmpty ? String(part) : path + "/" + part
                if let existing = index[path] {
                    parent = existing
                } else {
                    nodes.append(Node(path: path, depth: nodes[parent].depth + 1))
                    index[path] = nodes.count - 1
                    nodes[parent].children.append(nodes.count - 1)
                    parent = nodes.count - 1
                }
            }
            nodes[parent].files.append(parts.joined(separator: "/"))
        }

        /// Each folder's radius, place inside its parent and number of files, from the leaves up.
        func radii() -> Radii {
            var radii = Radii(count: nodes.count)
            // Children always come after their parent, so the reverse order visits them first.
            for index in nodes.indices.reversed() {
                radii.fileCount[index] = nodes[index].files.count
                    + nodes[index].children.reduce(0) { $0 + radii.fileCount[$1] }
                radii.radius[index] = arrange(index, radii: &radii)
            }
            return radii
        }

        /// Packs the subfolders of `index` around its core disc and returns its radius.
        ///
        /// Each circle keeps half a ``GalaxyLayout/gap`` around it, so neighbours are a whole gap apart. The folder is
        /// the smallest circle around its core and subfolders, so a folder holding one large subfolder is barely
        /// larger than it.
        private func arrange(_ index: Int, radii: inout Radii) -> Float {
            let node = nodes[index]
            let margin = Double(GalaxyLayout.gap) / 2
            let sizes = [Double(GalaxyLayout.coreRadius) + margin]
                + node.children.map { Double(radii.radius[$0]) + margin }
            let centers = CirclePacking.pack(sizes, startingAt: Double(GalaxyLayout.phase(of: node.path)))
            let enclosing = CirclePacking.enclosingCircle(centers: centers, radii: sizes)
            radii.core[index] = SIMD2<Float>(centers[0] - enclosing.center)
            for (offset, child) in node.children.enumerated() {
                radii.offset[child] = SIMD2<Float>(centers[offset + 1])
            }
            return Float(enclosing.radius - margin)
        }
    }

    /// What ``Builder/radii()`` works out, by node.
    struct Radii {
        var radius: [Float]
        /// Where each folder sits from its parent's core.
        var offset: [SIMD2<Float>]
        var fileCount: [Int]
        /// Where the core disc sits from the folder's middle.
        var core: [SIMD2<Float>]

        init(count: Int) {
            radius = Array(repeating: 0, count: count)
            offset = Array(repeating: .zero, count: count)
            fileCount = Array(repeating: 0, count: count)
            core = Array(repeating: .zero, count: count)
        }
    }
}

/// Circles packed tight in order and the smallest circle around them: the front-chain packing and Welzl's algorithm,
/// as d3-hierarchy's `packSiblings` and `packEnclose` do them, in `Double` so a large Progetto stays exact.
nonisolated private enum CirclePacking {
    private struct Circle {
        var center: SIMD2<Double>
        var radius: Double
    }

    /// The centres of circles of `radii` packed in order: the first at the origin, the second touching it at the
    /// angle `phase`, each next one touching two of those before it, as close to the origin as it fits.
    ///
    /// A circle's place depends only on the circles before it.
    static func pack(_ radii: [Double], startingAt phase: Double) -> [SIMD2<Double>] {
        var circles = radii.map { Circle(center: .zero, radius: $0) }
        guard circles.count > 1 else { return circles.map(\.center) }
        circles[1].center = (circles[0].radius + circles[1].radius) * SIMD2(cos(phase), sin(phase))
        guard circles.count > 2 else { return circles.map(\.center) }
        circles[2].center = place(circles[2].radius, touching: circles[1], and: circles[0])
        // The front chain, the circles on the outside, as a ring: from `first` to `second` is where the next one goes.
        var next = Array(repeating: 0, count: circles.count)
        var previous = Array(repeating: 0, count: circles.count)
        (next[0], next[1], next[2]) = (1, 2, 0)
        (previous[1], previous[2], previous[0]) = (0, 1, 2)
        var first = 0
        var second = 1
        // Rounding could make a circle bounce between two places forever: past this many tries, it and the rest go
        // outside. The budget is per circle and grows with its index only, so a circle's place still depends only on
        // the circles before it.
        var index = 3
        var triesLeft = 8 * index + 16
        placing: while index < circles.count {
            circles[index].center = place(circles[index].radius, touching: circles[first], and: circles[second])
            triesLeft -= 1
            guard triesLeft > 0 else { break }
            // Walks the chain both ways from the gap; a circle in the way becomes a side of the gap and it tries again.
            var forward = next[second]
            var backward = previous[first]
            var forwardLength = circles[second].radius
            var backwardLength = circles[first].radius
            repeat {
                if forwardLength <= backwardLength {
                    if intersects(circles[forward], circles[index]) {
                        second = forward
                        (next[first], previous[second]) = (second, first)
                        continue placing
                    }
                    forwardLength += circles[forward].radius
                    forward = next[forward]
                } else {
                    if intersects(circles[backward], circles[index]) {
                        first = backward
                        (next[first], previous[second]) = (second, first)
                        continue placing
                    }
                    backwardLength += circles[backward].radius
                    backward = previous[backward]
                }
            } while forward != next[backward]
            (previous[index], next[index]) = (first, second)
            (next[first], previous[second]) = (index, index)
            // The next gap is the one of the chain closest to the origin.
            var closest = first
            var closestScore = score(circles[first], circles[next[first]])
            var link = next[index]
            while link != index {
                let linkScore = score(circles[link], circles[next[link]])
                if linkScore < closestScore { (closest, closestScore) = (link, linkScore) }
                link = next[link]
            }
            first = closest
            second = next[first]
            index += 1
            triesLeft = 8 * index + 16
        }
        if index < circles.count {
            var reach = circles[..<index].map { simd_length($0.center) + $0.radius }.max() ?? 0
            for rest in index..<circles.count {
                let angle = phase + Double(rest) * 2.399_963
                circles[rest].center = (reach + circles[rest].radius) * SIMD2(cos(angle), sin(angle))
                reach += 2 * circles[rest].radius
            }
        }
        return circles.map(\.center)
    }

    /// The smallest circle around the circles at `centers` with `radii`.
    static func enclosingCircle(centers: [SIMD2<Double>], radii: [Double]) -> (center: SIMD2<Double>, radius: Double) {
        // Farthest first: the circles arrive spiralling outwards, Welzl's worst order, and d3 shuffles them for this.
        // Sorting is deterministic, and the smallest enclosing circle is unique, so the result does not change.
        let circles = zip(centers, radii).map { Circle(center: $0, radius: $1) }
            .sorted { simd_length($0.center) + $0.radius > simd_length($1.center) + $1.radius }
        var basis: [Circle] = []
        var enclosing: Circle?
        var index = 0
        var triesLeft = 8 * circles.count * circles.count + 16
        while index < circles.count, triesLeft > 0 {
            triesLeft -= 1
            let circle = circles[index]
            if let enclosing, enclosesWeakly(enclosing, circle) {
                index += 1
            } else if let extended = extend(basis, with: circle) {
                basis = extended
                enclosing = Self.enclosing(basis)
                index = 0
            } else {
                break
            }
        }
        if let enclosing, index == circles.count { return (enclosing.center, enclosing.radius) }
        // Rounding defeated the search: the circle around the first one's centre always holds them all.
        let center = centers.first ?? .zero
        return (center, circles.map { simd_length($0.center - center) + $0.radius }.max() ?? 0)
    }

    /// Where a circle of `radius` touches both `a` and `b`, on the left going from `b` to `a`.
    private static func place(_ radius: Double, touching a: Circle, and b: Circle) -> SIMD2<Double> {
        let delta = a.center - b.center
        let distance2 = simd_length_squared(delta)
        guard distance2 > 0 else { return b.center + SIMD2(radius, 0) }
        let toB = (b.radius + radius) * (b.radius + radius)
        let toA = (a.radius + radius) * (a.radius + radius)
        if toB > toA {
            let x = (distance2 + toA - toB) / (2 * distance2)
            let y = max(0, toA / distance2 - x * x).squareRoot()
            return SIMD2(a.center.x - x * delta.x - y * delta.y, a.center.y - x * delta.y + y * delta.x)
        }
        let x = (distance2 + toB - toA) / (2 * distance2)
        let y = max(0, toB / distance2 - x * x).squareRoot()
        return SIMD2(b.center.x + x * delta.x - y * delta.y, b.center.y + x * delta.y + y * delta.x)
    }

    private static func intersects(_ a: Circle, _ b: Circle) -> Bool {
        let overlap = a.radius + b.radius - 1e-6
        return overlap > 0 && overlap * overlap > simd_length_squared(b.center - a.center)
    }

    /// How far from the origin the gap after `a` is, squared.
    private static func score(_ a: Circle, _ b: Circle) -> Double {
        simd_length_squared((a.center * b.radius + b.center * a.radius) / (a.radius + b.radius))
    }

    private static func enclosesNot(_ a: Circle, _ b: Circle) -> Bool {
        let room = a.radius - b.radius
        return room < 0 || room * room < simd_length_squared(b.center - a.center)
    }

    private static func enclosesWeakly(_ a: Circle, _ b: Circle) -> Bool {
        let room = a.radius - b.radius + max(a.radius, b.radius, 1) * 1e-9
        return room > 0 && room * room > simd_length_squared(b.center - a.center)
    }

    private static func enclosesWeakly(_ a: Circle, all circles: [Circle]) -> Bool {
        circles.allSatisfy { enclosesWeakly(a, $0) }
    }

    /// The circles, at most three, whose smallest enclosing circle holds `basis` and `circle`.
    private static func extend(_ basis: [Circle], with circle: Circle) -> [Circle]? {
        if enclosesWeakly(circle, all: basis) { return [circle] }
        for one in basis where enclosesNot(circle, one) && enclosesWeakly(enclosing(one, circle), all: basis) {
            return [one, circle]
        }
        for (offset, one) in basis.enumerated() {
            for other in basis.dropFirst(offset + 1)
            where enclosesNot(enclosing(one, other), circle) && enclosesNot(enclosing(one, circle), other)
                && enclosesNot(enclosing(other, circle), one)
                && enclosesWeakly(enclosing(one, other, circle), all: basis) {
                return [one, other, circle]
            }
        }
        return nil
    }

    private static func enclosing(_ basis: [Circle]) -> Circle {
        switch basis.count {
        case 1: basis[0]
        case 2: enclosing(basis[0], basis[1])
        default: enclosing(basis[0], basis[1], basis[2])
        }
    }

    private static func enclosing(_ a: Circle, _ b: Circle) -> Circle {
        let delta = b.center - a.center
        let distance = simd_length(delta)
        return Circle(center: (a.center + b.center + delta / distance * (b.radius - a.radius)) / 2,
                      radius: (distance + a.radius + b.radius) / 2)
    }

    private static func enclosing(_ a: Circle, _ b: Circle, _ c: Circle) -> Circle {
        let (x1, y1, r1) = (a.center.x, a.center.y, a.radius)
        let (x2, y2, r2) = (b.center.x, b.center.y, b.radius)
        let (x3, y3, r3) = (c.center.x, c.center.y, c.radius)
        let (a2, a3, b2, b3) = (x1 - x2, x1 - x3, y1 - y2, y1 - y3)
        let (c2, c3) = (r2 - r1, r3 - r1)
        let d1 = x1 * x1 + y1 * y1 - r1 * r1
        let d2 = d1 - x2 * x2 - y2 * y2 + r2 * r2
        let d3 = d1 - x3 * x3 - y3 * y3 + r3 * r3
        let ab = a3 * b2 - a2 * b3
        let xa = (b2 * d3 - b3 * d2) / (ab * 2) - x1
        let xb = (b3 * c2 - b2 * c3) / ab
        let ya = (a3 * d2 - a2 * d3) / (ab * 2) - y1
        let yb = (a2 * c3 - a3 * c2) / ab
        let qa = xb * xb + yb * yb - 1
        let qb = 2 * (r1 + xa * xb + ya * yb)
        let qc = xa * xa + ya * ya - r1 * r1
        let radius = -(abs(qa) > 1e-6 ? (qb + (qb * qb - 4 * qa * qc).squareRoot()) / (2 * qa) : qc / qb)
        return Circle(center: SIMD2(x1 + xa + xb * radius, y1 + ya + yb * radius), radius: radius)
    }
}
