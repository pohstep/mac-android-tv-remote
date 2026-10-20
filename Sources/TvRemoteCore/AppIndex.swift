import Foundation

public enum AppListCaption {
    public static let offlineSaved = "TV offline, saved list"
    public static let loadingTitle = "Loading apps"
    public static let liveTitle = "Apps"

    public static func text(loading: Bool, appsEmpty: Bool, savedCatalog: Bool, connected: Bool, connecting: Bool) -> String {
        if loading && appsEmpty { return loadingTitle }
        if savedCatalog && !appsEmpty && !connected && !connecting && !loading { return offlineSaved }
        return liveTitle
    }
}

public enum AppIndex {
    /// Evening Paper writes this export. Names, order, and favourites come from the file.
    public static let launcherPath = "/sdcard/Android/data/dev.pohstep.eveningpaper/files/index.json"

    public static func parseLauncher(_ text: String) -> [TvApp]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let parsed = apps(in: json)
        guard !parsed.apps.isEmpty else { return nil }
        return pinFavourites(parsed.apps, explicit: parsed.pinned)
    }

    /// `cmd package query-activities` for the leanback launcher category.
    /// Labels come from `nonLocalizedLabel` or `application-label` when the dump includes them.
    public static func parseLeanback(_ text: String) -> [TvApp] {
        var labeled: [String: String] = [:]
        var order: [String] = []

        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        var pendingPackage: String?
        for line in lines {
            if let package = packageNameField(line) {
                remember(package, label: nil, order: &order, labeled: &labeled)
                pendingPackage = package
                continue
            }
            if let label = labelField(line), let package = pendingPackage {
                labeled[package] = label
                continue
            }
            if let package = slashPackage(line) {
                remember(package, label: nil, order: &order, labeled: &labeled)
                pendingPackage = package
            }
        }
        return order.compactMap { package in
            guard PackageName.isValid(package) else { return nil }
            let label = labeled[package].flatMap { cleanedLabel($0) } ?? TvPicture.shortName(package)
            return TvApp(id: package, name: label, packageName: package, favourite: false)
        }
    }

    public static func label(in dump: String) -> String? {
        for raw in dump.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let label = labelField(line), let cleaned = cleanedLabel(label) {
                return cleaned
            }
        }
        return nil
    }

    public static func pinFavourites(_ apps: [TvApp], explicit: [String]) -> [TvApp] {
        var seen = Set<String>()
        var unique: [TvApp] = []
        for app in apps where seen.insert(app.packageName).inserted {
            unique.append(app)
        }
        var pinOrder: [String] = []
        for package in explicit where unique.contains(where: { $0.packageName == package }) && !pinOrder.contains(package) {
            pinOrder.append(package)
        }
        for app in unique where app.favourite && !pinOrder.contains(app.packageName) {
            pinOrder.append(app.packageName)
        }
        let pinned = pinOrder.compactMap { package in unique.first { $0.packageName == package } }
            .map { TvApp(id: $0.id, name: $0.name, packageName: $0.packageName, favourite: true) }
        let rest = unique.filter { !pinOrder.contains($0.packageName) }
            .map { TvApp(id: $0.id, name: $0.name, packageName: $0.packageName, favourite: false) }
        return pinned + rest
    }

    private static func apps(in json: Any) -> (apps: [TvApp], pinned: [String]) {
        if let rows = json as? [Any] {
            return (rows.compactMap(app(from:)), [])
        }
        guard let object = json as? [String: Any] else { return ([], []) }
        let rows = (object["apps"] as? [Any])
            ?? (object["items"] as? [Any])
            ?? (object["index"] as? [Any])
            ?? []
        let pinned = packageList(object["favourites"] ?? object["favorites"])
        return (rows.compactMap(app(from:)), pinned)
    }

    private static func packageList(_ value: Any?) -> [String] {
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { item in
            if let package = item as? String { return PackageName.isValid(package) ? package : nil }
            if let object = item as? [String: Any] { return packageField(object) }
            return nil
        }
    }

    private static func app(from value: Any) -> TvApp? {
        guard let object = value as? [String: Any], let package = packageField(object) else { return nil }
        let name = string(object, keys: ["name", "label", "title"]) ?? TvPicture.shortName(package)
        let favourite = bool(object, keys: ["favourite", "favorite", "pinned", "starred"])
        return TvApp(id: package, name: name, packageName: package, favourite: favourite)
    }

    private static func packageField(_ object: [String: Any]) -> String? {
        if let package = string(object, keys: ["packageName", "package", "package_name"]), PackageName.isValid(package) {
            return package
        }
        if let component = string(object, keys: ["component", "activity"]) {
            let package = component.split(separator: "/").first.map(String.init) ?? ""
            if PackageName.isValid(package) { return package }
        }
        return nil
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let text = object[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func bool(_ object: [String: Any], keys: [String]) -> Bool {
        for key in keys {
            if let flag = object[key] as? Bool, flag { return true }
            if let number = object[key] as? Int, number != 0 { return true }
            if let text = object[key] as? String, ["1", "true", "yes"].contains(text.lowercased()) { return true }
        }
        return false
    }

    private static func remember(_ package: String, label: String?, order: inout [String], labeled: inout [String: String]) {
        guard PackageName.isValid(package) else { return }
        if !order.contains(package) { order.append(package) }
        if let label, labeled[package] == nil { labeled[package] = label }
    }

    private static func packageNameField(_ line: String) -> String? {
        guard let range = line.range(of: "packageName=") else { return nil }
        let rest = line[range.upperBound...]
        let token = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        return PackageName.isValid(token) ? token : nil
    }

    private static func labelField(_ line: String) -> String? {
        if let range = line.range(of: "nonLocalizedLabel=") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let range = line.range(of: "application-label:") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func cleanedLabel(_ raw: String) -> String? {
        TvApp.cleanName(raw)
    }

    /// Sony getApplicationList → launchable apps in TV order. Drops inputs, system tools, duplicates.
    public static func parseSony(_ data: Data) -> [TvApp] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [Any],
              let list = result.first as? [[String: Any]] else { return [] }
        let hidden = ["com.sony.dtv.timers", "com.sony.dtv.appassistant", "com.sony.dtv.notificationcenter",
                      "guidedActions", "ExternalInput", "com.android.tv.settings"]
        var seen = Set<String>()
        var out: [TvApp] = []
        for item in list {
            guard let uri = item["uri"] as? String, !uri.isEmpty,
                  let title = TvApp.cleanName(item["title"] as? String) else { continue }
            if hidden.contains(where: { uri.contains($0) }) { continue }
            if title.range(of: #"^HDMI\s*\d"#, options: .regularExpression) != nil { continue }
            if seen.contains(title) { continue }
            seen.insert(title)
            let package = sonyPackage(uri) ?? uri
            out.append(TvApp(id: uri, name: title, packageName: package, favourite: false,
                             uri: uri, iconURL: item["icon"] as? String))
        }
        return out
    }

    /// "com.sony.dtv.<package>.<activity class>" → package.
    public static func sonyPackage(_ uri: String) -> String? {
        let prefix = "com.sony.dtv."
        guard uri.hasPrefix(prefix) else { return nil }
        let tokens = uri.dropFirst(prefix.count).split(separator: ".").map(String.init)
        guard tokens.count >= 3 else { return nil }
        for k in 2..<tokens.count {
            let pkg = tokens[0..<k].joined(separator: ".")
            let rest = tokens[k...].joined(separator: ".")
            if rest.hasPrefix(pkg + ".") { return pkg }
        }
        let roots: Set<String> = ["com", "org", "dev", "net", "io", "cn"]
        for k in 2..<tokens.count where roots.contains(tokens[k]) {
            return tokens[0..<k].joined(separator: ".")
        }
        return nil
    }

    private static func slashPackage(_ line: String) -> String? {
        let token = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        guard token.contains("/") else { return nil }
        let package = String(token.split(separator: "/").first ?? "")
        return PackageName.isValid(package) ? package : nil
    }
}

public struct AppCatalogStore {
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func fileURL(homeDirectory: String = NSHomeDirectory()) -> URL {
        Settings.applicationSupportURL(homeDirectory: homeDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent("apps.json")
    }

    public func load() -> [TvApp]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let apps = try? JSONDecoder().decode([TvApp].self, from: data),
              !apps.isEmpty else { return nil }
        return AppIndex.pinFavourites(apps, explicit: apps.filter(\.favourite).map(\.packageName))
    }

    public func save(_ apps: [TvApp]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(apps).write(to: url, options: .atomic)
    }
}
