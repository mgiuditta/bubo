/// Runs the commands that change the plugins one at a time, in the order they arrive (spec 20).
///
/// Two `claude` writing together have corrupted `~/.claude.json` before: one queue for the whole app, so two windows
/// or two clicks wait their turn.
actor PluginWriteQueue {
    /// The queue of the whole app.
    static let shared = PluginWriteQueue()

    /// The last operation queued; the next one starts after it ends.
    private var tail: Task<Void, Never>?

    /// Runs `operation` after every operation queued before it, and returns its result.
    ///
    /// Cancelling the caller cancels `operation`, also while it is still waiting its turn: it then never starts.
    ///
    /// - Throws: What `operation` throws, or `CancellationError`.
    func enqueue<Result: Sendable>(_ operation: @escaping @Sendable () async throws -> Result) async throws -> Result {
        let previous = tail
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        tail = Task { _ = await task.result }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
