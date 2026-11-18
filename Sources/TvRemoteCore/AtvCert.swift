import Foundation
#if canImport(Security)
import Security

public struct AtvIdentity {
    public var certificate: SecCertificate
    public var key: SecKey
    public var modulus: Data
    public var exponent: Int

    public var certificateDER: Data {
        SecCertificateCopyData(certificate) as Data
    }
}

public enum AtvCertError: Error {
    case key
    case export
    case signature
    case certificate
}

public enum AtvCert {
    public static func generate(commonName: String) throws -> AtvIdentity {
        let tag = Data("app.pohstep.remote.atv.\(commonName)".utf8)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw AtvCertError.key
        }
        guard let publicKey = SecKeyCopyPublicKey(key),
              let exported = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
              let numbers = RsaPublic.numbers(pkcs1: exported) else {
            throw AtvCertError.export
        }
        let certificate = try selfSigned(commonName: commonName, key: key, pkcs1: exported)
        return AtvIdentity(certificate: certificate, key: key, modulus: numbers.modulus, exponent: numbers.exponent)
    }

    private static func selfSigned(commonName: String, key: SecKey, pkcs1: Data) throws -> SecCertificate {
        let now = Date()
        let later = now.addingTimeInterval(60 * 60 * 24 * 365 * 10)
        let spki = Der.sequence(
            Der.sequence(Der.oidRSAEncryption + Der.null()) + Der.bitString(pkcs1)
        )
        let name = distinguished(commonName)
        let tbs = Der.sequence(
            Der.explicit(0, Der.integer(Data([2])))
                + Der.integer(Data([0x01]))
                + Der.sequence(Der.oidSHA256WithRSA)
                + name
                + Der.sequence(Der.utcTime(now) + Der.utcTime(later))
                + name
                + spki
                + Der.explicit(3, Der.sequence(
                    Der.sequence(Der.oidBasicConstraints + Der.octetString(Der.sequence(Der.boolean(true))))
                ))
        )
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, &error) as Data? else {
            throw AtvCertError.signature
        }
        let certificateDER = Der.sequence(
            tbs + Der.sequence(Der.oidSHA256WithRSA) + Der.bitString(signature)
        )
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw AtvCertError.certificate
        }
        return certificate
    }

    private static func distinguished(_ commonName: String) -> Data {
        let attribute = Der.sequence(Der.oidCommonName + Der.utf8(commonName))
        return Der.sequence(Der.set(attribute))
    }
}

enum RsaPublic {
    static func pkcs1(in certificate: Data) -> Data? {
        let bytes = [UInt8](certificate)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x03, let body = Der.read(certificate, at: index, tag: 0x03), body.data.count > 200, body.data.first == 0 {
                let key = Data(body.data.dropFirst())
                if numbers(pkcs1: key) != nil { return key }
            }
            index += 1
        }
        return nil
    }

    static func numbers(pkcs1: Data) -> (modulus: Data, exponent: Int)? {
        guard let body = Der.unwrap(pkcs1, tag: 0x30),
              let modulus = Der.readInteger(body.data, at: 0),
              let exponent = Der.readInteger(body.data, at: modulus.next) else { return nil }
        var magnitude = modulus.bytes
        if magnitude.first == 0 { magnitude.removeFirst() }
        let value = exponent.bytes.reduce(0) { ($0 << 8) | Int($1) }
        return (Data(magnitude), value)
    }
}

enum Der {
    static func sequence(_ contents: Data) -> Data { tagged(0x30, contents) }
    static func set(_ contents: Data) -> Data { tagged(0x31, contents) }
    static func null() -> Data { Data([0x05, 0x00]) }
    static func boolean(_ value: Bool) -> Data { Data([0x01, 0x01, value ? 0xff : 0x00]) }
    static func utf8(_ text: String) -> Data { tagged(0x0c, Data(text.utf8)) }
    static func octetString(_ contents: Data) -> Data { tagged(0x04, contents) }
    static func bitString(_ contents: Data) -> Data { tagged(0x03, Data([0x00]) + contents) }
    static func integer(_ contents: Data) -> Data {
        var body = contents
        if body.first ?? 0 >= 0x80 { body.insert(0x00, at: 0) }
        return tagged(0x02, body)
    }
    static func explicit(_ number: UInt8, _ contents: Data) -> Data {
        tagged(0xa0 | number, contents)
    }
    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tagged(0x17, Data(formatter.string(from: date).utf8))
    }
    static var oidRSAEncryption: Data { tagged(0x06, Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01])) }
    static var oidSHA256WithRSA: Data { tagged(0x06, Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b])) }
    static var oidCommonName: Data { tagged(0x06, Data([0x55, 0x04, 0x03])) }
    static var oidBasicConstraints: Data { tagged(0x06, Data([0x55, 0x1d, 0x13])) }

    static func tagged(_ tag: UInt8, _ body: Data) -> Data {
        Data([tag]) + length(body.count) + body
    }

    static func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var value = count
        var bytes = [UInt8]()
        while value > 0 {
            bytes.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }

    static func unwrap(_ data: Data, tag: UInt8) -> (data: Data, next: Int)? {
        read(data, at: 0, tag: tag)
    }

    static func readInteger(_ data: Data, at offset: Int) -> (bytes: Data, next: Int)? {
        read(data, at: offset, tag: 0x02)
    }

    static func read(_ data: Data, at offset: Int, tag: UInt8) -> (data: Data, next: Int)? {
        let bytes = [UInt8](data)
        guard offset < bytes.count, bytes[offset] == tag else { return nil }
        var index = offset + 1
        guard index < bytes.count else { return nil }
        var length = 0
        if bytes[index] < 0x80 {
            length = Int(bytes[index])
            index += 1
        } else {
            let count = Int(bytes[index] & 0x7f)
            index += 1
            guard count > 0, index + count <= bytes.count else { return nil }
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard index + length <= bytes.count else { return nil }
        return (Data(bytes[index..<(index + length)]), index + length)
    }
}
#endif
