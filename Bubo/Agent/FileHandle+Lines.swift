import Foundation
import Synchronization

extension FileHandle {
    /// The lines read from this handle until end of file, without their newline.
    ///
    /// Unlike `bytes.lines`, it never blocks a shared thread: `bytes` stalls every other
    /// reader while one pipe stays open and silent, as the bridge's does between answers.
    var lines: AsyncStream<String> {
        let (lines, continuation) = AsyncStream.makeStream(of: String.self)
        let buffer = Mutex(Data())
        readabilityHandler = { handle in
            let chunk = handle.availableData
            buffer.withLock { pending in
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    if !pending.isEmpty { continuation.yield(String(decoding: pending, as: UTF8.self)) }
                    continuation.finish()
                    return
                }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    continuation.yield(String(decoding: pending[..<newline], as: UTF8.self))
                    pending.removeSubrange(...newline)
                }
            }
        }
        return lines
    }
}
