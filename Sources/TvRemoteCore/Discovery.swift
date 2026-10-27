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
    /// Other addresses for this same advertisement, when the resolver returned more than one.
    public var addresses: [String]

    public init(name: String, host: String, port: Int, serviceType: String, model: String = "", addresses: [String] = []) {
        self.name = name
        self.host = host
        self.port = port
        self.serviceType = serviceType
        self.model = model
        self.addresses = addresses
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
    /// Extra addresses for the same device. The card uses an IPv4 from here when `host` is not one.
    public var otherHosts: [String]
    /// Label on the Find card. Empty until the list is assembled, then a brand name with no address.
    public var cardTitle: String

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
        legacyAdbPort: Int? = nil,
        otherHosts: [String] = [],
        cardTitle: String = ""
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
        self.otherHosts = otherHosts
        self.cardTitle = cardTitle
    }

    /// Name for the remember step. A placeholder yields the model, then the host.
    public var friendlyName: String {
        if !name.isEmpty, name != host, !Self.placeholderNames.contains(name), !DiscoveryCards.isAnonymous(name) {
            return name
        }
        if !model.isEmpty, !DiscoveryCards.isAnonymous(model) { return model }
        if !cardTitle.isEmpty { return cardTitle }
        if !name.isEmpty, !DiscoveryCards.isAnonymous(name) { return name }
        return DiscoveryCards.baseTitle(self)
    }

    /// Find-step card. Brand and the word TV, never an address or a serial.
    public var listTitle: String {
        if !cardTitle.isEmpty { return cardTitle }
        return DiscoveryCards.baseTitle(self)
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
            for address in endpoint.addresses {
                let extra = address.trimmingCharacters(in: .whitespacesAndNewlines)
                if extra.isEmpty || extra == tv.host || tv.otherHosts.contains(extra) { continue }
                tv.otherHosts.append(extra)
            }
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
    public var neighbours: any NeighbourLooking

    public init(
        listing: any ServiceListing,
        prober: any SubnetProbing,
        localAddresses: [String],
        ssdp: any SsdpSearching = StaticSsdpSearch(found: []),
        portProbe: any HostPortProbing = StaticPortProbe(),
        namer: any TvNaming = EmptyTvNaming(),
        neighbours: any NeighbourLooking = EmptyNeighbourLookup()
    ) {
        self.listing = listing
        self.prober = prober
        self.localAddresses = localAddresses
        self.ssdp = ssdp
        self.portProbe = portProbe
        self.namer = namer
        self.neighbours = neighbours
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
        let named = DiscoveryNaming.apply(outcome.found, namer: namer)
        return DiscoveryOutcome(found: DiscoveryCards.present(named, neighbours: neighbours))
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

public protocol NeighbourLooking {
    /// MAC from the neighbour cache for an IPv6 address. Nil when the cache has no row.
    func mac(forIPv6 host: String) -> String?
    /// IPv4 addresses that share a MAC in the neighbour cache.
    func ipv4s(forMAC mac: String) -> [String]
}

public struct EmptyNeighbourLookup: NeighbourLooking {
    public init() {}
    public func mac(forIPv6 host: String) -> String? { nil }
    public func ipv4s(forMAC mac: String) -> [String] { [] }
}

/// Reads `ndp -an` and `arp -an`. Those print the cache. They do not send a probe.
/// A sandbox that blocks them yields an empty cache, and the card list uses the fallback.
public struct SystemNeighbourLookup: NeighbourLooking {
    public init() {}

    public func mac(forIPv6 host: String) -> String? {
        NeighbourParse.mac(forIPv6: host, ndp: commandOutput("/usr/sbin/ndp", ["-an"]))
    }

    public func ipv4s(forMAC mac: String) -> [String] {
        NeighbourParse.ipv4s(forMAC: mac, arp: commandOutput("/usr/sbin/arp", ["-an"]))
    }

    private func commandOutput(_ path: String, _ args: [String]) -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum NeighbourParse {
    public static func mac(forIPv6 host: String, ndp text: String) -> String? {
        let needle = stripZone(host)
        guard !needle.isEmpty else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let first = fields.first else { continue }
            let address = stripZone(first)
            guard address == needle else { continue }
            if let mac = fields.dropFirst().first(where: { looksLikeMAC($0) }) {
                return normalizeMAC(mac)
            }
        }
        return nil
    }

    public static func ipv4s(forMAC mac: String, arp text: String) -> [String] {
        let wanted = normalizeMAC(mac)
        guard !wanted.isEmpty else { return [] }
        var found: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard line.lowercased().contains(wanted) else { continue }
            guard let address = firstIPv4(in: line), !found.contains(address) else { continue }
            found.append(address)
        }
        return found
    }

    public static func normalizeMAC(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "-", with: ":")
        let parts = cleaned.split(separator: ":").map(String.init)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return "" }
        return parts.joined(separator: ":")
    }

    private static func looksLikeMAC(_ text: String) -> Bool {
        !normalizeMAC(text).isEmpty
    }

    private static func stripZone(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let zone = trimmed.firstIndex(of: "%") else { return trimmed }
        return String(trimmed[..<zone])
    }

    private static func firstIPv4(in text: String) -> String? {
        var token = ""
        func finish() -> String? {
            defer { token = "" }
            return DiscoveryCards.isIPv4(token) ? token : nil
        }
        for character in text {
            if character.isNumber || character == "." {
                token.append(character)
            } else if let address = finish() {
                return address
            }
        }
        return finish()
    }
}

/// One card per television. Addresses stay off the card.
public enum DiscoveryCards {
    public static func present(_ found: [DiscoveredTV], neighbours: any NeighbourLooking = EmptyNeighbourLookup()) -> [DiscoveredTV] {
        let visible = found.filter { !isPhoneOrTablet($0) }
        let enriched = visible.map { enrich($0, neighbours: neighbours) }
        let merged = mergeSameDevice(enriched)
        let kept = hideLooseDebugging(merged)
        let ordered = kept.sorted { left, right in
            let rankLeft = rank(left)
            let rankRight = rank(right)
            if rankLeft != rankRight { return rankLeft < rankRight }
            return left.host < right.host
        }
        return assignTitles(ordered)
    }

    public static func baseTitle(_ tv: DiscoveredTV) -> String {
        switch tv.brand {
        case .sony: return "Sony TV"
        case .xiaomi: return "Xiaomi TV"
        case .generic:
            return isTVClass(tv) ? "Android TV" : "Android device"
        }
    }

    public static func isAnonymous(_ name: String) -> Bool {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }
        if text.lowercased().hasPrefix("adb-") { return true }
        if isIPv4(text) || isIPv6(text) { return true }
        return false
    }

    public static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts.allSatisfy { (0...255).contains($0) } && text.split(separator: ".").count == 4
    }

    public static func isIPv6(_ text: String) -> Bool {
        text.contains(":")
    }

    private static func enrich(_ tv: DiscoveredTV, neighbours: any NeighbourLooking) -> DiscoveredTV {
        var copy = tv
        if copy.macAddress.isEmpty, isLinkLocal(copy.host), let mac = neighbours.mac(forIPv6: copy.host) {
            copy.macAddress = NeighbourParse.normalizeMAC(mac)
        }
        let mac = NeighbourParse.normalizeMAC(copy.macAddress)
        if !mac.isEmpty {
            copy.macAddress = mac
            for address in neighbours.ipv4s(forMAC: mac) where address != copy.host && !copy.otherHosts.contains(address) {
                copy.otherHosts.append(address)
            }
        }
        return copy
    }

    /// (a) MAC, (b) IPv4, (c) any resolved address of the same advertisement, (d) the same hostname.
    private static func mergeSameDevice(_ rows: [DiscoveredTV]) -> [DiscoveredTV] {
        guard !rows.isEmpty else { return [] }
        var parent = Array(rows.indices)
        func find(_ index: Int) -> Int {
            var cursor = index
            while parent[cursor] != cursor { cursor = parent[cursor] }
            return cursor
        }
        func link(_ left: Int, _ right: Int) {
            let rootLeft = find(left)
            let rootRight = find(right)
            if rootLeft != rootRight { parent[rootRight] = rootLeft }
        }
        for left in rows.indices {
            for right in rows.indices where right > left {
                if sameDevice(rows[left], rows[right]) { link(left, right) }
            }
        }
        var groups: [Int: [DiscoveredTV]] = [:]
        for index in rows.indices {
            groups[find(index), default: []].append(rows[index])
        }
        return rows.indices.compactMap { index in
            guard parent[index] == index else { return nil }
            return combine(groups[index] ?? [])
        }
    }

    private static func sameDevice(_ left: DiscoveredTV, _ right: DiscoveredTV) -> Bool {
        let leftMAC = NeighbourParse.normalizeMAC(left.macAddress)
        let rightMAC = NeighbourParse.normalizeMAC(right.macAddress)
        if !leftMAC.isEmpty, leftMAC == rightMAC { return true }
        let shared = Set(ipv4s(left)).intersection(ipv4s(right))
        if !shared.isEmpty { return true }
        if let name = serviceName(left), name == serviceName(right) { return true }
        return false
    }

    private static func ipv4s(_ tv: DiscoveredTV) -> [String] {
        ([tv.host] + tv.otherHosts).filter { isIPv4($0) }
    }

    /// A repeated service name ties two resolutions of one advertisement. Placeholder card names do not.
    private static func serviceName(_ tv: DiscoveredTV) -> String? {
        let name = tv.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = name.lowercased()
        if key.isEmpty || isIPv4(name) || isIPv6(name) { return nil }
        if key == "sony tv" || key == "xiaomi tv" || key == "android tv" || key == "android device" || key == "tv" {
            return nil
        }
        return key
    }

    private static func combine(_ rows: [DiscoveredTV]) -> DiscoveredTV {
        guard var primary = rows.max(by: { score($0) < score($1) }) else {
            return DiscoveredTV(name: "", brand: .generic, host: "", port: 0, controlPort: 0, source: "")
        }
        if let address = rows.flatMap({ ipv4s($0) }).first {
            primary.host = address
        }
        for extra in rows {
            if extra.host != primary.host, !extra.host.isEmpty, !primary.otherHosts.contains(extra.host) {
                primary.otherHosts.append(extra.host)
            }
            for address in extra.otherHosts where address != primary.host && !primary.otherHosts.contains(address) {
                primary.otherHosts.append(address)
            }
            if primary.model.isEmpty { primary.model = extra.model }
            if primary.macAddress.isEmpty { primary.macAddress = extra.macAddress }
            if primary.pairingPort == nil { primary.pairingPort = extra.pairingPort }
            if primary.legacyAdbPort == nil { primary.legacyAdbPort = extra.legacyAdbPort }
            if prefersServiceName(extra.name, over: primary.name) { primary.name = extra.name }
            if isAdbSource(extra.source) {
                if primary.brand == .generic {
                    primary.port = extra.port
                    primary.controlPort = extra.controlPort
                    primary.source = extra.source
                } else if extra.port != 0 {
                    primary.port = extra.port
                }
            }
        }
        primary.cardTitle = ""
        return primary
    }

    private static func score(_ tv: DiscoveredTV) -> Int {
        var value = 0
        switch tv.brand {
        case .sony: value += 30
        case .xiaomi: value += 20
        case .generic: value += 10
        }
        if isTVClass(tv) { value += 5 }
        if isIPv4(tv.host) { value += 1 }
        return value
    }

    private static func prefersServiceName(_ candidate: String, over current: String) -> Bool {
        if isAnonymous(candidate) { return false }
        return isAnonymous(current) || current == "Sony TV" || current == "Xiaomi TV"
    }

    /// An unmatched debugging row is not offered beside a television. It is not folded in without a match.
    private static func hideLooseDebugging(_ rows: [DiscoveredTV]) -> [DiscoveredTV] {
        let televisions = rows.filter { isTVClass($0) }
        guard !televisions.isEmpty else { return rows }
        return rows.filter { isTVClass($0) || !isBareAdb($0) }
    }

    private static func isPhoneOrTablet(_ tv: DiscoveredTV) -> Bool {
        if tv.source == "sony-scan" || tv.source == "xiaomi-scan" || tv.source == "ssdp-scalar" || tv.source == "ssdp-xiaomi" {
            return false
        }
        if DiscoveryService.normalize(tv.source) == DiscoveryService.androidTvRemoteType { return false }
        let tokens = (tv.name + " " + tv.model).lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let markers: Set<String> = ["phone", "phones", "tablet", "tablets", "iphone", "ipad"]
        return tokens.contains { markers.contains($0) }
    }

    static func isTVClass(_ tv: DiscoveredTV) -> Bool {
        if tv.brand == .sony || tv.brand == .xiaomi { return true }
        if tv.source == "sony-scan" || tv.source == "xiaomi-scan" || tv.source.hasPrefix("ssdp-") { return true }
        let type = DiscoveryService.normalize(tv.source)
        return type == DiscoveryService.androidTvRemoteType || type == DiscoveryService.castType
    }

    private static func isBareAdb(_ tv: DiscoveredTV) -> Bool {
        if isTVClass(tv) { return false }
        return isAdbSource(tv.source) || tv.source == "bonjour" || tv.brand == .generic
    }

    private static func isAdbSource(_ source: String) -> Bool {
        switch DiscoveryService.normalize(source) {
        case DiscoveryService.connectType, DiscoveryService.pairingType, DiscoveryService.legacyAdbType:
            return true
        default:
            return false
        }
    }

    private static func isLinkLocal(_ host: String) -> Bool {
        host.lowercased().hasPrefix("fe80:")
    }

    private static func rank(_ tv: DiscoveredTV) -> Int {
        if tv.source == "sony-scan" || tv.source == "ssdp-scalar" || (tv.brand == .sony && tv.source != DiscoveryService.castType) {
            return 0
        }
        let type = DiscoveryService.normalize(tv.source)
        if type == DiscoveryService.androidTvRemoteType || type == DiscoveryService.castType || tv.source == "ssdp-dial" {
            return 1
        }
        if tv.brand == .xiaomi || tv.source == "xiaomi-scan" || tv.source == "ssdp-xiaomi" { return 2 }
        if isBareAdb(tv) { return 4 }
        return 3
    }

    private static func assignTitles(_ rows: [DiscoveredTV]) -> [DiscoveredTV] {
        var seen: [String: Int] = [:]
        return rows.map { tv in
            var copy = tv
            let base = baseTitle(tv)
            let count = seen[base, default: 0] + 1
            seen[base] = count
            copy.cardTitle = count == 1 ? base : "\(base) \(count)"
            return copy
        }
    }
}
