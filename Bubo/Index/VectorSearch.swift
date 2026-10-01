import Accelerate
import Foundation

/// The vectors of the Indice in memory, in half precision, searched exhaustively with Accelerate.
///
/// Each row is the unit-length vector of one fragment, so a dot product is the cosine similarity.
/// 30.000 fragments of 384 dimensions take 23 MB. Half floats are kept as their IEEE 754 bits, as `Float16`
/// does not exist on Intel Macs.
nonisolated struct VectorMatrix: Sendable {
    /// Creates an empty matrix of vectors with `dimension` components.
    init(dimension: Int) {
        self.dimension = dimension
    }

    /// The components of each vector.
    let dimension: Int
    /// The fragment of each row.
    private(set) var rowIDs: [Int64] = []
    private var rows: [Int64: Int] = [:]
    private var storage: [UInt16] = []

    /// The number of vectors.
    var count: Int { rowIDs.count }

    /// Returns the half-precision bits of `vector`, as the matrix and the database keep it.
    static func half(_ vector: [Float]) -> [UInt16] {
        var half = [UInt16](repeating: 0, count: vector.count)
        guard !vector.isEmpty else { return half }
        vector.withUnsafeBufferPointer { single in
            half.withUnsafeMutableBufferPointer { half in
                var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: single.baseAddress!), height: 1,
                                           width: vImagePixelCount(single.count), rowBytes: single.count * 4)
                var destination = vImage_Buffer(data: half.baseAddress!, height: 1,
                                                width: vImagePixelCount(half.count), rowBytes: half.count * 2)
                vImageConvert_PlanarFtoPlanar16F(&source, &destination, vImage_Flags(kvImageNoFlags))
            }
        }
        return half
    }

    /// Stores the half-precision `vector` for the fragment `rowID`, replacing its previous one; a vector of another
    /// size is ignored.
    mutating func insert(_ vector: some Collection<UInt16>, for rowID: Int64) {
        guard vector.count == dimension else { return }
        if let row = rows[rowID] {
            storage.replaceSubrange((row * dimension)..<((row + 1) * dimension), with: vector)
        } else {
            rows[rowID] = rowIDs.count
            rowIDs.append(rowID)
            storage.append(contentsOf: vector)
        }
    }

    /// Forgets the vector of the fragment `rowID`, moving the last row into its place.
    mutating func remove(_ rowID: Int64) {
        guard let row = rows.removeValue(forKey: rowID) else { return }
        let last = rowIDs.count - 1
        if row != last {
            let moved = rowIDs[last]
            rowIDs[row] = moved
            rows[moved] = row
            storage.withUnsafeMutableBufferPointer { buffer in
                for component in 0..<dimension {
                    buffer[row * dimension + component] = buffer[last * dimension + component]
                }
            }
        }
        rowIDs.removeLast()
        storage.removeLast(dimension)
    }

    /// Returns up to `limit` fragments closest to `query`, closest first.
    ///
    /// - Parameter allowed: When given, only these fragments are considered.
    /// - Complexity: O(*n* × *d*), with *n* vectors of *d* components.
    func nearest(to query: [Float], limit: Int, allowed: Set<Int64>? = nil) -> [Int64] {
        guard query.count == dimension, count > 0, limit > 0 else { return [] }
        var scores = [Float](repeating: 0, count: count)
        // Converted to single precision a block at a time, so the copy stays small.
        let block = 4096
        var single = [Float](repeating: 0, count: min(block, count) * dimension)
        storage.withUnsafeBufferPointer { half in
            for start in stride(from: 0, to: count, by: block) {
                let rows = min(block, count - start)
                let elements = rows * dimension
                var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: half.baseAddress! + start * dimension),
                                           height: 1, width: vImagePixelCount(elements), rowBytes: elements * 2)
                single.withUnsafeMutableBufferPointer { single in
                    var destination = vImage_Buffer(data: single.baseAddress!, height: 1,
                                                    width: vImagePixelCount(elements), rowBytes: elements * 4)
                    vImageConvert_Planar16FtoPlanarF(&source, &destination, vImage_Flags(kvImageNoFlags))
                    scores.withUnsafeMutableBufferPointer { scores in
                        // (rows × dimension) · (dimension × 1): one score per row.
                        vDSP_mmul(single.baseAddress!, 1, query, 1, scores.baseAddress! + start, 1,
                                  vDSP_Length(rows), 1, vDSP_Length(dimension))
                    }
                }
            }
        }
        var candidates = Array(0..<count)
        if let allowed { candidates.removeAll { !allowed.contains(rowIDs[$0]) } }
        return candidates.max(count: limit) { scores[$0] < scores[$1] }.map { rowIDs[$0] }
    }
}

/// Reciprocal Rank Fusion: merges rankings made with different scales, such as BM25 and cosine similarity.
nonisolated enum ReciprocalRankFusion {
    /// Returns the items of `rankings`, best first, scored by the sum of 1 / (`k` + rank) over the rankings.
    ///
    /// Ties keep the order in which the items first appear.
    static func fuse<Item: Hashable>(_ rankings: [[Item]], k: Double = 60) -> [Item] {
        var scores: [Item: Double] = [:]
        var order: [Item] = []
        for ranking in rankings {
            for (rank, item) in ranking.enumerated() {
                if scores[item] == nil { order.append(item) }
                scores[item, default: 0] += 1 / (k + Double(rank + 1))
            }
        }
        return order.enumerated().sorted { lhs, rhs in
            let left = scores[lhs.element]!, right = scores[rhs.element]!
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
    }
}

private nonisolated extension Array {
    /// The `count` largest elements by `areInIncreasingOrder`, largest first.
    func max(count: Int, by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        // A small sorted window: k is tiny next to the thousands of fragments.
        var best: [Element] = []
        best.reserveCapacity(count + 1)
        for element in self {
            if best.count == count, let last = best.last, !areInIncreasingOrder(last, element) { continue }
            let index = best.firstIndex { areInIncreasingOrder($0, element) } ?? best.endIndex
            best.insert(element, at: index)
            if best.count > count { best.removeLast() }
        }
        return best
    }
}
