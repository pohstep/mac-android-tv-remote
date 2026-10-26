#if ZAPBAR_ADVANCED
import Foundation

/// Facts read from the TV before a package is offered or turned off.
public struct DeviceFacts: Equatable {
    public var model: String
    public var osVersion: String
    public var installed: Set<String>
    public var thirdParty: Set<String>
    public var disabled: Set<String>
    public var homePackage: String?
    public var homePackages: Set<String>
    public var defaultIMEPackage: String?
    public var enabledIMEPackages: Set<String>
    public var persistentPackages: Set<String>
    public var systemUIDPackages: Set<String>
    public var tvInputPackages: Set<String>
    public var passthroughPackages: Set<String>
    public var settingsHandlerPackages: Set<String>
    public var setupWizardPackages: Set<String>
    public var keyHandlerPackages: Set<String>
    public var webViewPackage: String?

    public init(
        model: String = "",
        osVersion: String = "",
        installed: Set<String> = [],
        thirdParty: Set<String> = [],
        disabled: Set<String> = [],
        homePackage: String? = nil,
        homePackages: Set<String> = [],
        defaultIMEPackage: String? = nil,
        enabledIMEPackages: Set<String> = [],
        persistentPackages: Set<String> = [],
        systemUIDPackages: Set<String> = [],
        tvInputPackages: Set<String> = [],
        passthroughPackages: Set<String> = [],
        settingsHandlerPackages: Set<String> = [],
        setupWizardPackages: Set<String> = [],
        keyHandlerPackages: Set<String> = [],
        webViewPackage: String? = nil
    ) {
        self.model = model
        self.osVersion = osVersion
        self.installed = installed
        self.thirdParty = thirdParty
        self.disabled = disabled
        self.homePackage = homePackage
        self.homePackages = homePackages
        self.defaultIMEPackage = defaultIMEPackage
        self.enabledIMEPackages = enabledIMEPackages
        self.persistentPackages = persistentPackages
        self.systemUIDPackages = systemUIDPackages
        self.tvInputPackages = tvInputPackages
        self.passthroughPackages = passthroughPackages
        self.settingsHandlerPackages = settingsHandlerPackages
        self.setupWizardPackages = setupWizardPackages
        self.keyHandlerPackages = keyHandlerPackages
        self.webViewPackage = webViewPackage
    }

    public var enabled: Set<String> {
        installed.subtracting(disabled)
    }
}

public struct NeverTouchPrefix: Equatable {
    public var prefix: String
    public var exceptions: [String]
}

public struct NeverTouchDependency: Equatable {
    public var ifEnabled: String
    public var neverDisable: String
}

/// The bundled never-touch rules. `why` text from the file is kept for tests
/// and is not shown in the panel.
public struct NeverTouchRuleSet {
    public let version: Int
    public let method: String
    public let exactPackages: [String]
    public let prefixes: [NeverTouchPrefix]
    public let regexSources: [String]
    public let denyNamespaces: [String]
    public let structuralIDs: [String]
    public let warningPackages: [String]
    public let dependencies: [NeverTouchDependency]
    public let exactWhys: [String: String]

    private let exact: Set<String>
    private let regexes: [NSRegularExpression]

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(NeverTouchFile.self, from: data)
        version = file.version
        method = file.method
        exactPackages = file.never_exact.map(\.pkg)
        exact = Set(exactPackages)
        prefixes = file.never_prefix.map { NeverTouchPrefix(prefix: $0.prefix, exceptions: $0.exceptions) }
        regexSources = file.never_regex
        denyNamespaces = file.default_deny_namespaces.map(\.prefix)
        structuralIDs = file.structural_rules.map(\.id)
        warningPackages = file.advanced_warn.map(\.pkg)
        dependencies = file.conditional_dependencies.map {
            NeverTouchDependency(ifEnabled: $0.if_enabled, neverDisable: $0.then_never_disable)
        }
        var whys: [String: String] = [:]
        for item in file.never_exact {
            whys[item.pkg] = item.why
        }
        exactWhys = whys
        regexes = try file.never_regex.map { source in
            try NSRegularExpression(pattern: source)
        }
    }

    public func regexMatches(_ package: String) -> Bool {
        let range = NSRange(package.startIndex..., in: package)
        return regexes.contains { $0.firstMatch(in: package, options: [], range: range) != nil }
    }

    func isExact(_ package: String) -> Bool {
        exact.contains(package)
    }

    /// A prefix hit that is not one of the named exceptions.
    func prefixRule(for package: String) -> String? {
        for entry in prefixes where package.hasPrefix(entry.prefix) {
            if entry.exceptions.contains(package) { return nil }
            return "prefix"
        }
        return nil
    }

    func isPrefixException(_ package: String) -> Bool {
        prefixes.contains { $0.exceptions.contains(package) }
    }
}

public enum NeverTouchReasons {
    public static func sentence(_ rule: String) -> String {
        switch rule {
        case "home":
            return "This is the Home screen. Turning it off can stop the TV from starting."
        case "home_pair":
            return "Turning this off can leave the TV stuck on the startup screen."
        case "ime":
            return "This is a keyboard. Turning it off removes typing on the TV."
        case "persistent":
            return "The TV starts this with the system. Turning it off can stop the set from booting."
        case "tv_input_framework":
            return "This handles picture inputs."
        case "passthrough_handler":
            return "This routes picture inputs or Settings."
        case "setup_wizard":
            return "This handles first-time setup. Turning it off can drop the saved network."
        case "key_events":
            return "This handles remote keys."
        case "webview":
            return "Settings and apps use this to draw pages."
        case "networking":
            return "This keeps the TV on the network."
        case "vendor_middleware":
            return "This is part of the picture system."
        case "factory":
            return "This is a factory tool. Changing it can break the inputs."
        case "companion_pairs":
            return "Something else on the TV still needs this."
        case "firmware_refuses":
            return "The TV left this on."
        default:
            return "The TV needs this to start and stay usable."
        }
    }

    public static func warning(_ package: String) -> String {
        switch package {
        case "com.google.android.katniss":
            return "The mic button and voice search stop."
        case "com.google.android.apps.mediashell":
            return "Casting to the TV stops."
        case "com.google.android.tvrecommendations":
            return "Recommendation rows go empty, and some phone remotes stop."
        case "com.google.android.apps.tv.dreamx":
            return "The home panel and the ambient screen go away."
        case "com.google.android.leanbacklauncher":
            return "Leave this on unless you know the set does not use it to start."
        default:
            return "Turning this off can break a feature you still use."
        }
    }
}

public struct NeverTouchMatcher {
    public let rules: NeverTouchRuleSet

    public init(rules: NeverTouchRuleSet) {
        self.rules = rules
    }

    /// First matching rule, or nil when the package may be turned off.
    /// Prefix exceptions also skip the provider regex. Default-deny namespaces
    /// still allow a package that is on the starter list.
    public func matchingRule(package: String, facts: DeviceFacts, allowListed: Bool) -> String? {
        let pkg = package.trimmingCharacters(in: .whitespacesAndNewlines)
        if pkg.isEmpty { return "exact" }
        if rules.isExact(pkg) { return "exact" }
        if rules.prefixRule(for: pkg) != nil { return "prefix" }
        if !rules.isPrefixException(pkg) && rules.regexMatches(pkg) { return "regex" }
        if let structural = structuralRule(package: pkg, facts: facts) { return structural }
        if !allowListed && rules.denyNamespaces.contains(where: { pkg.hasPrefix($0) }) {
            return "default_deny"
        }
        return nil
    }

    public func reason(package: String, facts: DeviceFacts, allowListed: Bool) -> String? {
        guard let rule = matchingRule(package: package, facts: facts, allowListed: allowListed) else {
            return nil
        }
        return NeverTouchReasons.sentence(rule)
    }

    /// Structural rules only, in the order stored in the JSON.
    /// `firmware_refuses` is a read-back after the command, so it returns nil here.
    public func structuralRule(package: String, facts: DeviceFacts) -> String? {
        let pkg = package.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = pkg.lowercased()
        for id in rules.structuralIDs {
            switch id {
            case "home":
                if pkg == facts.homePackage || facts.homePackages.contains(pkg) || pkg == "com.android.tv.settings" {
                    return id
                }
            case "home_pair":
                if pkg == "com.google.android.apps.tv.launcherx" || pkg == "com.google.android.tungsten.setupwraith" {
                    return id
                }
            case "ime":
                if pkg == facts.defaultIMEPackage || facts.enabledIMEPackages.contains(pkg) {
                    return id
                }
            case "persistent":
                if facts.persistentPackages.contains(pkg) || facts.systemUIDPackages.contains(pkg) {
                    return id
                }
            case "tv_input_framework":
                if facts.tvInputPackages.contains(pkg) {
                    return id
                }
            case "passthrough_handler":
                if facts.passthroughPackages.contains(pkg) || facts.settingsHandlerPackages.contains(pkg) {
                    return id
                }
            case "setup_wizard":
                if facts.setupWizardPackages.contains(pkg) || Self.nameLooksLikeSetup(lower) {
                    return id
                }
            case "key_events":
                if facts.keyHandlerPackages.contains(pkg) || Self.nameLooksLikeKeyHandler(lower) {
                    return id
                }
            case "webview":
                if let web = facts.webViewPackage, pkg == web {
                    return id
                }
            case "networking":
                if Self.nameLooksLikeNetworking(lower) {
                    return id
                }
            case "permission_controller":
                if lower.contains("permissioncontroller") {
                    return id
                }
            case "package_installer":
                if lower.contains("packageinstaller") {
                    return id
                }
            case "vendor_middleware":
                if Self.nameLooksLikeMiddleware(lower) {
                    return id
                }
            case "factory":
                if Self.nameLooksLikeFactory(lower) {
                    return id
                }
            case "companion_pairs":
                if dependencyBlocks(pkg, facts: facts) {
                    return id
                }
            case "firmware_refuses":
                break
            default:
                break
            }
        }
        return nil
    }

    public func dependencyBlocks(_ package: String, facts: DeviceFacts) -> Bool {
        for pair in rules.dependencies where pair.neverDisable == package {
            if facts.enabled.contains(pair.ifEnabled) { return true }
        }
        return false
    }

    static func nameLooksLikeSetup(_ lower: String) -> Bool {
        lower.contains("setupwizard") || lower.contains("provision") || lower.contains("tvsetup")
    }

    static func nameLooksLikeKeyHandler(_ lower: String) -> Bool {
        let tokens = ["kpad", "favkey", "hotkey.dispatcher", "uinputservice", "remotepairing", "inputinjection"]
        return tokens.contains { lower.contains($0) }
    }

    static func nameLooksLikeNetworking(_ lower: String) -> Bool {
        lower.contains("networkstack") || lower.contains("captiveportallogin") || lower.contains("captiveportal")
            || lower.contains(".ethernet") || lower.contains("dhcpservice")
    }

    static func nameLooksLikeMiddleware(_ lower: String) -> Bool {
        lower.contains("middleware") || lower.contains("tvcenter") || lower.contains("tvapi")
            || lower.contains("tvservice") || lower.contains(".mal") || lower.hasSuffix(".mal")
    }

    static func nameLooksLikeFactory(_ lower: String) -> Bool {
        lower.contains("factory") || lower.contains("production") || lower.contains("fac.menu")
            || lower.contains("hkcfac") || lower.contains(".fac.")
    }
}

public enum CleanupProfile: String, Codable, Equatable {
    case sonyChina
    case sonyGlobal
    case generic
    case unknown
}

public enum CleanupProfileDetector {
    /// China firmware and an unknown model select nothing. A Sony set with no
    /// Play services package, or with the China home app, counts as China firmware.
    public static func detect(brand: TvBrand, model: String, installed: Set<String>) -> CleanupProfile {
        if installed.isEmpty { return .unknown }
        let folded = model.lowercased()
        let chinaMarker = folded.contains("china") || folded.contains("-cn") || folded.contains("_cn")
            || folded.contains("vh21") || folded.contains("vh1")
        let chinaHome = installed.contains("com.dangbei.TVHomeLauncher")
        let hasServices = installed.contains("com.google.android.gms")
        switch brand {
        case .sony:
            if chinaHome || chinaMarker || !hasServices { return .sonyChina }
            return .sonyGlobal
        case .generic, .xiaomi:
            if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .unknown }
            return .generic
        }
    }

    public static func ticksSuggestions(_ profile: CleanupProfile) -> Bool {
        profile == .sonyGlobal || profile == .generic
    }
}

private struct NeverTouchFile: Decodable {
    var version: Int
    var method: String
    var never_exact: [ExactItem]
    var never_prefix: [PrefixItem]
    var never_regex: [String]
    var default_deny_namespaces: [DenyItem]
    var structural_rules: [StructuralItem]
    var advanced_warn: [WarnItem]
    var conditional_dependencies: [DependencyItem]
}

private struct ExactItem: Decodable {
    var pkg: String
    var why: String
}

private struct PrefixItem: Decodable {
    var prefix: String
    var why: String?
    var exceptions: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prefix = try container.decode(String.self, forKey: .prefix)
        why = try container.decodeIfPresent(String.self, forKey: .why)
        exceptions = try container.decodeIfPresent([String].self, forKey: .exceptions) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case prefix, why, exceptions
    }
}

private struct DenyItem: Decodable {
    var prefix: String
}

private struct StructuralItem: Decodable {
    var id: String
}

private struct WarnItem: Decodable {
    var pkg: String
}

private struct DependencyItem: Decodable {
    var if_enabled: String
    var then_never_disable: String
}
#endif
