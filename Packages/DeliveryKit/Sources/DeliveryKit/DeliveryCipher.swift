import CryptoKit
import Foundation

/// The encryption of a Consegna: HPKE in auth mode, suite P-256, the content in chunks of 1 MiB (spec 24, ADR 0008).
///
/// A sealed file is the ``DeliveryHeader``, the encapsulated key, then the chunks, each 1 MiB plus its 16-byte tag
/// except the last, which is shorter. All the chunks share one HPKE context, so the nonce grows by itself; the
/// associated data of each chunk is the header, the chunk's index and a last-chunk flag. Changing the header,
/// swapping, removing or adding chunks, or cutting the file after any chunk fails the opening.
///
/// The private keys are any `HPKEDiffieHellmanPrivateKey` over P-256: a `SecureEnclave.P256.KeyAgreement.PrivateKey`
/// in the app, so they never leave the Secure Enclave; software keys in the tests.
public enum DeliveryCipher {
    /// The size of every chunk in the clear but the last, in bytes.
    public static let chunkSize = 1 << 20
    /// The HPKE `info`, binding the keys to this use and version.
    public static let info = Data("bubo-consegna-v1".utf8)
    /// The ciphersuite of every Consegna.
    public static let ciphersuite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256
    /// The size of the encapsulated key after the header: a P-256 point in x9.63 uncompressed form.
    public static let encapsulatedKeyByteCount = 65
    /// The size of the AES-GCM tag after each chunk.
    static let tagByteCount = 16

    /// Encrypts the file at `input` for `recipient`, authenticated by `sender`, into a new file at `output`.
    ///
    /// - Returns: The header written at the start of `output`.
    /// - Throws: A file error, or a CryptoKit error from the keys.
    @discardableResult
    public static func seal<Key: HPKEDiffieHellmanPrivateKey>(
        contentsOf input: URL, to output: URL, for recipient: P256.KeyAgreement.PublicKey, from sender: Key
    ) throws -> DeliveryHeader where Key.PublicKey == P256.KeyAgreement.PublicKey {
        let size = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let reader = try FileHandle(forReadingFrom: input)
        defer { try? reader.close() }
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }
        return try seal(size: UInt64(size), read: { try reader.read(upToCount: $0) ?? Data() },
                        write: { try writer.write(contentsOf: $0) }, for: recipient, from: sender)
    }

    /// Encrypts `content` for `recipient`, authenticated by `sender`.
    ///
    /// - Returns: The whole sealed file.
    /// - Throws: A CryptoKit error from the keys.
    public static func seal<Key: HPKEDiffieHellmanPrivateKey>(
        _ content: Data, for recipient: P256.KeyAgreement.PublicKey, from sender: Key
    ) throws -> Data where Key.PublicKey == P256.KeyAgreement.PublicKey {
        var offset = content.startIndex
        var file = Data()
        try seal(size: UInt64(content.count), read: { count in
            let end = content.index(offset, offsetBy: min(count, content.endIndex - offset))
            defer { offset = end }
            return Data(content[offset..<end])
        }, write: { file.append($0) }, for: recipient, from: sender)
        return file
    }

    /// Decrypts the Consegna at `input`, made by `sender`, into a new file at `output`.
    ///
    /// Nothing is left at `output` when the opening fails: a chunk written before the failure is not trusted.
    /// - Returns: The file's header.
    /// - Throws: ``DeliveryError``, checked in this order: not a Consegna, for another key than `recipient`'s,
    ///   from another key than `sender`, then ``DeliveryError/damaged`` when the authentication does not pass.
    @discardableResult
    public static func open<Key: HPKEDiffieHellmanPrivateKey>(
        contentsOf input: URL, to output: URL, with recipient: Key, from sender: P256.KeyAgreement.PublicKey
    ) throws(DeliveryError) -> DeliveryHeader where Key.PublicKey == P256.KeyAgreement.PublicKey {
        let reader: FileHandle
        let writer: FileHandle
        do {
            reader = try FileHandle(forReadingFrom: input)
            guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            writer = try FileHandle(forWritingTo: output)
        } catch {
            throw .unreadable
        }
        defer {
            try? reader.close()
            try? writer.close()
        }
        do {
            return try open(read: { try reader.read(upToCount: $0) ?? Data() }, write: { try writer.write(contentsOf: $0) },
                            with: recipient, from: sender)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    /// Decrypts `file`, a whole Consegna made by `sender`.
    ///
    /// - Returns: The content in the clear.
    /// - Throws: As ``open(contentsOf:to:with:from:)``.
    public static func open<Key: HPKEDiffieHellmanPrivateKey>(
        _ file: Data, with recipient: Key, from sender: P256.KeyAgreement.PublicKey
    ) throws(DeliveryError) -> Data where Key.PublicKey == P256.KeyAgreement.PublicKey {
        var offset = file.startIndex
        var content = Data()
        try open(read: { count in
            let end = file.index(offset, offsetBy: min(count, file.endIndex - offset))
            defer { offset = end }
            return Data(file[offset..<end])
        }, write: { content.append($0) }, with: recipient, from: sender)
        return content
    }

    @discardableResult
    private static func seal<Key: HPKEDiffieHellmanPrivateKey>(
        size: UInt64, read: (Int) throws -> Data, write: (Data) throws -> Void,
        for recipient: P256.KeyAgreement.PublicKey, from sender: Key
    ) throws -> DeliveryHeader where Key.PublicKey == P256.KeyAgreement.PublicKey {
        let header = DeliveryHeader(kind: .consegna, recipient: KeyID(recipient), sender: KeyID(sender.publicKey),
                                    contentSize: size)
        let encoded = header.encoded
        var context = try HPKE.Sender(recipientKey: recipient, ciphersuite: ciphersuite, info: info,
                                      authenticatedBy: sender)
        try write(encoded)
        try write(context.encapsulatedKey)
        let count = chunkCount(for: size)
        for index in 0..<count {
            let chunk = try read(chunkSize)
            let isLast = index == count - 1
            guard chunk.count == (isLast ? Int(size - index * UInt64(chunkSize)) : chunkSize) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try write(context.seal(chunk, authenticating: associatedData(encoded, index: index, isLast: isLast)))
        }
        return header
    }

    @discardableResult
    private static func open<Key: HPKEDiffieHellmanPrivateKey>(
        read: (Int) throws -> Data, write: (Data) throws -> Void,
        with recipient: Key, from sender: P256.KeyAgreement.PublicKey
    ) throws(DeliveryError) -> DeliveryHeader where Key.PublicKey == P256.KeyAgreement.PublicKey {
        let encoded = try readExactly(DeliveryHeader.byteCount, with: read, else: .notBubo)
        let header = try DeliveryHeader(decoding: encoded)
        guard header.kind == .consegna else { throw .wrongKind }
        guard header.recipient == KeyID(recipient.publicKey) else { throw .otherRecipient }
        guard header.sender == KeyID(sender) else { throw .otherSender }
        let encapsulatedKey = try readExactly(encapsulatedKeyByteCount, with: read, else: .damaged)
        var context: HPKE.Recipient
        do {
            context = try HPKE.Recipient(privateKey: recipient, ciphersuite: ciphersuite, info: info,
                                         encapsulatedKey: encapsulatedKey, authenticatedBy: sender)
        } catch {
            throw .damaged
        }
        let count = chunkCount(for: header.contentSize)
        for index in 0..<count {
            let isLast = index == count - 1
            let size = isLast ? Int(header.contentSize - index * UInt64(chunkSize)) : chunkSize
            let sealed = try readExactly(size + tagByteCount, with: read, else: .damaged)
            do {
                try write(context.open(sealed, authenticating: associatedData(encoded, index: index, isLast: isLast)))
            } catch {
                throw .damaged
            }
        }
        // Nothing after the last chunk.
        guard (try? read(1))?.isEmpty == true else { throw .damaged }
        return header
    }

    /// The number of chunks of a content of `size` bytes: at least one, empty when the content is.
    private static func chunkCount(for size: UInt64) -> UInt64 {
        max(1, (size + UInt64(chunkSize) - 1) / UInt64(chunkSize))
    }

    /// The associated data of chunk `index`: the header, the index (8 bytes big-endian) and the last-chunk flag.
    private static func associatedData(_ header: Data, index: UInt64, isLast: Bool) -> Data {
        var data = header
        data.append(contentsOf: (0..<8).reversed().map { UInt8(truncatingIfNeeded: index >> ($0 * 8)) })
        data.append(isLast ? 1 : 0)
        return data
    }

    /// Reads exactly `count` bytes, else throws `error`: the file ends too soon or cannot be read.
    private static func readExactly(_ count: Int, with read: (Int) throws -> Data,
                                    else error: DeliveryError) throws(DeliveryError) -> Data {
        guard let data = try? read(count), data.count == count else { throw error }
        return data
    }
}
