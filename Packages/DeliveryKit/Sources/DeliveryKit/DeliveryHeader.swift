import Foundation

/// What a `.bubo` file holds.
public enum DeliveryKind: UInt8, Sendable {
    /// A Sessione, encrypted for one Macchina.
    case consegna = 1
    /// The public key of a Macchina, with the names of its person and Mac; not encrypted.
    case biglietto = 2
}

/// The header in the clear at the start of every `.bubo` file (spec 24, Formato `.bubo`).
///
/// Only what Quick Look and the right error need before decrypting: kind, format version, the two key identifiers
/// and the size of the content. In a Consegna it is associated data of every chunk, so changing it fails the opening.
///
/// Layout, 30 bytes, integers big-endian: `BUBO` · kind (1) · version (1) · recipient key (8) · sender key (8) ·
/// content size (8).
public struct DeliveryHeader: Equatable, Sendable {
    /// What the file holds.
    public var kind: DeliveryKind
    /// The version of the format that wrote the file.
    public var version: UInt8
    /// The key the content is encrypted for; ``KeyID/none`` in a Biglietto.
    public var recipient: KeyID
    /// The key of who made the file: the sender of a Consegna, the key a Biglietto carries.
    public var sender: KeyID
    /// The size of the content in the clear, in bytes.
    public var contentSize: UInt64

    /// The format version this package writes and reads.
    public static let currentVersion: UInt8 = 1
    /// The size of the encoded header, in bytes.
    public static let byteCount = 30
    /// The first 4 bytes of every `.bubo` file.
    public static let magic = Data("BUBO".utf8)

    /// Creates the header of a file in the current format version.
    public init(kind: DeliveryKind, recipient: KeyID, sender: KeyID, contentSize: UInt64) {
        self.kind = kind
        version = Self.currentVersion
        self.recipient = recipient
        self.sender = sender
        self.contentSize = contentSize
    }

    /// Reads the header at the start of `data`; the bytes after it are ignored.
    ///
    /// - Throws: ``DeliveryError/notBubo`` when `data` does not start with a header,
    ///   ``DeliveryError/unsupportedVersion(_:)`` when a newer Bubo wrote it.
    public init(decoding data: Data) throws(DeliveryError) {
        let bytes = Data(data.prefix(Self.byteCount))
        guard bytes.count == Self.byteCount, bytes.prefix(4) == Self.magic else { throw .notBubo }
        guard bytes[5] == Self.currentVersion else { throw .unsupportedVersion(bytes[5]) }
        guard let kind = DeliveryKind(rawValue: bytes[4]),
              let recipient = KeyID(bytes: bytes[6..<14]),
              let sender = KeyID(bytes: bytes[14..<22])
        else { throw .notBubo }
        self.kind = kind
        version = bytes[5]
        self.recipient = recipient
        self.sender = sender
        contentSize = bytes[22..<30].reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// Reads the header of the file at `url`, without reading the rest.
    ///
    /// - Throws: ``DeliveryError/unreadable`` when the file cannot be read, else as ``init(decoding:)``.
    public init(contentsOf url: URL) throws(DeliveryError) {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: Self.byteCount) ?? Data()
        } catch {
            throw .unreadable
        }
        try self.init(decoding: data)
    }

    /// The header's 30 bytes.
    public var encoded: Data {
        var data = Self.magic
        data.append(kind.rawValue)
        data.append(version)
        data.append(recipient.bytes)
        data.append(sender.bytes)
        data.append(contentsOf: (0..<8).reversed().map { UInt8(truncatingIfNeeded: contentSize >> ($0 * 8)) })
        return data
    }
}
