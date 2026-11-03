// Adapted from nikships/dyson-zone-companion (MIT License, Copyright (c) 2026 Nik).
// https://github.com/nikships/dyson-zone-companion  — Dyson LTK handshake crypto.
import CommonCrypto
import CryptoKit
import Foundation

/// The Dyson LTK handshake: an AES-128 key derived from the long-term key with HKDF-SHA256,
/// then unpadded AES-CBC with an HMAC-SHA256 over the ciphertext (encrypt-then-MAC, same key).
enum ZoneCrypto {
    private static let authInfo = Data("USER_AUTH_AES".utf8) + Data([0, 0, 0])
    private static let block = 16

    static func deriveAuthKey(ltk: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ltk),
            salt: Data(),
            info: authInfo,
            outputByteCount: block
        )
    }

    /// `IV(16) || AES-128-CBC(key, IV, plaintext) || HMAC-SHA256(key, ciphertext)`
    static func seal(key: SymmetricKey, plaintext: Data, iv: Data = randomBytes(16)) -> Data {
        let ct = aesCBC(encrypt: true, key: key, iv: iv, data: plaintext) ?? Data()
        return iv + ct + mac(key: key, over: ct)
    }

    static func reauthPayloadA(accountId: String, key: SymmetricKey, nonce: Data) -> Data? {
        guard let guid = uuidBytes(accountId) else { return nil }
        return guid + Data([0, 0]) + seal(key: key, plaintext: nonce)
    }

    static func reauthPayloadC(key: SymmetricKey, challenge: Data) -> Data {
        Data([0, 0]) + seal(key: key, plaintext: challenge)
    }

    /// Payload B is `00 00 || IV(16) || ciphertext(32) || MAC(32)`. The plaintext is our nonce
    /// followed by the headphones' own challenge, which is what we return.
    static func challenge(fromPayloadB payload: Data, key: SymmetricKey) -> Data? {
        guard payload.count >= 50 else { return nil }
        let iv = payload.subdata(in: 2..<18)
        let ct = payload.subdata(in: 18..<50)
        if payload.count >= 82 {
            let received = payload.subdata(in: 50..<82)
            guard received == mac(key: key, over: ct) else { return nil }
        }
        guard let plain = aesCBC(encrypt: false, key: key, iv: iv, data: ct), plain.count >= 32 else { return nil }
        return plain.subdata(in: 16..<32)
    }

    static func randomBytes(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    private static func mac(key: SymmetricKey, over data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    /// Dyson sends account GUIDs in RFC 4122 (big-endian) byte order.
    static func uuidBytes(_ uuid: String) -> Data? {
        let hex = uuid.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32 else { return nil }
        return Data(hexString: hex)
    }

    private static func aesCBC(encrypt: Bool, key: SymmetricKey, iv: Data, data: Data) -> Data? {
        let keyBytes = key.withUnsafeBytes { Array($0) }
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                iv.withUnsafeBytes { ivPtr in
                    CCCrypt(
                        CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        0,
                        keyBytes, keyBytes.count,
                        ivPtr.baseAddress,
                        inPtr.baseAddress, data.count,
                        outPtr.baseAddress, outPtr.count,
                        &moved
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return out.prefix(moved)
    }
}

extension Data {
    init?(hexString: String) {
        let chars = Array(hexString.filter { $0.isHexDigit })
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let byte = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            bytes.append(byte)
            i += 2
        }
        self.init(bytes)
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
