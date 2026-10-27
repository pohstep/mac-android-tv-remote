import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// SSDP M-SEARCH, the public UPnP device-architecture search.
///
/// Sony sets are asked for `urn:schemas-sony-com:service:ScalarWebAPI:1`.
/// A second search uses `ssdp:all` so a Xiaomi set that announces itself as
/// MiTV, or another set that announces an Android TV DIAL device, can be listed.
/// Routers and other root devices are ignored.
///
/// Sandbox: Apple's multicast entitlement is an iOS restriction (TN3179) and is
/// not required on macOS. This process already has `network.client` and
/// `network.server`. Local Network permission still applies. If multicast is
/// blocked, `search()` returns nothing and Bonjour plus the /24 probe still run.
public enum SsdpMessage {
    public static let group = "239.255.255.250"
    public static let port = 1900
    public static let sonyTarget = "urn:schemas-sony-com:service:ScalarWebAPI:1"
    public static let allTarget = "ssdp:all"
    public static let targets = [sonyTarget, allTarget]

    public static func search(target: String, mx: Int = 2) -> String {
        [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(group):\(port)",
            "MAN: \"ssdp:discover\"",
            "MX: \(mx)",
            "ST: \(target)",
            "",
            ""
        ].joined(separator: "\r\n")
    }
}

public enum SsdpRole: Equatable {
    case sony
    case xiaomi
    case androidTV
    case ignore
}

public enum SsdpClassify {
    /// Sony's ScalarWebAPI (or a BRAVIA server banner) wins over a generic TV banner.
    /// Xiaomi is the MiTV / Xiaomi / Redmi banner. Other Android TV DIAL banners stay generic.
    public static func role(server: String, searchTarget: String, usn: String) -> SsdpRole {
        let blob = [server, searchTarget, usn].joined(separator: "\n").lowercased()
        if blob.contains("scalarwebapi") || blob.contains("schemas-sony-com") || blob.contains("bravia") {
            return .sony
        }
        if blob.contains("mitv") || blob.contains("xiaomi") || blob.contains("redmi") {
            return .xiaomi
        }
        let android = blob.contains("android tv") || blob.contains("androidtv") || blob.contains("google tv") || blob.contains("googletv")
        let androidDial = blob.contains("android") && (blob.contains("dial") || blob.contains("mediarenderer") || blob.contains("tv"))
        if android || androidDial {
            return .androidTV
        }
        return .ignore
    }
}

public enum SsdpParse {
    public static func isSearchResponse(_ packet: String) -> Bool {
        let first = packet.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let line = first.uppercased()
        return line.contains("HTTP/") && line.contains("200")
    }

    public static func fields(_ packet: String) -> [String: String] {
        var found: [String: String] = [:]
        for raw in packet.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty || found[key] != nil { continue }
            found[key] = value
        }
        return found
    }

    public static func host(from location: String) -> String? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parts = URLComponents(string: trimmed), let host = parts.host, !host.isEmpty else {
            return nil
        }
        if host == "0.0.0.0" { return nil }
        return host
    }

    /// One candidate from one reply. `sourceHost` is the UDP sender, used when LOCATION has no host.
    public static func television(packet: String, sourceHost: String) -> DiscoveredTV? {
        guard isSearchResponse(packet) else { return nil }
        let header = fields(packet)
        let server = header["server"] ?? ""
        let target = header["st"] ?? ""
        let usn = header["usn"] ?? ""
        let located = host(from: header["location"] ?? "")
        let host = located ?? sourceHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host != "0.0.0.0" else { return nil }
        switch SsdpClassify.role(server: server, searchTarget: target, usn: usn) {
        case .sony:
            return DiscoveredTV(
                name: "Sony TV",
                brand: .sony,
                host: host,
                port: 5555,
                controlPort: 80,
                source: "ssdp-scalar"
            )
        case .xiaomi:
            return DiscoveredTV(
                name: "Xiaomi TV",
                brand: .xiaomi,
                host: host,
                port: 6095,
                controlPort: 6095,
                source: "ssdp-xiaomi"
            )
        case .androidTV:
            return DiscoveredTV(
                name: androidLabel(server: server),
                brand: .generic,
                host: host,
                port: 5555,
                controlPort: 5555,
                source: "ssdp-dial"
            )
        case .ignore:
            return nil
        }
    }

    /// Product token from a SERVER banner, for the list row. "Linux/4.9 UPnP/1.0 Android TV/1.0" → "Android TV".
    public static func androidLabel(server: String) -> String {
        let parts = server.split(separator: " ").map(String.init)
        let product: String
        if let index = parts.firstIndex(where: { $0.lowercased().contains("upnp") }), index + 1 < parts.count {
            product = parts[(index + 1)...].joined(separator: " ")
        } else {
            product = parts.last ?? ""
        }
        let name = product.split(separator: "/").first.map(String.init) ?? product
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("UPnP") == .orderedSame { return "TV" }
        return trimmed
    }
}

public protocol SsdpSearching {
    func search() -> [DiscoveredTV]
}

public struct StaticSsdpSearch: SsdpSearching {
    public var found: [DiscoveredTV]
    public init(found: [DiscoveredTV]) { self.found = found }
    public func search() -> [DiscoveredTV] { found }
}

public struct LiveSsdpSearch: SsdpSearching {
    public var localAddresses: [String]
    public var timeout: TimeInterval

    public init(localAddresses: [String] = [], timeout: TimeInterval = 2.5) {
        self.localAddresses = localAddresses
        self.timeout = timeout
    }

    public func search() -> [DiscoveredTV] {
        let packets = SsdpSocket.collect(localAddresses: localAddresses, timeout: timeout)
        return packets.compactMap { SsdpParse.television(packet: $0.text, sourceHost: $0.sourceHost) }
    }
}

struct SsdpDatagram: Equatable {
    var sourceHost: String
    var text: String
}

enum SsdpSocket {
    static func collect(localAddresses: [String], timeout: TimeInterval) -> [SsdpDatagram] {
        let interfaces = localAddresses.isEmpty ? [""] : localAddresses
        var sockets: [Int32] = []
        for interface in interfaces {
            for target in SsdpMessage.targets {
                if let fd = openSocket(interface: interface, target: target) {
                    sockets.append(fd)
                }
            }
        }
        if sockets.isEmpty, let fd = openSocket(interface: "", target: SsdpMessage.sonyTarget) {
            sockets.append(fd)
        }
        defer { sockets.forEach { close($0) } }
        guard !sockets.isEmpty else { return [] }
        return receive(sockets, timeout: timeout)
    }

    private static func openSocket(interface: String, target: String) -> Int32? {
        let fd = SocketCall.udp()
        guard fd >= 0 else { return nil }
        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        if let address = ipv4(interface) {
            local.sin_addr = address
        } else {
            local.sin_addr.s_addr = inet_addr("0.0.0.0")
        }
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            return nil
        }
        if let address = ipv4(interface) {
            var iface = address
            _ = setsockopt(fd, SocketCall.ipProto, SocketCall.multicastInterface, &iface, socklen_t(MemoryLayout<in_addr>.size))
        }
        setMulticastTTL(fd)
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(SsdpMessage.port).bigEndian
        dest.sin_addr.s_addr = inet_addr(SsdpMessage.group)
        let payload = Array(SsdpMessage.search(target: target).utf8)
        let sent = payload.withUnsafeBytes { buffer -> Int in
            withUnsafePointer(to: &dest) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(fd, buffer.baseAddress, buffer.count, 0, address, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 {
            close(fd)
            return nil
        }
        return fd
    }

    private static func setMulticastTTL(_ fd: Int32) {
        #if os(Linux)
        var ttl: Int32 = 2
        #else
        var ttl: UInt8 = 2
        #endif
        _ = setsockopt(fd, SocketCall.ipProto, SocketCall.multicastTTL, &ttl, socklen_t(MemoryLayout.size(ofValue: ttl)))
    }

    private static func receive(_ sockets: [Int32], timeout: TimeInterval) -> [SsdpDatagram] {
        let deadline = Date().addingTimeInterval(timeout)
        var found: [SsdpDatagram] = []
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            var readSet = fd_set()
            fdZero(&readSet)
            var maxFD: Int32 = 0
            for fd in sockets {
                fdSet(fd, &readSet)
                if fd > maxFD { maxFD = fd }
            }
            var wait = timeval()
            wait.tv_sec = time_t(remaining)
            wait.tv_usec = suseconds_t((remaining - Double(Int(remaining))) * 1_000_000)
            let ready = select(maxFD + 1, &readSet, nil, nil, &wait)
            if ready <= 0 { break }
            for fd in sockets where fdIsSet(fd, &readSet) {
                var buffer = [UInt8](repeating: 0, count: 2048)
                var sender = sockaddr_in()
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = buffer.withUnsafeMutableBytes { raw in
                    withUnsafeMutablePointer(to: &sender) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                            recvfrom(fd, raw.baseAddress, raw.count, 0, address, &length)
                        }
                    }
                }
                guard count > 0 else { continue }
                let text = String(decoding: buffer.prefix(count), as: UTF8.self)
                found.append(SsdpDatagram(sourceHost: addressText(sender.sin_addr), text: text))
            }
        }
        return found
    }

    static func ipv4(_ text: String) -> in_addr? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var address = in_addr()
        let ok = trimmed.withCString { inet_pton(AF_INET, $0, &address) }
        return ok == 1 ? address : nil
    }

    private static func addressText(_ address: in_addr) -> String {
        var copy = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &copy, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return "" }
        return String(cString: buffer)
    }
}

/// Linux Swift does not import the `fd_set` macros, and a few socket constants are a different integer type than Darwin.
private enum SocketCall {
    static func udp() -> Int32 {
        #if os(Linux)
        return socket(AF_INET, Int32(SOCK_DGRAM.rawValue), Int32(IPPROTO_UDP))
        #else
        return socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        #endif
    }

    static func tcp() -> Int32 {
        #if os(Linux)
        return socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        return socket(AF_INET, SOCK_STREAM, 0)
        #endif
    }

    static var ipProto: Int32 {
        #if os(Linux)
        return Int32(IPPROTO_IP)
        #else
        return IPPROTO_IP
        #endif
    }

    static var multicastInterface: Int32 {
        #if os(Linux)
        return Int32(IP_MULTICAST_IF)
        #else
        return IP_MULTICAST_IF
        #endif
    }

    static var multicastTTL: Int32 {
        #if os(Linux)
        return Int32(IP_MULTICAST_TTL)
        #else
        return IP_MULTICAST_TTL
        #endif
    }
}

private func fdZero(_ set: inout fd_set) {
    #if os(Linux)
    withUnsafeMutableBytes(of: &set) { raw in
        raw.initializeMemory(as: UInt8.self, repeating: 0)
    }
    #else
    withUnsafeMutableBytes(of: &set) { raw in
        raw.initializeMemory(as: UInt8.self, repeating: 0)
    }
    #endif
}

private func fdSet(_ fd: Int32, _ set: inout fd_set) {
    #if os(Linux)
    fdWrite(fd, &set) { bits, index, mask in
        bits[index] |= mask
    }
    #else
    withUnsafeMutableBytes(of: &set) { raw in
        let bits = raw.bindMemory(to: Int32.self)
        bits[Int(fd) / 32] |= Int32(truncatingIfNeeded: 1 << (Int(fd) % 32))
    }
    #endif
}

private func fdIsSet(_ fd: Int32, _ set: inout fd_set) -> Bool {
    #if os(Linux)
    var hit = false
    fdWrite(fd, &set) { bits, index, mask in
        hit = bits[index] & mask != 0
    }
    return hit
    #else
    return withUnsafeMutableBytes(of: &set) { raw in
        let bits = raw.bindMemory(to: Int32.self)
        return bits[Int(fd) / 32] & Int32(truncatingIfNeeded: 1 << (Int(fd) % 32)) != 0
    }
    #endif
}

#if os(Linux)
private func fdWrite(_ fd: Int32, _ set: UnsafeMutablePointer<fd_set>, _ body: (UnsafeMutablePointer<Int>, Int, Int) -> Void) {
    set.withMemoryRebound(to: Int.self, capacity: 16) { bits in
        let index = Int(fd) / 64
        let mask = 1 << (Int(fd) % 64)
        body(bits, index, mask)
    }
}
#endif

public protocol HostPortProbing {
    func isOpen(host: String, port: Int) -> Bool
}

public struct StaticPortProbe: HostPortProbing {
    public var open: Set<String>

    public init(open: Set<String> = []) {
        self.open = open
    }

    public func isOpen(host: String, port: Int) -> Bool {
        open.contains("\(host):\(port)")
    }
}

/// Short TCP connect used to notice port 5555 on a set SSDP or Cast already found.
/// The /24 scan does not call this for every address.
public struct LivePortProbe: HostPortProbing {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 0.3) {
        self.timeout = timeout
    }

    public func isOpen(host: String, port: Int) -> Bool {
        guard (1...65535).contains(port), let address = SsdpSocket.ipv4(host) else { return false }
        let fd = SocketCall.tcp()
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { return false }
        guard fcntl(fd, F_SETFL, flags | Int32(O_NONBLOCK)) >= 0 else { return false }
        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(port).bigEndian
        dest.sin_addr = address
        let started = withUnsafePointer(to: &dest) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if started == 0 { return true }
        if errno != EINPROGRESS { return false }
        var writeSet = fd_set()
        fdZero(&writeSet)
        fdSet(fd, &writeSet)
        var wait = timeval()
        let seconds = Int(timeout)
        wait.tv_sec = time_t(seconds)
        wait.tv_usec = suseconds_t(Int((timeout - Double(seconds)) * 1_000_000))
        let ready = select(fd + 1, nil, &writeSet, nil, &wait)
        if ready <= 0 { return false }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
        return error == 0
    }
}
