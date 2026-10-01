import Darwin
import Foundation
import Testing
@testable import Bubo

struct PortAllocatorTests {
    @Test func tenSessionsGetTenBlocksThatNeverOverlap() throws {
        let allocator = PortAllocator(isFree: { _ in true })
        var reserved: [Range<Int>] = []
        for _ in 0..<10 {
            reserved.append(try #require(allocator.ports(avoiding: reserved)))
        }

        #expect(reserved.allSatisfy { $0.count == PortAllocator.count })
        #expect(Set(reserved.flatMap(\.self)).count == 10 * PortAllocator.count)
    }

    /// The spec's "0 conflitti di porta con 10 Sessioni sullo stesso dev server": each listens on its `PORT`.
    @Test func tenDevServersOnTheirSessionsPortListenWithoutConflicts() throws {
        var reserved: [Range<Int>] = []
        var servers: [Int32] = []
        defer { servers.forEach { close($0) } }
        for _ in 0..<10 {
            let ports = try #require(PortAllocator().ports(avoiding: reserved))
            reserved.append(ports)
            let server = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP)
            servers.append(server)
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = in_port_t(UInt16(ports.lowerBound).bigEndian)
            address.sin6_addr = in6addr_any
            let listening = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(server, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0 && listen(server, 1) == 0
                }
            }
            #expect(listening, "PORT \(ports.lowerBound)")
        }
    }

    @Test func aBlockWithABusyPortIsSkipped() {
        let allocator = PortAllocator(isFree: { $0 != 40_003 })
        #expect(allocator.ports(avoiding: []) == 40_010..<40_020)
    }

    @Test func noBlockWhenTheRangeIsTaken() {
        let allocator = PortAllocator(range: 40_000..<40_020, isFree: { _ in true })
        #expect(allocator.ports(avoiding: [40_000..<40_010, 40_010..<40_020]) == nil)
    }

    @Test func aPortWithAServerOnLocalhostIsNotFree() throws {
        let server = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        try #require(server >= 0)
        defer { close(server) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(server, $0, length) == 0 && listen(server, 1) == 0 && getsockname(server, $0, &length) == 0
            }
        }
        try #require(bound)

        #expect(!PortAllocator.canBind(Int(UInt16(bigEndian: address.sin_port))))
    }

    @Test func theRealPortsAreFree() throws {
        let ports = try #require(PortAllocator().ports(avoiding: []))
        #expect(ports.allSatisfy(PortAllocator.canBind))
    }

    @Test func aSessionHandsItsPortsToWhatRunsInIt() {
        var session = Session(id: UUID(), title: "Prova", project: URL(filePath: "/tmp"))
        #expect(session.portEnvironment.isEmpty)

        session.ports = 40_010..<40_020
        #expect(session.portEnvironment == ["PORT": "40010", "BUBO_PORT": "40010", "BUBO_PORTS": "40010-40019"])
    }
}
