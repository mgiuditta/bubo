import Darwin

/// A TCP port a process of the user listens on, IPv4 or IPv6, read from the kernel with `libproc` (spec 15).
nonisolated struct ListeningSocket: Hashable, Sendable {
    let pid: pid_t
    let port: Int
    /// The process's current folder; `nil` when the kernel does not say.
    let folder: String?

    /// The ports the user's processes listen on, each once per process, without `lsof` or `ps`: 0.5–3 ms for
    /// some 400 processes.
    static func scan() -> [ListeningSocket] {
        var pids = [pid_t](repeating: 0, count: 4_096)
        let bytes = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, Int32($0.count))
        }
        guard bytes > 0 else { return [] }
        let own = getpid()
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).filter { $0 > 0 && $0 != own }.flatMap { pid in
            let ports = listeningPorts(of: pid)
            guard !ports.isEmpty else { return [ListeningSocket]() }
            let folder = currentFolder(of: pid)
            return ports.sorted().map { ListeningSocket(pid: pid, port: $0, folder: folder) }
        }
    }

    /// The TCP ports `pid` listens on, on any address.
    private static func listeningPorts(of pid: pid_t) -> Set<Int> {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride)
        let read = descriptors.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard read > 0 else { return [] }
        var ports = Set<Int>()
        for descriptor in descriptors.prefix(Int(read) / stride)
        where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == Int32(SOCKINFO_TCP),
                  info.psi.soi_proto.pri_tcp.tcpsi_state == Int32(TSI_S_LISTEN)
            else { continue }
            // In network byte order, in the low 16 bits.
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)))
            if port > 0 { ports.insert(port) }
        }
        return ports
    }

    private static func currentFolder(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }
}
