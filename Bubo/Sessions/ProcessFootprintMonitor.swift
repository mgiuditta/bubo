import Darwin
import Foundation

/// Which Sessioni have a heavy `claude`: over 2 GB of footprint, until it falls under 1.5 GB (spec 25).
///
/// It only keeps the readings; ``ProcessInspector`` takes them, without starting any process.
@Observable
final class ProcessFootprintMonitor {
    /// The footprint over which a Sessione is heavy.
    static let heavyFootprint: UInt64 = 2 << 30
    /// The footprint under which a heavy Sessione is light again.
    static let lightFootprint: UInt64 = 3 << 29
    /// How often the footprints are read.
    static let interval = Duration.seconds(30)

    /// The Sessioni whose `claude` is heavy now.
    private(set) var heavySessions: Set<UUID> = []

    /// Records a reading: the footprint of the `claude` of each Sessione at work. A Sessione missing from it is no
    /// longer heavy.
    func record(_ footprints: [UUID: UInt64]) {
        heavySessions = Set(footprints.compactMap { session, footprint in
            let limit = heavySessions.contains(session) ? Self.lightFootprint : Self.heavyFootprint
            return footprint > limit ? session : nil
        })
    }

    /// Forgets the Sessione `id`, whose `claude` exited.
    func forget(_ id: UUID) {
        heavySessions.remove(id)
    }
}

/// Reads processes with `libproc` and `sysctl`: it never starts one.
nonisolated enum ProcessInspector {
    /// The footprint of `pid`, as `footprint` counts it; `nil` when the process is gone.
    static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? info.ri_phys_footprint : nil
    }

    /// The direct children of `pid`.
    static func children(of pid: pid_t) -> [pid_t] {
        var children = [pid_t](repeating: 0, count: 256)
        let count = children.withUnsafeMutableBytes { buffer in
            proc_listchildpids(pid, buffer.baseAddress, Int32(buffer.count))
        }
        return Array(children.prefix(max(0, Int(count))))
    }

    /// The arguments `pid` started with, `argv[0]` first; `nil` when they cannot be read.
    static func arguments(of pid: pid_t) -> [String]? {
        var request = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&request, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&request, 3, &bytes, &size, nil, 0) == 0 else { return nil }
        // `argc`, the executable's path, zeros of padding, then `argc` arguments, each ending with a zero.
        let count = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        let path = bytes[MemoryLayout<Int32>.size..<size]
            .split(separator: 0, maxSplits: 1, omittingEmptySubsequences: false)
        guard path.count == 2, let start = path[1].firstIndex(where: { $0 != 0 }) else { return nil }
        let arguments = bytes[start..<size].split(separator: 0, omittingEmptySubsequences: false).prefix(count)
        return arguments.map { String(decoding: $0, as: UTF8.self) }
    }

    /// The conversation id `claude` was started with, from `--session-id`; `nil` without one.
    static func conversation(in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument.hasPrefix("--session-id=") { return String(argument.dropFirst("--session-id=".count)) }
            if argument == "--session-id", arguments.indices.contains(index + 1) { return arguments[index + 1] }
        }
        return nil
    }

    /// The children of the bridge `pid` that are a `claude`, by the conversation they were started with.
    static func claudeProcesses(of pid: pid_t) -> [String: pid_t] {
        var processes: [String: pid_t] = [:]
        for child in children(of: pid) {
            if let arguments = arguments(of: child), let conversation = conversation(in: arguments) {
                processes[conversation] = child
            }
        }
        return processes
    }
}
