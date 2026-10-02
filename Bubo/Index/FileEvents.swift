import CoreServices
import Foundation
import Synchronization

/// File events FSEvents delivered together.
nonisolated struct FileEventBatch: Sendable {
    /// The files and folders that changed.
    var paths: [String]
    /// Whether FSEvents merged or lost events, or the watched folder moved: only a full rescan is reliable.
    var needsRescan: Bool
    /// The newest event in the batch, from which a later stream resumes.
    var latestID: FSEventStreamEventId
}

/// File-level FSEvents as an async sequence.
nonisolated enum FileEvents {
    /// The flags after which the events of a batch cannot be trusted one by one.
    static let rescanFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs
        | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
        | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged)

    /// Returns the changes under `root` since the event `since`, first those already recorded, then live ones.
    ///
    /// Ending the iteration stops the stream.
    static func batches(under root: String, since: FSEventStreamEventId,
                        latency: TimeInterval = 1) -> AsyncStream<FileEventBatch> {
        batches(under: [root], since: since, latency: latency)
    }

    /// Returns the changes under any of `roots`, except under `excluded` (at most 8 folders), since the event `since`.
    ///
    /// Ending the iteration stops the stream.
    static func batches(under roots: [String], excluding excluded: [String] = [], since: FSEventStreamEventId,
                        latency: TimeInterval = 1) -> AsyncStream<FileEventBatch> {
        let (batches, continuation) = AsyncStream.makeStream(of: FileEventBatch.self)
        let sink = Sink(continuation)
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer
        // Created inside the lock, so the stream belongs to the sink alone.
        let started = sink.stream.withLock { slot in
            var context = FSEventStreamContext(version: 0, info: Unmanaged.passRetained(sink).toOpaque(),
                                               retain: nil, release: { Unmanaged<Sink>.fromOpaque($0!).release() },
                                               copyDescription: nil)
            guard let stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, ids in
                let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                var needsRescan = false
                for index in 0..<count where flags[index] & FileEvents.rescanFlags != 0 { needsRescan = true }
                Unmanaged<Sink>.fromOpaque(info!).takeUnretainedValue().continuation
                    .yield(FileEventBatch(paths: paths, needsRescan: needsRescan, latestID: ids[count - 1]))
            }, &context, roots as CFArray, since, latency, FSEventStreamCreateFlags(flags)) else {
                Unmanaged<Sink>.fromOpaque(context.info!).release()
                return false
            }
            if !excluded.isEmpty { FSEventStreamSetExclusionPaths(stream, excluded as CFArray) }
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "com.mgiuditta.bubo.file-events", qos: .utility))
            FSEventStreamStart(stream)
            slot = stream
            return true
        }
        guard started else {
            continuation.finish()
            return batches
        }
        continuation.onTermination = { _ in sink.stop() }
        return batches
    }

    /// The receiver of a stream's callbacks, which also owns the stream.
    private final class Sink: Sendable {
        init(_ continuation: AsyncStream<FileEventBatch>.Continuation) {
            self.continuation = continuation
        }

        let continuation: AsyncStream<FileEventBatch>.Continuation
        let stream = Mutex<FSEventStreamRef?>(nil)

        func stop() {
            guard let stream = stream.withLock({ $0.take() }) else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
