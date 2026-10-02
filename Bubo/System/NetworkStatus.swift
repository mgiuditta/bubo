import Network

/// Whether the Mac can reach the network right now.
enum NetworkStatus {
    /// Returns `true` when the current network path is usable.
    @concurrent
    static func isOnline() async -> Bool {
        let monitor = NWPathMonitor()
        let (statuses, continuation) = AsyncStream.makeStream(of: NWPath.Status.self)
        monitor.pathUpdateHandler = { continuation.yield($0.status) }
        monitor.start(queue: DispatchQueue(label: "com.mgiuditta.bubo.network-status"))
        defer { monitor.cancel() }
        for await status in statuses {
            return status == .satisfied
        }
        return false
    }

    /// Whether the network path is usable, now and at each change, until the iteration ends.
    static func changes() -> AsyncStream<Bool> {
        let monitor = NWPathMonitor()
        let (statuses, continuation) = AsyncStream.makeStream(of: Bool.self)
        monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
        continuation.onTermination = { _ in monitor.cancel() }
        monitor.start(queue: DispatchQueue(label: "com.mgiuditta.bubo.network-changes"))
        return statuses
    }
}
