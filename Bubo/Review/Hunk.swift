import CryptoKit
import Foundation

/// A blocco of a diff: lines removed and added together, with the unchanged lines around them.
///
/// A file whose change has no lines to show, such as a binary or a rename, is one blocco without lines.
nonisolated struct Hunk: Identifiable, Equatable, Sendable {
    /// A line of a blocco.
    nonisolated struct Line: Equatable, Sendable {
        /// What happens to the line.
        enum Kind: Sendable {
            case context, added, removed
        }

        var kind: Kind
        /// The line, without the diff's leading `+`, `-` or space.
        var text: String
    }

    /// A row of the side-by-side diff: the line before on the left, the line after on the right.
    nonisolated struct Pair: Equatable, Sendable {
        /// The unchanged or removed line; `nil` where the change only adds.
        var before: Line?
        /// The unchanged or added line; `nil` where the change only removes.
        var after: Line?
    }

    /// Stable while the blocco's file and lines stay the same, wherever it moves in the file.
    let id: String
    /// The `@@` line, or what git says of a change without lines.
    let header: String
    let lines: [Line]
    /// How many lines the blocco adds.
    let added: Int
    /// How many lines the blocco removes.
    let removed: Int
    /// The lines side by side: each removed line next to the line added in its place, unchanged lines on both sides.
    let pairs: [Pair]

    /// Creates the blocco `header` with `lines` in the file at `path`.
    ///
    /// - Parameter occurrence: How many identical blocchi come before it in the file, so each keeps its own id.
    init(path: String, header: String, lines: [Line], occurrence: Int = 0) {
        var hash = SHA256()
        hash.update(data: Data("\(path)\0\(occurrence)\0".utf8))
        if lines.isEmpty { hash.update(data: Data(header.utf8)) }
        for line in lines {
            let mark: UInt8 = switch line.kind {
            case .context: 0x20
            case .added: 0x2B
            case .removed: 0x2D
            }
            var text = line.text
            text.withUTF8 { bytes in
                withUnsafeBytes(of: mark) { hash.update(bufferPointer: $0) }
                hash.update(bufferPointer: UnsafeRawBufferPointer(bytes))
                withUnsafeBytes(of: UInt8(0x0A)) { hash.update(bufferPointer: $0) }
            }
        }
        id = hash.finalize().prefix(12).map { String(format: "%02x", $0) }.joined()
        self.header = header
        self.lines = lines
        added = lines.count { $0.kind == .added }
        removed = lines.count { $0.kind == .removed }
        pairs = Self.pairs(of: lines)
    }

    /// `lines` side by side: a run of removed lines next to the run of added lines that follows it.
    static func pairs(of lines: [Line]) -> [Pair] {
        var pairs: [Pair] = []
        var removed: [Line] = []
        var added: [Line] = []
        func flush() {
            for index in 0..<max(removed.count, added.count) {
                pairs.append(Pair(before: index < removed.count ? removed[index] : nil,
                                  after: index < added.count ? added[index] : nil))
            }
            removed = []
            added = []
        }
        for line in lines {
            switch line.kind {
            case .context:
                flush()
                pairs.append(Pair(before: line, after: line))
            case .removed:
                if !added.isEmpty { flush() }
                removed.append(line)
            case .added:
                added.append(line)
            }
        }
        flush()
        return pairs
    }
}
