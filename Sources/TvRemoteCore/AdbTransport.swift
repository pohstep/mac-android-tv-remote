import Foundation

public enum AdbCommand {
    public static let sync: UInt32 = 0x434e5953
    public static let cnxn: UInt32 = 0x4e584e43
    public static let open: UInt32 = 0x4e45504f
    public static let okay: UInt32 = 0x59414b4f
    public static let close: UInt32 = 0x45534c43
    public static let write: UInt32 = 0x45545257
    public static let auth: UInt32 = 0x48545541
    public static let version: UInt32 = 0x01000001
    public static let maxData: UInt32 = 1024 * 1024
    public static let token: UInt32 = 1
    public static let signature: UInt32 = 2
    public static let publicKey: UInt32 = 3
}

public struct AdbPacket: Equatable {
    public var command: UInt32
    public var arg0: UInt32
    public var arg1: UInt32
    public var payload: Data

    public init(command: UInt32, arg0: UInt32, arg1: UInt32, payload: Data) {
        self.command = command
        self.arg0 = arg0
        self.arg1 = arg1
        self.payload = payload
    }

    public func encode(checksum: Bool) -> Data {
        var data = Data()
        data.append(little32(command))
        data.append(little32(arg0))
        data.append(little32(arg1))
        data.append(little32(UInt32(payload.count)))
        data.append(little32(checksum ? AdbPacket.checksum(payload) : 0))
        data.append(little32(command ^ 0xffff_ffff))
        data.append(payload)
        return data
    }

    public static func checksum(_ payload: Data) -> UInt32 {
        payload.reduce(UInt32(0)) { $0 &+ UInt32($1) }
    }

    public static func decode(_ data: Data) -> (packet: AdbPacket, consumed: Int)? {
        guard data.count >= 24 else { return nil }
        let command = uint32(data, 0)
        let arg0 = uint32(data, 4)
        let arg1 = uint32(data, 8)
        let length = Int(uint32(data, 12))
        guard length >= 0, data.count >= 24 + length else { return nil }
        let magic = uint32(data, 20)
        guard magic == (command ^ 0xffff_ffff) else { return nil }
        let payload = data.subdata(in: 24..<(24 + length))
        let check = uint32(data, 16)
        if check != 0 && check != checksum(payload) { return nil }
        return (AdbPacket(command: command, arg0: arg0, arg1: arg1, payload: payload), 24 + length)
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        let bytes = [UInt8](data)
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

public enum AdbWire {
    public static func banner() -> Data {
        Data("host::\0".utf8)
    }

    public static func connect() -> AdbPacket {
        AdbPacket(command: AdbCommand.cnxn, arg0: AdbCommand.version, arg1: AdbCommand.maxData, payload: banner())
    }

    public static func signature(_ signature: Data) -> AdbPacket {
        AdbPacket(command: AdbCommand.auth, arg0: AdbCommand.signature, arg1: 0, payload: signature)
    }

    public static func publicKey(_ key: Data) -> AdbPacket {
        AdbPacket(command: AdbCommand.auth, arg0: AdbCommand.publicKey, arg1: 0, payload: key)
    }

    public static func open(localID: UInt32, destination: String) -> AdbPacket {
        var payload = Data(destination.utf8)
        payload.append(0)
        return AdbPacket(command: AdbCommand.open, arg0: localID, arg1: 0, payload: payload)
    }

    public static func okay(localID: UInt32, remoteID: UInt32) -> AdbPacket {
        AdbPacket(command: AdbCommand.okay, arg0: localID, arg1: remoteID, payload: Data())
    }

    public static func write(localID: UInt32, remoteID: UInt32, payload: Data) -> AdbPacket {
        AdbPacket(command: AdbCommand.write, arg0: localID, arg1: remoteID, payload: payload)
    }
}

private func little32(_ value: UInt32) -> Data {
    var little = value.littleEndian
    return Data(bytes: &little, count: 4)
}
