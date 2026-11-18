import Foundation

enum Proto {
    static func varint(_ value: UInt64) -> Data {
        var rest = value
        var bytes = Data()
        while true {
            let piece = UInt8(rest & 0x7f)
            rest >>= 7
            if rest == 0 {
                bytes.append(piece)
                return bytes
            }
            bytes.append(piece | 0x80)
        }
    }

    static func key(_ field: Int, wire: Int) -> Data {
        varint(UInt64((field << 3) | wire))
    }

    static func field(_ number: Int, value: UInt64) -> Data {
        key(number, wire: 0) + varint(value)
    }

    static func field(_ number: Int, bytes: Data) -> Data {
        key(number, wire: 2) + varint(UInt64(bytes.count)) + bytes
    }

    static func field(_ number: Int, text: String) -> Data {
        field(number, bytes: Data(text.utf8))
    }

    static func frame(_ message: Data) -> Data {
        varint(UInt64(message.count)) + message
    }
}

struct ProtoFields {
    var values: [(field: Int, wire: Int, payload: Data)]

    static func parse(_ data: Data) -> ProtoFields {
        var values: [(field: Int, wire: Int, payload: Data)] = []
        var index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            var key: UInt64 = 0
            var shift: UInt64 = 0
            var broken = false
            while index < bytes.count {
                let piece = bytes[index]
                index += 1
                key |= UInt64(piece & 0x7f) << shift
                if piece & 0x80 == 0 { break }
                shift += 7
                if shift > 28 {
                    broken = true
                    break
                }
            }
            if broken { break }
            let field = Int(key >> 3)
            let wire = Int(key & 7)
            switch wire {
            case 0:
                var value: UInt64 = 0
                var valueShift: UInt64 = 0
                var raw = Data()
                while index < bytes.count {
                    let piece = bytes[index]
                    raw.append(piece)
                    index += 1
                    value |= UInt64(piece & 0x7f) << valueShift
                    if piece & 0x80 == 0 { break }
                    valueShift += 7
                }
                values.append((field, wire, raw))
            case 2:
                var length: UInt64 = 0
                var lengthShift: UInt64 = 0
                while index < bytes.count {
                    let piece = bytes[index]
                    index += 1
                    length |= UInt64(piece & 0x7f) << lengthShift
                    if piece & 0x80 == 0 { break }
                    lengthShift += 7
                }
                let end = min(bytes.count, index + Int(length))
                values.append((field, wire, Data(bytes[index..<end])))
                index = end
            default:
                return ProtoFields(values: values)
            }
        }
        return ProtoFields(values: values)
    }

    func uint64(_ field: Int) -> UInt64? {
        guard let raw = values.first(where: { $0.field == field && $0.wire == 0 })?.payload else { return nil }
        var value: UInt64 = 0
        var shift: UInt64 = 0
        for piece in raw {
            value |= UInt64(piece & 0x7f) << shift
            if piece & 0x80 == 0 { break }
            shift += 7
        }
        return value
    }

    func message(_ field: Int) -> Data? {
        values.first(where: { $0.field == field && $0.wire == 2 })?.payload
    }
}
