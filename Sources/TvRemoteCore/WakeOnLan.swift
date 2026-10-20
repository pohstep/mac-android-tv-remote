import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum MACAddress {
    public static func bytes(_ raw: String) -> [UInt8]? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard cleaned.count == 12 else { return nil }
        var out: [UInt8] = []
        var index = cleaned.startIndex
        for _ in 0..<6 {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    public static func display(_ raw: String) -> String? {
        guard let bytes = bytes(raw) else { return nil }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

public enum MagicPacket {
    public static func bytes(for mac: [UInt8]) -> [UInt8] {
        precondition(mac.count == 6)
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: mac)
        }
        return packet
    }
}

public protocol WakeOnLanSending {
    func send(mac: String, broadcastHost: String, port: UInt16) throws
}

public struct WakeOnLanSender: WakeOnLanSending {
    public init() {}

    public func send(mac: String, broadcastHost: String, port: UInt16) throws {
        guard let macBytes = MACAddress.bytes(mac) else {
            throw RemoteError.invalidMac(mac)
        }
        let packet = MagicPacket.bytes(for: macBytes)
        try UDPBroadcast.send(packet, host: broadcastHost, port: port)
    }
}

enum UDPBroadcast {
    static func send(_ packet: [UInt8], host: String, port: UInt16) throws {
        #if os(Linux)
        let socketType = Int32(SOCK_DGRAM.rawValue)
        #else
        let socketType = SOCK_DGRAM
        #endif
        let fd = socket(AF_INET, socketType, 0)
        if fd < 0 {
            throw RemoteError.commandFailed("Couldn't open a UDP socket for Wake-on-LAN.")
        }
        defer { close(fd) }

        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        #if os(macOS)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        let parsed = host.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        if parsed != 1 {
            throw RemoteError.invalidBroadcast(host)
        }

        let sent = packet.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(fd, raw.baseAddress, raw.count, 0, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 || sent != packet.count {
            throw RemoteError.commandFailed("Couldn't send the Wake-on-LAN packet (\(String(cString: strerror(errno)))).")
        }
    }
}
