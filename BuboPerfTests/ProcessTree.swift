import Foundation

/// A snapshot of the processes running on the Mac, read with `sysctl`.
nonisolated struct ProcessTree {
    private struct Entry {
        let pid: pid_t
        let parent: pid_t
        let name: String
    }

    private let entries: [Entry]

    /// Takes a snapshot of every process.
    init() throws {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else { throw POSIXError(errno) }
        // Room for processes started between the two calls.
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 16)
        size = processes.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &processes, &size, nil, 0) == 0 else { throw POSIXError(errno) }
        entries = processes.prefix(size / MemoryLayout<kinfo_proc>.stride).map { process in
            let name = withUnsafeBytes(of: process.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return Entry(pid: process.kp_proc.p_pid, parent: process.kp_eproc.e_ppid, name: name)
        }
    }

    /// The names of every process below `ancestor`, at any depth.
    func descendantNames(of ancestor: pid_t) -> [String] {
        var names: [String] = []
        var parents: Set<pid_t> = [ancestor]
        var remaining = entries
        while true {
            let children = remaining.filter { parents.contains($0.parent) }
            guard !children.isEmpty else { return names }
            names += children.map(\.name)
            parents = Set(children.map(\.pid))
            remaining.removeAll { parents.contains($0.pid) }
        }
    }
}

private extension POSIXError {
    init(_ code: Int32) {
        self.init(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
