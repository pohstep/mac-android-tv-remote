import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum DiscoveryService {
    public static let connectType = "_adb-tls-connect._tcp"
    public static let pairingType = "_adb-tls-pairing._tcp"
    public static let types = [connectType, pairingType]

    public static func normalize(_ serviceType: String) -> String {
        var type = serviceType.trimmingCharacters(in: .whitespacesAndNewlines)
        while type.hasSuffix(".") { type.removeLast() }
        return type
    }
}

public struct ServiceEndpoint: Equatable {
    public var name: String
    public var host: String
    public var port: Int
    public var serviceType: String

    public init(name: String, host: String, port: Int, serviceType: String) {
        self.name = name
        self.host = host
        self.port = port
        self.serviceType = serviceType
    }
}

public struct DiscoveredTV: Equatable {
    public var name: String
    public var brand: TvBrand
    public var host: String
    public var port: Int
    public var controlPort: Int
    public var pairingPort: Int?
    public var macAddress: String
    public var source: String

    public init(
        name: String,
        brand: TvBrand,
        host: String,
        port: Int,
        controlPort: Int,
        pairingPort: Int? = nil,
        macAddress: String = "",
        source: String
    ) {
        self.name = name
        self.brand = brand
        self.host = host
        self.port = port
        self.controlPort = controlPort
        self.pairingPort = pairingPort
        self.macAddress = macAddress
        self.source = source
    }
}

public struct DiscoveryOutcome: Equatable {
    public var found: [DiscoveredTV]
    /// Manual address entry is always offered, including when the scan finds nothing.
    public var manualEntryAvailable: Bool

    public init(found: [DiscoveredTV], manualEntryAvailable: Bool = true) {
        self.found = found
        self.manualEntryAvailable = true
    }
}

public enum SubnetHosts {
    /// Hosts in the /24 that contains `ipv4`, skipping the address itself, .0, and .255.
    public static func hosts(in ipv4: String) -> [String] {
        let parts = ipv4.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return [] }
        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])"
        return (1...254).compactMap { octet in
            let host = "\(prefix).\(octet)"
            return host == ipv4 ? nil : host
        }
    }
}

public enum IPv4Interfaces {
    public static func addresses() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(first) }
        var found: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var v4 = sockaddr_in()
            memcpy(&v4, address, MemoryLayout<sockaddr_in>.size)
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addr = v4.sin_addr
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ip = String(cString: buffer)
            if ip == "127.0.0.1" || ip.isEmpty || found.contains(ip) { continue }
            found.append(ip)
        }
        return found
    }
}

public enum DiscoveryParse {
    public static func bonjour(_ endpoints: [ServiceEndpoint]) -> [DiscoveredTV] {
        var byHost: [String: DiscoveredTV] = [:]
        for endpoint in endpoints {
            let host = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty, (1...65535).contains(endpoint.port) else { continue }
            let type = DiscoveryService.normalize(endpoint.serviceType)
            var tv = byHost[host] ?? DiscoveredTV(
                name: endpoint.name.isEmpty ? host : endpoint.name,
                brand: .generic,
                host: host,
                port: endpoint.port,
                controlPort: endpoint.port,
                pairingPort: nil,
                macAddress: "",
                source: type
            )
            if type == DiscoveryService.pairingType {
                tv.pairingPort = endpoint.port
            }
            if type == DiscoveryService.connectType {
                tv.port = endpoint.port
                tv.controlPort = endpoint.port
                tv.source = type
                if !endpoint.name.isEmpty { tv.name = endpoint.name }
            }
            if tv.name.isEmpty { tv.name = host }
            byHost[host] = tv
        }
        return byHost.values.sorted { $0.host < $1.host }
    }

    /// Sony IP control on port 80. A JSON-RPC body from getPowerStatus or
    /// getSystemInformation counts, including a forbidden error that still
    /// proves the path is there. HTML and empty bodies do not.
    public static func sony(host: String, status: Int, body: String) -> DiscoveredTV? {
        guard status == 403 || (200...299).contains(status) else { return nil }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let hasResult = json["result"] != nil
        let error = json["error"] as? [Any]
        guard hasResult || error != nil else { return nil }
        let name = stringField(json, keys: ["name", "product", "model"]) ?? host
        let mac = stringField(json, keys: ["macAddr", "mac", "macAddress"]) ?? ""
        return DiscoveredTV(
            name: name,
            brand: .sony,
            host: host,
            port: 5555,
            controlPort: 80,
            macAddress: mac,
            source: "sony-scan"
        )
    }

    /// Community Xiaomi reply from `GET /request?action=isalive` on port 6095.
    public static func xiaomi(host: String, status: Int, body: String) -> DiscoveredTV? {
        guard (200...299).contains(status) else { return nil }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let code = json["status"] as? Int, code != 0 { return nil }
        let payload = json["data"] as? [String: Any]
        let named = (payload?["devicename"] as? String) ?? (payload?["name"] as? String)
        guard json["status"] != nil || named != nil else { return nil }
        let name = named?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DiscoveredTV(
            name: (name?.isEmpty == false ? name! : host),
            brand: .xiaomi,
            host: host,
            port: 6095,
            controlPort: 6095,
            source: "xiaomi-scan"
        )
    }

    public static func deduped(_ sets: [DiscoveredTV]) -> [DiscoveredTV] {
        var ordered: [DiscoveredTV] = []
        for tv in sets {
            if let index = ordered.firstIndex(where: { $0.host == tv.host && $0.brand == tv.brand }) {
                ordered[index] = merge(ordered[index], tv)
            } else {
                ordered.append(tv)
            }
        }
        return ordered
    }

    private static func merge(_ left: DiscoveredTV, _ right: DiscoveredTV) -> DiscoveredTV {
        var tv = left
        if tv.name == tv.host, right.name != right.host { tv.name = right.name }
        if (tv.pairingPort == nil) { tv.pairingPort = right.pairingPort }
        if tv.macAddress.isEmpty { tv.macAddress = right.macAddress }
        if right.source == DiscoveryService.connectType { tv.source = right.source; tv.port = right.port; tv.controlPort = right.controlPort }
        return tv
    }

    private static func stringField(_ json: [String: Any], keys: [String]) -> String? {
        for dict in dictionaries(json) {
            for key in keys {
                if let text = dict[key] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    private static func dictionaries(_ value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            return [dict] + dict.values.flatMap { dictionaries($0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { dictionaries($0) }
        }
        return []
    }
}

public protocol ServiceListing {
    func list() -> [ServiceEndpoint]
}

public struct StaticServiceListing: ServiceListing {
    public var endpoints: [ServiceEndpoint]
    public init(endpoints: [ServiceEndpoint]) { self.endpoints = endpoints }
    public func list() -> [ServiceEndpoint] { endpoints }
}

public protocol SubnetProbing {
    func probe(hosts: [String]) -> [DiscoveredTV]
}

public struct StaticSubnetProbe: SubnetProbing {
    public var found: [DiscoveredTV]
    public init(found: [DiscoveredTV]) { self.found = found }
    public func probe(hosts: [String]) -> [DiscoveredTV] { found }
}

public struct DiscoveryEngine {
    public var serviceEndpoints: [ServiceEndpoint]
    public var localAddresses: [String]
    public var prober: any SubnetProbing

    public init(serviceEndpoints: [ServiceEndpoint], localAddresses: [String], prober: any SubnetProbing) {
        self.serviceEndpoints = serviceEndpoints
        self.localAddresses = localAddresses
        self.prober = prober
    }

    public func find() -> DiscoveryOutcome {
        let fromServices = DiscoveryParse.bonjour(serviceEndpoints)
        let hosts = Array(Set(localAddresses.flatMap { SubnetHosts.hosts(in: $0) })).sorted()
        let fromScan = prober.probe(hosts: hosts)
        return DiscoveryOutcome(found: DiscoveryParse.deduped(fromServices + fromScan))
    }
}

public struct DiscoveryCoordinator {
    public var listing: any ServiceListing
    public var prober: any SubnetProbing
    public var localAddresses: [String]

    public init(listing: any ServiceListing, prober: any SubnetProbing, localAddresses: [String]) {
        self.listing = listing
        self.prober = prober
        self.localAddresses = localAddresses
    }

    public func find() -> DiscoveryOutcome {
        DiscoveryEngine(serviceEndpoints: listing.list(), localAddresses: localAddresses, prober: prober).find()
    }
}

/// Probes a /24 for Sony IP control (port 80) and Xiaomi (port 6095).
/// Inject a `SubnetProbing` fake in tests; this type is the live one.
public struct LiveSubnetProbe: SubnetProbing {
    public var http: any HttpSending
    public var reader: any HttpReading
    public var timeout: TimeInterval

    public init(http: any HttpSending, reader: any HttpReading, timeout: TimeInterval = 0.4) {
        self.http = http
        self.reader = reader
        self.timeout = timeout
    }

    public func probe(hosts: [String]) -> [DiscoveredTV] {
        let lock = NSLock()
        var found: [DiscoveredTV] = []
        let group = DispatchGroup()
        let limit = DispatchSemaphore(value: 32)
        let queue = DispatchQueue(label: "zapbar.discovery", attributes: .concurrent)
        for host in hosts {
            group.enter()
            queue.async {
                limit.wait()
                defer { limit.signal(); group.leave() }
                if let tv = self.probeHost(host) {
                    lock.lock()
                    found.append(tv)
                    lock.unlock()
                }
            }
        }
        _ = group.wait(timeout: .now() + 20)
        return found
    }

    private func probeHost(_ host: String) -> DiscoveredTV? {
        if let xiaomi = probeXiaomi(host) { return xiaomi }
        return probeSony(host)
    }

    private func probeXiaomi(_ host: String) -> DiscoveredTV? {
        guard let url = XiaomiCommand.alive(host: host, port: 6095),
              let reply = try? reader.get(url: url, timeout: timeout) else { return nil }
        let body = String(data: reply.body, encoding: .utf8) ?? ""
        return DiscoveryParse.xiaomi(host: host, status: reply.status, body: body)
    }

    private func probeSony(_ host: String) -> DiscoveredTV? {
        for method in ["getPowerStatus", "getSystemInformation"] {
            guard let url = URL(string: "http://\(host):80/sony/system"),
                  let body = try? JSONSerialization.data(withJSONObject: [
                    "method": method, "params": [], "id": 1, "version": "1.0"
                  ]) else { continue }
            guard let reply = try? http.send(
                url: url,
                headers: ["Content-Type": "application/json"],
                body: body,
                timeout: timeout
            ) else { continue }
            let text = String(data: reply.body, encoding: .utf8) ?? ""
            if let tv = DiscoveryParse.sony(host: host, status: reply.status, body: text) {
                return tv
            }
        }
        return nil
    }
}
