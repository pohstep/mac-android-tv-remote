import Foundation

public enum AdbAuth {
    public static let sha1DigestInfoPrefix = Data([
        0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14
    ])

    public static func signature(token: Data, modulus: Data, privateExponent: Data) -> Data {
        let info = sha1DigestInfoPrefix + Sha1.hash(token)
        let width = modulus.count
        var encoded = Data([0x00, 0x01])
        let padding = width - info.count - 3
        if padding > 0 {
            encoded.append(Data(repeating: 0xff, count: padding))
        }
        encoded.append(0x00)
        encoded.append(info)
        let signed = AdbInteger(bigEndian: encoded).exponentiating(
            AdbInteger(bigEndian: privateExponent),
            modulus: AdbInteger(bigEndian: modulus)
        )
        return signed.bigEndian(width: width)
    }

    public static func androidPublicKey(modulus: Data, exponent: UInt32, comment: String) -> Data {
        let modulusInt = AdbInteger(bigEndian: modulus)
        let inverse = modInverse32(modulusInt.lowWord())
        let n0inv = 0 &- inverse
        let rr = AdbInteger.one().doubledMod(modulusInt, times: modulus.count * 8 * 2)
        var blob = Data()
        blob.append(uint32(64))
        blob.append(uint32(n0inv))
        blob.append(modulusInt.littleEndian(width: modulus.count))
        blob.append(rr.littleEndian(width: modulus.count))
        blob.append(uint32(exponent))
        let text = blob.base64EncodedString() + " " + comment
        var payload = Data(text.utf8)
        payload.append(0)
        return payload
    }

    private static func uint32(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 4)
    }

    private static func modInverse32(_ value: UInt32) -> UInt32 {
        var t: Int64 = 0
        var nextT: Int64 = 1
        var remainder: Int64 = Int64(1) << 32
        var nextRemainder = Int64(value)
        while nextRemainder != 0 {
            let quotient = remainder / nextRemainder
            let savedT = t
            t = nextT
            nextT = savedT - quotient * nextT
            let savedRemainder = remainder
            remainder = nextRemainder
            nextRemainder = savedRemainder - quotient * nextRemainder
        }
        if t < 0 {
            t += Int64(1) << 32
        }
        return UInt32(t)
    }
}

extension AdbInteger {
    func doubledMod(_ modulus: AdbInteger, times: Int) -> AdbInteger {
        var value = self
        if times <= 0 { return value.mod(modulus) }
        for _ in 0..<times {
            value = value.addingMod(value, modulus: modulus)
        }
        return value
    }
}
