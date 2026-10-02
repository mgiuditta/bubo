import Foundation

/// The version of the Telecomando protocol this build speaks.
///
/// It travels in the pairing QR and in the Device enrollment: a peer with another version cannot pair.
public enum RemoteProtocol {
    /// The current protocol version.
    public static let version = 1
}

extension UUID {
    /// The UUID's 16 bytes, for messages that are signed or fed to a key derivation.
    var bytes: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }
}

extension Data {
    /// `count` cryptographically random bytes, from CryptoKit's generator.
    static func random(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// Appends `field` preceded by its length, so that concatenated fields cannot be confused.
    mutating func appendField(_ field: Data) {
        append(contentsOf: Swift.withUnsafeBytes(of: UInt32(field.count).bigEndian) { Array($0) })
        append(field)
    }
}
