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
}
