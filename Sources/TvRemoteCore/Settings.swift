import Foundation

public struct TvApp: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var packageName: String
    public var favourite: Bool
    /// Sony app URI from getApplicationList; launched with setActiveApp when present.
    public var uri: String?
    /// Sony icon URL from getApplicationList.
    public var iconURL: String?

    public init(id: String, name: String, packageName: String, favourite: Bool = false, uri: String? = nil, iconURL: String? = nil) {
        self.id = id
        self.name = TvApp.cleanName(name) ?? TvPicture.shortName(packageName)
        self.packageName = packageName
        self.favourite = favourite
        self.uri = uri
        self.iconURL = iconURL
    }

    /// Drops raw dumpsys/pm text such as "null icon=0x7f040007 banner=0x7f040000".
    public static func cleanName(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        for marker in [" icon=", " banner=", " logo=", " theme=", "icon=0x", "banner=0x"] {
            if let r = text.range(of: marker) { text = String(text[..<r.lowerBound]) }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.lowercased() == "null" || text.hasPrefix("0x") { return nil }
        return text
    }

    /// True when this app is the given Android package (works for Sony URIs too).
    public func matches(package: String?) -> Bool {
        guard let package, !package.isEmpty else { return false }
        if packageName == package { return true }
        if let uri { return uri.hasPrefix("com.sony.dtv.\(package).") }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, packageName, favourite, favorite, uri, iconURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let packageName = try container.decode(String.self, forKey: .packageName)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? packageName
        name = TvApp.cleanName(try container.decodeIfPresent(String.self, forKey: .name)) ?? TvPicture.shortName(packageName)
        uri = try container.decodeIfPresent(String.self, forKey: .uri)
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
        self.packageName = packageName
        let british = try container.decodeIfPresent(Bool.self, forKey: .favourite) ?? false
        let american = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        favourite = british || american
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(packageName, forKey: .packageName)
        try container.encode(favourite, forKey: .favourite)
        try container.encodeIfPresent(uri, forKey: .uri)
        try container.encodeIfPresent(iconURL, forKey: .iconURL)
    }

    public static let defaults: [TvApp] = [
        TvApp(id: "smarttube", name: "SmartTube", packageName: "org.smarttube.stable"),
        TvApp(id: "netflix", name: "Netflix", packageName: "com.netflix.ninja"),
        TvApp(id: "disney", name: "Disney+", packageName: "com.disney.disneyplus"),
        TvApp(id: "vlc", name: "VLC", packageName: "org.videolan.vlc"),
        TvApp(id: "spotify", name: "Spotify", packageName: "com.spotify.tv.android"),
        TvApp(id: "tvbro", name: "TV Bro", packageName: "com.phlox.tvwebbrowser")
    ]
}

public struct Settings: Codable, Equatable {
    public var host: String
    public var port: Int
    public var adbPath: String
    public var macAddress: String
    public var broadcastAddress: String
    public var apps: [TvApp]
    public var keyboardMode: Bool
    /// HTTP port for Sony IP control. The pre-shared key is not stored here.
    public var sonyPort: Int
    public var devices: [StoredTV]
    public var activeDeviceID: String
    public var brand: TvBrand
    /// When false, a Sony TV stays on IP control and does not open network debugging.
    public var useDebugging: Bool

    public init(
        host: String,
        port: Int,
        adbPath: String,
        macAddress: String,
        broadcastAddress: String,
        apps: [TvApp],
        keyboardMode: Bool,
        sonyPort: Int = 80,
        devices: [StoredTV] = [],
        activeDeviceID: String = "",
        brand: TvBrand = .sony,
        useDebugging: Bool = true
    ) {
        self.host = host
        self.port = port
        self.adbPath = adbPath
        self.macAddress = macAddress
        self.broadcastAddress = broadcastAddress
        self.apps = apps
        self.keyboardMode = keyboardMode
        self.sonyPort = sonyPort
        self.devices = devices
        self.activeDeviceID = activeDeviceID
        self.brand = brand
        self.useDebugging = useDebugging
    }

    public static func factoryDefaults() -> Settings {
        Settings(
            host: "",
            port: 5555,
            adbPath: "",
            macAddress: "",
            broadcastAddress: "255.255.255.255",
            apps: TvApp.defaults,
            keyboardMode: false,
            sonyPort: 80,
            devices: [],
            activeDeviceID: "",
            brand: .sony,
            useDebugging: true
        )
    }

    public func applying(_ device: StoredTV) -> Settings {
        var copy = self
        copy.host = device.host
        copy.port = device.port
        copy.macAddress = device.macAddress
        copy.brand = device.brand
        copy.useDebugging = device.useDebugging
        copy.activeDeviceID = device.id
        if device.brand == .sony {
            copy.sonyPort = device.controlPort
        }
        if let index = copy.devices.firstIndex(where: { $0.id == device.id }) {
            copy.devices[index] = device
        } else if !device.id.isEmpty {
            copy.devices.append(device)
        }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case host, port, adbPath, macAddress, broadcastAddress, apps, keyboardMode, sonyPort
        case devices, activeDeviceID, brand, useDebugging
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 5555
        adbPath = try container.decodeIfPresent(String.self, forKey: .adbPath) ?? ""
        macAddress = try container.decodeIfPresent(String.self, forKey: .macAddress) ?? ""
        broadcastAddress = try container.decodeIfPresent(String.self, forKey: .broadcastAddress) ?? "255.255.255.255"
        apps = try container.decodeIfPresent([TvApp].self, forKey: .apps) ?? TvApp.defaults
        keyboardMode = try container.decodeIfPresent(Bool.self, forKey: .keyboardMode) ?? false
        sonyPort = try container.decodeIfPresent(Int.self, forKey: .sonyPort) ?? 80
        if let stored = try container.decodeIfPresent([StoredTV].self, forKey: .devices) {
            devices = stored
            activeDeviceID = try container.decodeIfPresent(String.self, forKey: .activeDeviceID) ?? stored.first?.id ?? ""
        } else {
            #if ZAPBAR_MIGRATE_V1 && !SANDBOX_BUILD
            devices = StoredTV.migrateLegacy(host: host, port: port, macAddress: macAddress, controlPort: sonyPort)
            #else
            devices = []
            #endif
            activeDeviceID = devices.first?.id ?? ""
        }
        brand = try container.decodeIfPresent(TvBrand.self, forKey: .brand) ?? devices.first?.brand ?? .sony
        useDebugging = try container.decodeIfPresent(Bool.self, forKey: .useDebugging) ?? devices.first?.useDebugging ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(adbPath, forKey: .adbPath)
        try container.encode(macAddress, forKey: .macAddress)
        try container.encode(broadcastAddress, forKey: .broadcastAddress)
        try container.encode(apps, forKey: .apps)
        try container.encode(keyboardMode, forKey: .keyboardMode)
        try container.encode(sonyPort, forKey: .sonyPort)
        try container.encode(devices, forKey: .devices)
        try container.encode(activeDeviceID, forKey: .activeDeviceID)
        try container.encode(brand, forKey: .brand)
        try container.encode(useDebugging, forKey: .useDebugging)
    }

    public static func applicationSupportURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        settingsFile(homeDirectory: homeDirectory, folder: "Zapbar")
    }

    #if ZAPBAR_MIGRATE_V1 && !SANDBOX_BUILD
    /// v1.0 wrote settings here. The dev build still reads this when the Zapbar file is absent.
    public static func legacyApplicationSupportURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        settingsFile(homeDirectory: homeDirectory, folder: "Pohstep Remote")
    }
    #endif

    public static func resolvedSettingsURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        let modern = applicationSupportURL(homeDirectory: homeDirectory)
        #if ZAPBAR_MIGRATE_V1 && !SANDBOX_BUILD
        if FileManager.default.fileExists(atPath: modern.path) { return modern }
        let legacy = legacyApplicationSupportURL(homeDirectory: homeDirectory)
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return modern
        #else
        return modern
        #endif
    }

    private static func settingsFile(homeDirectory: String, folder: String) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support/\(folder)", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}

public struct SettingsLoad: Equatable {
    public var settings: Settings
    public var warning: String?
}

public struct SettingsStore {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> SettingsLoad {
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists {
            return SettingsLoad(settings: .factoryDefaults(), warning: nil)
        }
        do {
            let data = try Data(contentsOf: url)
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            return SettingsLoad(settings: settings, warning: nil)
        } catch {
            let backup = url.appendingPathExtension("bad")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            return SettingsLoad(
                settings: .factoryDefaults(),
                warning: "Settings couldn't be read, so the defaults are in use. A copy was kept next to the file."
            )
        }
    }

    public func save(_ settings: Settings) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
