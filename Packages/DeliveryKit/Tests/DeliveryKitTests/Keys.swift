import CryptoKit
import Foundation

/// Fixed software keys, so the test vectors stay the same from run to run. Test-only: in the app the keys are in the
/// Secure Enclave.
enum Keys {
    static let alice = key(from: 0x01)
    static let bob = key(from: 0x21)
    static let carol = key(from: 0x41)

    /// The key whose scalar is the 32 bytes `first`, `first + 1`, …: valid, far below the order of P-256.
    private static func key(from first: UInt8) -> P256.KeyAgreement.PrivateKey {
        // A 32-byte scalar below the order is always a valid key.
        try! P256.KeyAgreement.PrivateKey(rawRepresentation: Data((0..<32).map { first + $0 }))
    }
}

/// The fixed vectors, computed once with the keys above.
enum Vectors {
    static let aliceKeyID = "4269889431e31319"
    static let bobKeyID = "f6140efc53882371"
    static let aliceBobCode = "687034461133"
    static let header = "4255424f0101f6140efc538823714269889431e313190000010203040506"
    /// "Ciao da Bubo" sealed by Alice for Bob.
    static let sealedFile = """
        4255424f0101f6140efc538823714269889431e31319000000000000000c04f6772c990cbea3382065c2b36174bd4b19b28421911e79c1\
        917980aef660169a9f037f6b92a44f64ddd7825868d50eb65fc5c25a6d346ad3972ec97b9bd9ec45d978404f9befd1bbf303a9c88016dd\
        39511923ebce0f05446b1de81c
        """
}

extension Data {
    /// The bytes of `hex`, two digits each; `nil` when it is not hexadecimal.
    init?(hex: String) {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    /// The bytes in lowercase hexadecimal.
    var hex: String {
        map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
    }
}
