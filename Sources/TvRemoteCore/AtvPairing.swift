import Foundation

public enum AtvPairingHash {
    public static func exponentBytes(_ exponent: Int) -> Data {
        var hex = String(exponent, radix: 16, uppercase: true)
        hex = "0" + hex
        if hex.count % 2 == 1 {
            hex = "0" + hex
        }
        return Hex.bytes(hex)
    }

    public static func digest(
        clientModulus: Data,
        clientExponent: Data,
        serverModulus: Data,
        serverExponent: Data,
        nonceHex: String
    ) -> Data {
        var material = Data()
        material.append(clientModulus)
        material.append(clientExponent)
        material.append(serverModulus)
        material.append(serverExponent)
        material.append(Hex.bytes(nonceHex))
        return Sha256.hash(material)
    }

    public static func accepts(
        code: String,
        clientModulus: Data,
        clientExponent: Data,
        serverModulus: Data,
        serverExponent: Data
    ) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 6, trimmed.allSatisfy(\.isHexDigit) else { return false }
        let prefix = trimmed.prefix(2)
        let nonce = String(trimmed.dropFirst(2))
        guard let expected = UInt8(prefix, radix: 16) else { return false }
        let digest = digest(
            clientModulus: clientModulus,
            clientExponent: clientExponent,
            serverModulus: serverModulus,
            serverExponent: serverExponent,
            nonceHex: nonce
        )
        return digest.first == expected
    }
}

public enum AtvPairingMessage {
    public static let serviceName = "atvremote"
    public static let clientName = "Zapbar"

    public static func outer(body: Data) -> Data {
        Proto.field(1, value: 2) + Proto.field(2, value: 200) + body
    }

    public static func pairingRequest() -> Data {
        let request = Proto.field(1, text: serviceName) + Proto.field(2, text: clientName)
        return outer(body: Proto.field(10, bytes: request))
    }

    public static func options() -> Data {
        let encoding = Proto.field(1, value: 3) + Proto.field(2, value: 6)
        let options = Proto.field(1, bytes: encoding) + Proto.field(3, value: 1)
        return outer(body: Proto.field(20, bytes: options))
    }

    public static func configuration() -> Data {
        let encoding = Proto.field(1, value: 3) + Proto.field(2, value: 6)
        let configuration = Proto.field(1, bytes: encoding) + Proto.field(2, value: 1)
        return outer(body: Proto.field(30, bytes: configuration))
    }

    public static func secret(_ digest: Data) -> Data {
        outer(body: Proto.field(40, bytes: Proto.field(1, bytes: digest)))
    }

    public static func framedRequest() -> Data {
        Proto.frame(pairingRequest())
    }

    public static func reply(to payload: Data) -> Data? {
        let fields = ProtoFields.parse(payload)
        if fields.message(11) != nil {
            return options()
        }
        if fields.message(20) != nil {
            return configuration()
        }
        if fields.message(31) != nil || fields.message(41) != nil {
            return nil
        }
        return nil
    }
}

enum Hex {
    static func bytes(_ text: String) -> Data {
        let cleaned = text.filter { !$0.isWhitespace }
        let chars = Array(cleaned)
        var out = Data()
        var index = 0
        while index + 1 < chars.count {
            let pair = String(chars[index...index + 1])
            if let byte = UInt8(pair, radix: 16) {
                out.append(byte)
            }
            index += 2
        }
        return out
    }
}
