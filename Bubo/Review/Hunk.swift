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

    /// Stable while the blocco's file and lines stay the same, wherever it moves in the file.
    let id: String
    /// The `@@` line, or what git says of a change without lines.
    let header: String
    let lines: [Line]
    /// How many lines the blocco adds.
    let added: Int
    /// How many lines the blocco removes.
    let removed: Int

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
    }
}
