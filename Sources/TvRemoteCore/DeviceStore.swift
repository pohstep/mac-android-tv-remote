import Foundation

public enum TvBrand: String, Codable, Equatable {
    case sony
    case generic
    case xiaomi
}

public struct StoredTV: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var brand: TvBrand
    public var host: String
    public var port: Int
    public var macAddress: String
    public var lastSeen: Date?
    public var preferred: Bool
    /// Sony IP control port, or the Xiaomi control port. Debugging uses `port`.
    public var controlPort: Int
    public var useDebugging: Bool

    public init(
        id: String,
        name: String,
        brand: TvBrand,
        host: String,
        port: Int,
        macAddress: String = "",
        lastSeen: Date? = nil,
        preferred: Bool = false,
        controlPort: Int? = nil,
        useDebugging: Bool = true
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.host = host
        self.port = port
        self.macAddress = macAddress
        self.lastSeen = lastSeen
        self.preferred = preferred
        self.controlPort = controlPort ?? (brand == .sony ? 80 : port)
        self.useDebugging = useDebugging
    }

    /// v1.0 stored one TV on the settings object. The id stays `legacy` so the
    /// existing Keychain item can be matched after upgrade.
    public static func migrateLegacy(host: String, port: Int, macAddress: String, controlPort: Int) -> [StoredTV] {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [
            StoredTV(
                id: "legacy",
                name: trimmed,
                brand: .sony,
                host: trimmed,
                port: port,
                macAddress: macAddress,
                lastSeen: nil,
                preferred: true,
                controlPort: controlPort,
                useDebugging: true
            )
        ]
    }
}

public struct DeviceSwitcher: Equatable {
    public var devices: [StoredTV]
    public var activeID: String

    public init(devices: [StoredTV], activeID: String) {
        self.devices = devices
        self.activeID = activeID
    }

    public func active() -> StoredTV? {
        if let match = devices.first(where: { $0.id == activeID }) { return match }
        return devices.first
    }

    /// Last TV used, then the most recently seen, then the preferred set, then the first.
    public func reconnectTarget() -> StoredTV? {
        if let active = devices.first(where: { $0.id == activeID }) { return active }
        let recent = devices.compactMap { device -> (StoredTV, Date)? in
            guard let seen = device.lastSeen else { return nil }
            return (device, seen)
        }.sorted { $0.1 > $1.1 }
        if let latest = recent.first?.0 { return latest }
        if let preferred = devices.first(where: \.preferred) { return preferred }
        return devices.first
    }

    public mutating func select(_ id: String, seenAt date: Date) {
        guard devices.contains(where: { $0.id == id }) else { return }
        activeID = id
        touch(id, date: date)
    }

    public mutating func remember(_ device: StoredTV, seenAt date: Date) {
        var next = device
        next.lastSeen = date
        if devices.isEmpty {
            next.preferred = true
        }
        if let index = devices.firstIndex(where: { $0.id == next.id || ($0.host == next.host && $0.brand == next.brand) }) {
            if devices[index].preferred { next.preferred = true }
            if next.id.isEmpty { next.id = devices[index].id }
            if devices[index].id != next.id && !devices[index].id.isEmpty {
                next.id = devices[index].id
            }
            devices[index] = next
        } else {
            if next.id.isEmpty { next.id = UUID().uuidString }
            devices.append(next)
        }
        activeID = next.id
    }

    public mutating func touch(_ id: String, date: Date) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[index].lastSeen = date
    }

    public mutating func setPreferred(_ id: String) {
        guard devices.contains(where: { $0.id == id }) else { return }
        for index in devices.indices {
            devices[index].preferred = devices[index].id == id
        }
    }
}
