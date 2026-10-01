import Foundation

/// Where every folder and file of a Progetto sits on the Galassia's plane (spec 11).
///
/// A folder is an ammasso: a core disc with its files, ringed by its subfolders in name order. An ammasso's size comes
/// from its subfolders only, never from how many files it holds, so adding or removing files never moves an ammasso:
/// only the stars inside the folder that changed rearrange. The same files always give the same layout.
nonisolated struct GalaxyLayout: Equatable, Sendable {
    /// A folder on the plane.
    nonisolated struct Cluster: Equatable, Sendable {
        /// The folder's path from the Progetto, `""` for the Progetto itself.
        var path: String
        var center: SIMD2<Float>
        var radius: Float
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
        place(builder, node: 0, at: .zero, radii: radii)
    }

    private mutating func place(_ builder: Builder, node index: Int, at center: SIMD2<Float>, radii: Radii) {
        let node = builder.nodes[index]
        let cluster = clusters.count
        clusters.append(Cluster(path: node.path, center: center, radius: radii.radius[index], depth: node.depth,
                                fileCount: radii.fileCount[index]))
        let phase = Self.phase(of: node.path)
        let spacing = Self.coreRadius / Float(node.files.count).squareRoot()
        for (offset, file) in node.files.enumerated() {
            // A sunflower inside the core disc: even density whatever the number of files.
            let distance = Self.coreRadius * 0.92 * ((Float(offset) + 0.5) / Float(node.files.count)).squareRoot()
            let angle = phase + Float(offset) * 2.399_963
            stars.append(Star(path: file, position: center + distance * SIMD2(cos(angle), sin(angle)),
                              spacing: spacing, cluster: cluster))
        }
        for child in node.children {
            place(builder, node: child, at: center + radii.offset[child], radii: radii)
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

        /// Places the subfolders of `index` on rings around its core disc and returns its radius.
        ///
        /// Each subfolder takes, at the inside of its ring, the wedge that contains it; a ring is full when the
        /// wedges reach a whole turn, and the spare angle is shared out evenly.
        private func arrange(_ index: Int, radii: inout Radii) -> Float {
            let node = nodes[index]
            var inner = GalaxyLayout.coreRadius + GalaxyLayout.gap
            var outer = GalaxyLayout.coreRadius
            var ring: [(child: Int, half: Float)] = []
            var phase = GalaxyLayout.phase(of: node.path)

            func halfAngle(_ child: Int) -> Float {
                let radius = radii.radius[child]
                return asin(min(1, (radius + GalaxyLayout.gap / 2) / (inner + radius)))
            }
            func closeRing() {
                guard !ring.isEmpty else { return }
                let spare = (2 * Float.pi - ring.reduce(0) { $0 + 2 * $1.half }) / Float(ring.count)
                var angle = phase
                var reach = inner
                for (child, half) in ring {
                    angle += half
                    let radius = radii.radius[child]
                    radii.offset[child] = (inner + radius) * SIMD2(cos(angle), sin(angle))
                    angle += half + spare
                    reach = max(reach, inner + 2 * radius)
                }
                outer = reach
                inner = reach + GalaxyLayout.gap
                phase += 2.399_963
                ring = []
            }

            var used: Float = 0
            for child in node.children {
                var half = halfAngle(child)
                if !ring.isEmpty, used + 2 * half > 2 * Float.pi {
                    closeRing()
                    used = 0
                    half = halfAngle(child)
                }
                ring.append((child, half))
                used += 2 * half
            }
            closeRing()
            return outer
        }
    }

    /// What ``Builder/radii()`` works out, by node.
    struct Radii {
        var radius: [Float]
        var offset: [SIMD2<Float>]
        var fileCount: [Int]

        init(count: Int) {
            radius = Array(repeating: 0, count: count)
            offset = Array(repeating: .zero, count: count)
            fileCount = Array(repeating: 0, count: count)
        }
    }
}
