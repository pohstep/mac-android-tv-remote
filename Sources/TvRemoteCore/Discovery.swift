import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum DiscoveryService {
    public static let connectType = "_adb-tls-connect._tcp"
    public static let pairingType = "_adb-tls-pairing._tcp"
    /// Older wireless debugging. The port is often 5555.
    public static let legacyAdbType = "_adb._tcp"
    /// Android TV Remote v2. Used for the name and the address, not as a control port.
    public static let androidTvRemoteType = "_androidtvremote2._tcp"
    /// Cast is a hint that a television is present. Speakers are filtered out.
    public static let castType = "_googlecast._tcp"
    public static let types = [connectType, pairingType, legacyAdbType, androidTvRemoteType, castType]

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
    /// Cast TXT `md`, when the browser has it.
    public var model: String

    public init(name: String, host: String, port: Int, serviceType: String, model: String = "") {
        self.name = name
        self.host = host
        self.port = port
        self.serviceType = serviceType
        self.model = model
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
    /// Model from getSystemInformation, Cast TXT, or a DIAL banner. Empty when unknown.
    public var model: String
    /// Port of `_adb._tcp`, or 5555 when that TCP port answered. Nil when debugging was not seen.
    public var legacyAdbPort: Int?

    public init(
        name: String,
        brand: TvBrand,
        host: String,
        port: Int,
        controlPort: Int,
        pairingPort: Int? = nil,
        macAddress: String = "",
        source: String,
        model: String = "",
        legacyAdbPort: Int? = nil
    ) {
        self.name = name
        self.brand = brand
        self.host = host
        self.port = port
        self.controlPort = controlPort
        self.pairingPort = pairingPort
        self.macAddress = macAddress
        self.source = source
        self.model = model
        self.legacyAdbPort = legacyAdbPort
    }

    /// Name for the remember step. A placeholder yields the model, then the host.
    public var friendlyName: String {
        if !name.isEmpty, name != host, !Self.placeholderNames.contains(name) { return name }
        if !model.isEmpty { return model }
        if !name.isEmpty { return name }
        return host
    }

    /// Row label: name, model when it adds something, and the IP.
    public var listTitle: String {
        let label = friendlyName
        let modelText = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelText.isEmpty, modelText.caseInsensitiveCompare(label) != .orderedSame {
            return "\(label) · \(modelText) · \(host)"
        }
        return "\(label) · \(host)"
    }

    private static let placeholderNames: Set<String> = ["Sony TV", "Xiaomi TV"]
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

public enum CastFilter {
    /// Speakers and groups advertise Cast too. A row is kept when the name or model looks like a television.
    public static func include(name: String, model: String) -> Bool {
        let blob = (name + " " + model).lowercased()
        let blocked = ["speaker", "audio", "google home", "nest mini", "nest audio", "nest hub", "group"]
        if blocked.contains(where: { blob.contains($0) }) { return false }
        let allowed = ["tv", "bravia", "xiaomi", "mitv", "redmi", "google tv", "shield", "chromecast", "sony"]
        return allowed.contains(where: { blob.contains($0) })
    }

    public static func suggestsSony(name: String, model: String) -> Bool {
        let blob = (name + " " + model).lowercased()
        return blob.contains("bravia") || blob.contains("sony")
    }
}

public enum DiscoveryParse {
    public static func bonjour(_ endpoints: [ServiceEndpoint]) -> [DiscoveredTV] {
        var byHost: [String: DiscoveredTV] = [:]
        for endpoint in endpoints {
            let host = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty, (1...65535).contains(endpoint.port) else { continue }
            let type = DiscoveryService.normalize(endpoint.serviceType)
            if type == DiscoveryService.castType, !CastFilter.include(name: endpoint.name, model: endpoint.model) {
                continue
            }
            var tv = byHost[host] ?? DiscoveredTV(
                name: host,
                brand: .generic,
                host: host,
                port: 5555,
                controlPort: 5555,
                source: type
            )
            applyService(endpoint, type: type, to: &tv)
            if tv.name.isEmpty { tv.name = host }
            byHost[host] = tv
        }
        return byHost.values.sorted { $0.host < $1.host }
    }

    private static func applyService(_ endpoint: ServiceEndpoint, type: String, to tv: inout DiscoveredTV) {
        if !endpoint.model.isEmpty { tv.model = endpoint.model }
        switch type {
        case DiscoveryService.pairingType:
            tv.pairingPort = endpoint.port
            adoptName(endpoint.name, into: &tv)
        case DiscoveryService.connectType:
            tv.port = endpoint.port
            if tv.brand == .generic { tv.controlPort = endpoint.port }
            tv.source = type
            adoptName(endpoint.name, into: &tv)
        case DiscoveryService.legacyAdbType:
            tv.legacyAdbPort = endpoint.port
            if tv.brand == .generic {
                tv.port = endpoint.port
                tv.controlPort = endpoint.port
            }
            tv.source = type
            adoptName(endpoint.name, into: &tv)
        case DiscoveryService.androidTvRemoteType:
            adoptName(endpoint.name, into: &tv)
            if tv.source != DiscoveryService.connectType && tv.source != DiscoveryService.legacyAdbType {
                tv.source = type
            }
        case DiscoveryService.castType:
            adoptName(endpoint.name, into: &tv)
            if CastFilter.suggestsSony(name: endpoint.name, model: endpoint.model), tv.brand != .xiaomi {
                tv.brand = .sony
                tv.controlPort = 80
            }
            if tv.source != DiscoveryService.connectType && tv.source != DiscoveryService.legacyAdbType {
                tv.source = type
            }
        default:
            break
        }
    }

    private static func adoptName(_ name: String, into tv: inout DiscoveredTV) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if tv.name.isEmpty || tv.name == tv.host { tv.name = trimmed }
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
        let model = stringField(json, keys: ["model"]) ?? ""
        let explicit = stringField(json, keys: ["name"])
        let name = displayName(explicit: explicit, model: model, host: host)
        let mac = stringField(json, keys: ["macAddr", "mac", "macAddress"]) ?? ""
        return DiscoveredTV(
            name: name,
            brand: .sony,
            host: host,
            port: 5555,
            controlPort: 80,
            macAddress: mac,
            source: "sony-scan",
            model: model
        )
    }

    /// Name and model from a getSystemInformation body. Nil when the set did not describe itself.
    public static func sonyIdentity(host: String, status: Int, body: String) -> TvIdentity? {
        guard (200...299).contains(status), let tv = sony(host: host, status: status, body: body) else { return nil }
        if tv.name == host && tv.model.isEmpty && tv.macAddress.isEmpty { return nil }
        return TvIdentity(name: tv.name, model: tv.model, macAddress: tv.macAddress)
    }

    public static func xiaomiIdentity(host: String, status: Int, body: String) -> TvIdentity? {
        guard let tv = xiaomi(host: host, status: status, body: body) else { return nil }
        return TvIdentity(name: tv.name, model: "", macAddress: tv.macAddress)
    }

    private static func displayName(explicit: String?, model: String, host: String) -> String {
        if let explicit {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.caseInsensitiveCompare("TV") != .orderedSame { return trimmed }
        }
        if !model.isEmpty { return model }
        return host
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

    /// One row per host. Sony outranks Xiaomi, which outranks a generic debugging advertisement on the same address.
    public static func deduped(_ sets: [DiscoveredTV]) -> [DiscoveredTV] {
        var ordered: [DiscoveredTV] = []
        for tv in sets {
            if let index = ordered.firstIndex(where: { $0.host == tv.host }) {
                ordered[index] = merge(ordered[index], tv)
            } else {
                ordered.append(tv)
            }
        }
        return ordered
    }

    /// Marks port 5555 when a probe says it is open and `_adb._tcp` did not already name a port.
    public static func noteOpenPorts(_ tvs: [DiscoveredTV], probe: any HostPortProbing) -> [DiscoveredTV] {
        tvs.map { tv in
            var copy = tv
            if copy.legacyAdbPort == nil, probe.isOpen(host: copy.host, port: 5555) {
                copy.legacyAdbPort = 5555
            }
            return copy
        }
    }

    private static func merge(_ left: DiscoveredTV, _ right: DiscoveredTV) -> DiscoveredTV {
        var primary = left
        var extra = right
        if rank(right.brand) > rank(left.brand) {
            primary = right
            extra = left
        }
        if prefersName(extra.name, over: primary.name, host: primary.host) {
            primary.name = extra.name
        }
        if primary.model.isEmpty { primary.model = extra.model }
        if primary.macAddress.isEmpty { primary.macAddress = extra.macAddress }
        if primary.pairingPort == nil { primary.pairingPort = extra.pairingPort }
        if primary.legacyAdbPort == nil { primary.legacyAdbPort = extra.legacyAdbPort }
        if primary.brand == .generic,
           extra.source == DiscoveryService.connectType || extra.source == DiscoveryService.legacyAdbType {
            primary.port = extra.port
            primary.controlPort = extra.controlPort
            primary.source = extra.source
        }
        return primary
    }

    private static func rank(_ brand: TvBrand) -> Int {
        switch brand {
        case .sony: return 3
        case .xiaomi: return 2
        case .generic: return 1
        }
    }

    private static func prefersName(_ candidate: String, over current: String, host: String) -> Bool {
        func useful(_ text: String) -> Bool {
            !text.isEmpty && text != host && text != "Sony TV" && text != "Xiaomi TV"
        }
        guard useful(candidate) else { return false }
        return !useful(current)
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
    public var ssdpFound: [DiscoveredTV]
    public var portProbe: any HostPortProbing

    public init(
        serviceEndpoints: [ServiceEndpoint],
        localAddresses: [String],
        prober: any SubnetProbing,
        ssdpFound: [DiscoveredTV] = [],
        portProbe: any HostPortProbing = StaticPortProbe()
    ) {
        self.serviceEndpoints = serviceEndpoints
        self.localAddresses = localAddresses
        self.prober = prober
        self.ssdpFound = ssdpFound
        self.portProbe = portProbe
    }

    public func find() -> DiscoveryOutcome {
        let fromServices = DiscoveryParse.bonjour(serviceEndpoints)
        let hosts = Array(Set(localAddresses.flatMap { SubnetHosts.hosts(in: $0) })).sorted()
        let fromScan = prober.probe(hosts: hosts)
        let merged = DiscoveryParse.deduped(ssdpFound + fromServices + fromScan)
        return DiscoveryOutcome(found: DiscoveryParse.noteOpenPorts(merged, probe: portProbe))
    }
}

public struct DiscoveryCoordinator {
    public var listing: any ServiceListing
    public var prober: any SubnetProbing
    public var localAddresses: [String]
    public var ssdp: any SsdpSearching
    public var portProbe: any HostPortProbing
    public var namer: any TvNaming

    public init(
        listing: any ServiceListing,
        prober: any SubnetProbing,
        localAddresses: [String],
        ssdp: any SsdpSearching = StaticSsdpSearch(found: []),
        portProbe: any HostPortProbing = StaticPortProbe(),
        namer: any TvNaming = EmptyTvNaming()
    ) {
        self.listing = listing
        self.prober = prober
        self.localAddresses = localAddresses
        self.ssdp = ssdp
        self.portProbe = portProbe
        self.namer = namer
    }

    public func find() -> DiscoveryOutcome {
        let gathered = gather()
        let outcome = DiscoveryEngine(
            serviceEndpoints: gathered.endpoints,
            localAddresses: localAddresses,
            prober: prober,
            ssdpFound: gathered.ssdp,
            portProbe: portProbe
        ).find()
        return DiscoveryOutcome(found: DiscoveryNaming.apply(outcome.found, namer: namer))
    }

    /// Bonjour and SSDP overlap. The /24 probe runs after both, inside `DiscoveryEngine`.
    private func gather() -> (endpoints: [ServiceEndpoint], ssdp: [DiscoveredTV]) {
        let box = GatherBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let endpoints = self.listing.list()
            box.lock.lock()
            box.endpoints = endpoints
            box.lock.unlock()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let found = self.ssdp.search()
            box.lock.lock()
            box.ssdp = found
            box.lock.unlock()
            group.leave()
        }
        group.wait()
        box.lock.lock()
        let snapshot = (endpoints: box.endpoints, ssdp: box.ssdp)
        box.lock.unlock()
        return snapshot
    }
}

private final class GatherBox {
    let lock = NSLock()
    var endpoints: [ServiceEndpoint] = []
    var ssdp: [DiscoveredTV] = []
}

public struct TvIdentity: Equatable {
    public var name: String
    public var model: String
    public var macAddress: String

    public init(name: String, model: String, macAddress: String) {
        self.name = name
        self.model = model
        self.macAddress = macAddress
    }
}

public protocol TvNaming {
    func describe(host: String, brand: TvBrand) -> TvIdentity?
}

public struct EmptyTvNaming: TvNaming {
    public init() {}
    public func describe(host: String, brand: TvBrand) -> TvIdentity? { nil }
}

public enum DiscoveryNaming {
    /// Fills a model or a friendlier name when getSystemInformation or isalive answers.
    /// A name the scan already learned is kept.
    public static func apply(_ found: [DiscoveredTV], namer: any TvNaming) -> [DiscoveredTV] {
        found.map { tv in
            guard tv.brand == .sony || tv.brand == .xiaomi else { return tv }
            guard let identity = namer.describe(host: tv.host, brand: tv.brand) else { return tv }
            var copy = tv
            if prefersDescribedName(identity.name, over: copy.name, host: copy.host) {
                copy.name = identity.name
            }
            if copy.model.isEmpty, !identity.model.isEmpty { copy.model = identity.model }
            if copy.macAddress.isEmpty { copy.macAddress = identity.macAddress }
            if (copy.name == copy.host || copy.name == "Sony TV" || copy.name == "Xiaomi TV"), !copy.model.isEmpty {
                copy.name = copy.model
            }
            return copy
        }
    }

    private static func prefersDescribedName(_ candidate: String, over current: String, host: String) -> Bool {
        let useful = !candidate.isEmpty && candidate != host && candidate != "Sony TV" && candidate != "Xiaomi TV"
        guard useful else { return false }
        if current.isEmpty || current == host || current == "Sony TV" || current == "Xiaomi TV" { return true }
        return false
    }
}

public struct LiveTvNaming: TvNaming {
    public var http: any HttpSending
    public var reader: any HttpReading
    public var timeout: TimeInterval

    public init(http: any HttpSending, reader: any HttpReading, timeout: TimeInterval = 0.8) {
        self.http = http
        self.reader = reader
        self.timeout = timeout
    }

    public func describe(host: String, brand: TvBrand) -> TvIdentity? {
        switch brand {
        case .sony:
            return sony(host)
        case .xiaomi:
            return xiaomi(host)
        case .generic:
            return nil
        }
    }

    private func sony(_ host: String) -> TvIdentity? {
        guard let url = SonyURL.make(host: host, port: 80, path: "/sony/system"),
              let body = try? JSONSerialization.data(withJSONObject: [
                "method": "getSystemInformation", "params": [], "id": 1, "version": "1.0"
              ]),
              let reply = try? http.send(
                url: url,
                headers: ["Content-Type": "application/json"],
                body: body,
                timeout: timeout
              ) else { return nil }
        let text = String(data: reply.body, encoding: .utf8) ?? ""
        return DiscoveryParse.sonyIdentity(host: host, status: reply.status, body: text)
    }

    private func xiaomi(_ host: String) -> TvIdentity? {
        guard let url = XiaomiCommand.alive(host: host, port: 6095),
              let reply = try? reader.get(url: url, timeout: timeout) else { return nil }
        let text = String(data: reply.body, encoding: .utf8) ?? ""
        return DiscoveryParse.xiaomiIdentity(host: host, status: reply.status, body: text)
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
