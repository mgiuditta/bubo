import Foundation

/// Which Sessione a listening socket belongs to, without the process tree (spec 15): the one whose folder holds the
/// process's current folder, else the one whose ports include it. Docker and `ssh` tunnels show only in the second
/// case.
nonisolated enum ServerAttribution {
    /// A Sessione that can own servers.
    struct Owner: Sendable {
        let id: UUID
        /// The Sessione's folder, without symbolic links, as the kernel writes current folders.
        let folder: String
        let ports: Range<Int>?

        init(id: UUID, folder: URL, ports: Range<Int>?) {
            self.id = id
            // `realpath`, not `resolvingSymlinksInPath()`, which drops the `/private` the kernel keeps.
            let path = folder.withUnsafeFileSystemRepresentation { name in
                name.flatMap { realpath($0, nil) }.map { resolved in
                    defer { free(resolved) }
                    return String(cString: resolved)
                }
            } ?? folder.path(percentEncoded: false)
            self.folder = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
            self.ports = ports
        }

        /// The open Sessioni with a folder.
        static func of(_ sessions: [Session]) -> [Owner] {
            sessions.compactMap { session in
                guard session.phase == .aperta, let folder = session.workspace?.folder else { return nil }
                return Owner(id: session.id, folder: folder, ports: session.ports)
            }
        }
    }

    /// The Sessione `socket` belongs to among `owners`; `nil` when none.
    ///
    /// The deepest folder wins, so a worktree inside the Progetto beats the Sessione on its checkout.
    static func owner(of socket: ListeningSocket, among owners: [Owner]) -> UUID? {
        if let folder = socket.folder {
            let holders = owners.filter { folder == $0.folder || folder.hasPrefix($0.folder + "/") }
            if let deepest = holders.max(by: { $0.folder.count < $1.folder.count }) { return deepest.id }
        }
        return owners.first { $0.ports?.contains(socket.port) == true }?.id
    }

    /// The sockets of each Sessione among `owners`, by port, IPv4 and IPv6 counted once.
    static func servers(_ sockets: [ListeningSocket], among owners: [Owner]) -> [UUID: [ListeningSocket]] {
        var servers: [UUID: [ListeningSocket]] = [:]
        for socket in sockets {
            guard let id = owner(of: socket, among: owners),
                  servers[id]?.contains(where: { $0.port == socket.port }) != true
            else { continue }
            servers[id, default: []].append(socket)
        }
        return servers.mapValues { $0.sorted { $0.port < $1.port } }
    }
}
