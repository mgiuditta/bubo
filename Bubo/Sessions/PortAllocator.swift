import Darwin

/// Reserves a block of free ports for each Sessione, so the same dev server started in ten Sessioni
/// never collides.
nonisolated struct PortAllocator: Sendable {
    /// How many ports a Sessione gets.
    static let count = 10

    /// The ports handed out, in blocks of `count`: above the usual dev servers (3000, 5173, 8080) and
    /// below the ephemeral ports macOS gives to outgoing connections (49152).
    var range = 40_000..<49_000
    /// Whether nothing listens on a port.
    var isFree: @Sendable (Int) -> Bool = Self.canBind

    /// The first block of `count` ports that are all free and outside `reserved`; `nil` when there is none.
    func ports(avoiding reserved: [Range<Int>]) -> Range<Int>? {
        stride(from: range.lowerBound, through: range.upperBound - Self.count, by: Self.count)
            .lazy
            .map { $0..<($0 + Self.count) }
            .first { block in !reserved.contains { $0.overlaps(block) } && block.allSatisfy(isFree) }
    }

    /// Whether a server could listen on `port` on every IPv4 and IPv6 address.
    static func canBind(_ port: Int) -> Bool {
        var v4 = sockaddr_in()
        v4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        v4.sin_family = sa_family_t(AF_INET)
        v4.sin_port = in_port_t(UInt16(port).bigEndian)
        v4.sin_addr = in_addr(s_addr: INADDR_ANY)
        var v6 = sockaddr_in6()
        v6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        v6.sin6_family = sa_family_t(AF_INET6)
        v6.sin6_port = in_port_t(UInt16(port).bigEndian)
        v6.sin6_addr = in6addr_any
        return canBind(&v4, family: AF_INET) && canBind(&v6, family: AF_INET6)
    }

    private static func canBind<Address>(_ address: inout Address, family: Int32) -> Bool {
        let socket = Darwin.socket(family, SOCK_STREAM, IPPROTO_TCP)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socket, $0, socklen_t(MemoryLayout<Address>.size)) == 0
            }
        }
    }
}
