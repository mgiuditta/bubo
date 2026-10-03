import Foundation
import simd

/// Places the notes of a ``NeuronGraph`` on a plane with a force simulation: linked notes pull together, near notes
/// push apart, and everything leans gently to the middle.
///
/// The same graph always gives the same places: a new note starts at a point taken from its path, and the notes
/// already placed stay where they were, so the graph keeps its shape from one opening to the next.
nonisolated enum NeuronLayout {
    /// The length a link pulls its two notes to, in units of the plane.
    static let linkLength: Float = 30
    /// How far a note pushes the others; beyond that, not at all.
    static let reach: Float = 45

    /// Returns the place of each note of `graph`, by index: those in `placed`, by path, stay there; the others are
    /// simulated for `steps` steps.
    static func positions(of graph: NeuronGraph, keeping placed: [String: SIMD2<Float>] = [:],
                          steps: Int = 300) -> [SIMD2<Float>] {
        let notes = graph.notes
        var positions = notes.map { placed[$0.path] ?? .zero }
        let isFixed = notes.map { placed[$0.path] != nil }
        guard isFixed.contains(false) else { return positions }
        var neighbours = Array(repeating: [Int](), count: notes.count)
        for edge in graph.edges {
            neighbours[Int(edge.x)].append(Int(edge.y))
            neighbours[Int(edge.y)].append(Int(edge.x))
        }
        // A new note starts next to a placed neighbour, else on a disc large enough for all of them.
        let spread = linkLength * Float(notes.count).squareRoot()
        for index in notes.indices where !isFixed[index] {
            let seed = seedPoint(of: notes[index].path)
            if let anchor = neighbours[index].first(where: { isFixed[$0] }) {
                positions[index] = positions[anchor] + seed * linkLength
            } else {
                positions[index] = seed * spread
            }
        }
        var velocities = Array(repeating: SIMD2<Float>.zero, count: notes.count)
        // As d3-force: the heat falls from 1 to 0.001 over the steps.
        let decay = 1 - pow(0.001, 1 / Float(max(steps, 1)))
        var heat: Float = 1
        for _ in 0..<steps {
            var forces = repulsion(among: positions)
            for edge in graph.edges {
                let (a, b) = (Int(edge.x), Int(edge.y))
                let offset = positions[b] - positions[a]
                let distance = max(simd_length(offset), 0.01)
                let pull = offset / distance * (distance - linkLength) * 0.1
                forces[a] += pull
                forces[b] -= pull
            }
            for index in notes.indices where !isFixed[index] {
                velocities[index] = (velocities[index] + (forces[index] - positions[index] * 0.002) * heat) * 0.6
                positions[index] += velocities[index]
            }
            heat -= heat * decay
        }
        return positions
    }

    /// The push each note gets from the notes within ``reach``, found through a grid of cells at least as large as
    /// the reach, kept in flat arrays: each note looks only in its cell and the eight around it.
    private static func repulsion(among positions: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let low = positions.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let high = positions.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        // At most 256 cells a side, however far a note strays.
        let size = max(reach, simd_reduce_max(high - low) / 255)
        let columns = Int((high.x - low.x) / size) + 1
        let rows = Int((high.y - low.y) / size) + 1
        let cells = positions.map { point in
            Int((point.x - low.x) / size) + Int((point.y - low.y) / size) * columns
        }
        // The notes of each cell side by side, in index order: a counting sort.
        var starts = Array(repeating: 0, count: columns * rows + 1)
        for cell in cells { starts[cell + 1] += 1 }
        for index in 1..<starts.count { starts[index] += starts[index - 1] }
        var next = starts
        var members = Array(repeating: 0, count: positions.count)
        for (index, cell) in cells.enumerated() {
            members[next[cell]] = index
            next[cell] += 1
        }
        var forces = Array(repeating: SIMD2<Float>.zero, count: positions.count)
        let reachSquared = reach * reach
        for (index, point) in positions.enumerated() {
            let (column, row) = (cells[index] % columns, cells[index] / columns)
            var force = SIMD2<Float>.zero
            for y in max(row - 1, 0)...min(row + 1, rows - 1) {
                for x in max(column - 1, 0)...min(column + 1, columns - 1) {
                    let cell = x + y * columns
                    for slot in starts[cell]..<starts[cell + 1] {
                        let other = members[slot]
                        guard other != index else { continue }
                        var offset = point - positions[other]
                        var squared = simd_length_squared(offset)
                        guard squared < reachSquared else { continue }
                        if squared < 0.01 {
                            // Two notes on the same point part along a direction their indices fix.
                            offset = seedPoint(of: "\(min(index, other)) \(max(index, other))") * (index < other ? 1 : -1)
                            squared = 0.01
                        }
                        force += offset / squared * 200
                    }
                }
            }
            forces[index] = force
        }
        return forces
    }

    /// A point of the unit disc taken from `path` alone.
    static func seedPoint(of path: String) -> SIMD2<Float> {
        let hash = GalaxyLayout.fnv1a(path)
        let angle = Float(hash & 0xffff) / 65_536 * 2 * .pi
        let radius = (Float(hash >> 16 & 0xffff) / 65_536).squareRoot()
        return SIMD2(cos(angle), sin(angle)) * radius
    }
}
