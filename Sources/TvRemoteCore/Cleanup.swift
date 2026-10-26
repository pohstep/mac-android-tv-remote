#if ZAPBAR_ADVANCED
import Foundation

public struct CleanupCatalogItem: Equatable {
    public var packageName: String
    public var reason: String
}

public struct CleanupCatalog {
    public let sonyGlobal: [CleanupCatalogItem]
    public let sonyChina: [CleanupCatalogItem]
    public let generic: [CleanupCatalogItem]
    public let allowList: Set<String>

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(CatalogFile.self, from: data)
        sonyGlobal = file.profiles.sonyGlobal.map { CleanupCatalogItem(packageName: $0.pkg, reason: $0.reason) }
        sonyChina = file.profiles.sonyChina.map { CleanupCatalogItem(packageName: $0.pkg, reason: $0.reason) }
        generic = file.profiles.generic.map { CleanupCatalogItem(packageName: $0.pkg, reason: $0.reason) }
        allowList = Set((sonyGlobal + sonyChina + generic).map(\.packageName))
    }

    public func items(for profile: CleanupProfile) -> [CleanupCatalogItem] {
        switch profile {
        case .sonyGlobal: return sonyGlobal
        case .sonyChina: return sonyChina
        case .generic: return generic
        case .unknown:
            var seen = Set<String>()
            var merged: [CleanupCatalogItem] = []
            for item in sonyGlobal + sonyChina + generic where seen.insert(item.packageName).inserted {
                merged.append(item)
            }
            return merged
        }
    }

    public func allows(_ package: String) -> Bool {
        allowList.contains(package)
    }

    public func reason(for package: String, profile: CleanupProfile) -> String? {
        items(for: profile).first { $0.packageName == package }?.reason
            ?? (sonyGlobal + sonyChina + generic).first { $0.packageName == package }?.reason
    }
}

public struct CleanupRow: Equatable, Identifiable {
    public var name: String
    public var reason: String
    public var ticked: Bool
    public var warning: Bool

    public var id: String { name }

    public init(name: String, reason: String, ticked: Bool, warning: Bool) {
        self.name = name
        self.reason = reason
        self.ticked = ticked
        self.warning = warning
    }
}

public struct CleanupRejection: Equatable {
    public var name: String
    public var reason: String
}

public struct CleanupPreview: Equatable {
    public var profile: CleanupProfile
    public var rows: [CleanupRow]
    public var warnings: [CleanupRow]
    public var rejected: [CleanupRejection]
    public var note: String
    public var model: String
    public var osVersion: String
}

public enum UndoPhase: String, Codable, Equatable {
    case planned
    case disabled
    case blocked
    case refused
    case restored
}

public struct UndoPackage: Codable, Equatable {
    public var name: String
    public var wasEnabled: Bool
    public var phase: UndoPhase
    public var disabledAt: Date?

    public init(name: String, wasEnabled: Bool, phase: UndoPhase, disabledAt: Date? = nil) {
        self.name = name
        self.wasEnabled = wasEnabled
        self.phase = phase
        self.disabledAt = disabledAt
    }
}

public struct UndoRecord: Codable, Equatable {
    public var version: Int
    public var tvID: String
    public var model: String
    public var osVersion: String
    public var createdAt: Date
    public var updatedAt: Date
    public var packages: [UndoPackage]

    public var restorableNames: [String] {
        packages.filter { $0.phase == .planned || $0.phase == .disabled }.map(\.name)
    }
}

public struct UndoStore {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory(homeDirectory: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support/Zapbar", isDirectory: true)
    }

    public static func fileName(tvID: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let cleanedScalars = tvID.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let cleaned = String(cleanedScalars)
        let base = cleaned.isEmpty ? "tv" : cleaned
        return "undo-\(base).json"
    }

    public func fileURL(tvID: String) -> URL {
        directory.appendingPathComponent(UndoStore.fileName(tvID: tvID))
    }

    public func fileExists(tvID: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(tvID: tvID).path)
    }

    public func load(tvID: String) -> UndoRecord? {
        let url = fileURL(tvID: tvID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UndoRecord.self, from: data)
    }

    public func save(_ record: UndoRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: fileURL(tvID: record.tvID), options: .atomic)
    }
}

public struct CleanupReport: Equatable {
    public var sentence: String
    public var isError: Bool
    public var disabled: [String]
    public var skipped: [String]

    public init(sentence: String, isError: Bool, disabled: [String] = [], skipped: [String] = []) {
        self.sentence = sentence
        self.isError = isError
        self.disabled = disabled
        self.skipped = skipped
    }
}

public enum CleanupCopy {
    public static let recoveryTitle = "If the TV will not start"
    public static let recoveryBody = """
    Nothing was removed. What was turned off can be turned back on.

    Wait 3 minutes. Do not hold the power button.

    If the TV answers, use Restore all. That turns the same packages back on. Wait a moment, then restart the TV if the picture is still wrong.

    If it does not answer, plug in a network cable. Some sets answer sooner that way.

    If you can open the recovery menu, the button combination is in the manual. It is often the power key plus another key while plugging the set in. Choose the choice that wipes user data. A Bluetooth remote often does not work on that screen. Use the infrared remote or a keyboard plugged into the set.

    If there is no recovery menu, a service centre is the next step. Do not use flashing tools from a random site.

    After a reset, nothing here turns packages off again unless you do it yourself.
    """

    public static let notAnsweringNothingChanged = "The TV is not answering. Nothing was changed."
    public static let homeDidNotAnswer = "The Home screen did not answer. Nothing was changed."
    public static let rolledBack = "The TV did not stay up after the change, so those packages were turned back on."
    public static let unreachableKeepRecord = "The TV is not answering. The list stays on this Mac. Try Restore all when the TV is back."
    public static let chooseOne = "Choose a package first."
    public static let nothingToRestore = "There is nothing to turn back on."
    public static let restored = "Turned those packages back on."
    public static let recordUnreadable = "The saved list could not be read. It was left in place."

    public static func finished(disabled: Int, leftOn: Int, refused: Int) -> String {
        if disabled == 0 && leftOn == 0 && refused == 0 {
            return chooseOne
        }
        if disabled == 0 && leftOn > 0 && refused == 0 {
            return "Nothing was turned off. The TV needs those packages."
        }
        var parts: [String] = []
        if disabled > 0 {
            let noun = disabled == 1 ? "package" : "packages"
            parts.append("Turned off \(disabled) \(noun).")
        }
        if leftOn > 0 {
            let noun = leftOn == 1 ? "package" : "packages"
            let pronoun = leftOn == 1 ? "it" : "them"
            parts.append("Left \(leftOn) \(noun) on because the TV needs \(pronoun).")
        }
        if refused > 0 {
            parts.append(refused == 1 ? "The TV left 1 on." : "The TV left \(refused) on.")
        }
        if disabled > 0 {
            parts.append("Restore all turns \(disabled == 1 ? "it" : "them") back on.")
        }
        return parts.joined(separator: " ")
    }
}

public enum CleanupParse {
    public static func packages(from text: String) -> Set<String> {
        var found = Set<String>()
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("package:") {
                line = String(line.dropFirst("package:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if PackageName.isValid(line) || line == "android" {
                found.insert(line)
            }
        }
        return found
    }

    public static func componentPackage(from text: String) -> String? {
        if text.lowercased().contains("no activity found") { return nil }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'{},="))
        for raw in text.components(separatedBy: separators) where raw.contains("/") {
            let pkg = String(raw.split(separator: "/").first ?? "")
            if PackageName.isValid(pkg) { return pkg }
        }
        return nil
    }

    public static func componentPackages(from text: String) -> Set<String> {
        var found = Set<String>()
        for raw in text.split(whereSeparator: \.isNewline) {
            if let pkg = componentPackage(from: String(raw)) {
                found.insert(pkg)
            }
        }
        return found
    }

    public static func webViewPackage(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+"#) else {
            return nil
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let name = ns.substring(with: match.range)
            if name.lowercased().contains("webview") { return name }
        }
        return nil
    }

    public static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    public static func homeResolved(_ text: String) -> Bool {
        componentPackage(from: text) != nil
    }

    public static func enrich(_ facts: inout DeviceFacts, dumpsys: String, package: String) {
        if dumpsys.range(of: #"\bPERSISTENT\b"#, options: .regularExpression) != nil {
            facts.persistentPackages.insert(package)
        }
        if dumpsys.contains("android.uid.system") {
            facts.systemUIDPackages.insert(package)
        }
        if dumpsys.contains("TV_INPUT_HARDWARE") || dumpsys.contains("TvInputService") {
            facts.tvInputPackages.insert(package)
        }
        if dumpsys.contains("passthrough") {
            facts.passthroughPackages.insert(package)
        }
        if dumpsys.contains("android.settings.SETTINGS") {
            facts.settingsHandlerPackages.insert(package)
        }
        if dumpsys.contains("AccessibilityService") || dumpsys.contains("InputMethodService") {
            facts.keyHandlerPackages.insert(package)
        }
        if dumpsys.contains("SETUP_WIZARD") {
            facts.setupWizardPackages.insert(package)
        }
    }
}

public struct CleanupRunner {
    public static let defaultPause: TimeInterval = 0.4

    public var client: AdbClient
    public var serial: String
    public var rules: NeverTouchRuleSet
    public var catalog: CleanupCatalog
    public var pause: TimeInterval
    public var sleep: (TimeInterval) -> Void

    public init(
        client: AdbClient,
        serial: String,
        rules: NeverTouchRuleSet,
        catalog: CleanupCatalog,
        pause: TimeInterval = CleanupRunner.defaultPause,
        sleep: ((TimeInterval) -> Void)? = nil
    ) {
        self.client = client
        self.serial = serial
        self.rules = rules
        self.catalog = catalog
        self.pause = pause
        self.sleep = sleep ?? { Thread.sleep(forTimeInterval: $0) }
    }

    private var matcher: NeverTouchMatcher { NeverTouchMatcher(rules: rules) }

    public func preview(brand: TvBrand, extras: [String] = []) throws -> CleanupPreview {
        let facts = try collect()
        return makePreview(facts: facts, brand: brand, extras: extras)
    }

    public func makePreview(facts: DeviceFacts, brand: TvBrand, extras: [String] = []) -> CleanupPreview {
        let profile = CleanupProfileDetector.detect(brand: brand, model: facts.model, installed: facts.installed)
        let tickSuggestions = CleanupProfileDetector.ticksSuggestions(profile) && facts.homePackage != nil
        var rows: [CleanupRow] = []
        var seen = Set<String>()
        let warningNames = Set(rules.warningPackages)

        for item in catalog.items(for: profile) where facts.installed.contains(item.packageName) {
            if warningNames.contains(item.packageName) { continue }
            if matcher.matchingRule(package: item.packageName, facts: facts, allowListed: true) != nil { continue }
            seen.insert(item.packageName)
            let enabled = !facts.disabled.contains(item.packageName)
            rows.append(CleanupRow(
                name: item.packageName,
                reason: item.reason,
                ticked: tickSuggestions && enabled,
                warning: false
            ))
        }

        for name in facts.thirdParty.sorted() where !seen.contains(name) && !warningNames.contains(name) {
            let allow = catalog.allows(name)
            if matcher.matchingRule(package: name, facts: facts, allowListed: allow) != nil { continue }
            seen.insert(name)
            rows.append(CleanupRow(name: name, reason: "Installed on the TV.", ticked: false, warning: false))
        }

        var rejected: [CleanupRejection] = []
        for raw in extras {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || seen.contains(name) { continue }
            if !facts.installed.contains(name) {
                rejected.append(CleanupRejection(name: name, reason: "That package is not on the TV."))
                continue
            }
            let allow = catalog.allows(name)
            if let reason = matcher.reason(package: name, facts: facts, allowListed: allow) {
                rejected.append(CleanupRejection(name: name, reason: reason))
                continue
            }
            if warningNames.contains(name) { continue }
            seen.insert(name)
            rows.append(CleanupRow(name: name, reason: "You added this.", ticked: false, warning: false))
        }

        var warnings: [CleanupRow] = []
        for name in rules.warningPackages where facts.installed.contains(name) {
            if matcher.matchingRule(package: name, facts: facts, allowListed: true) != nil { continue }
            warnings.append(CleanupRow(
                name: name,
                reason: NeverTouchReasons.warning(name),
                ticked: false,
                warning: true
            ))
        }

        rows.sort { $0.name < $1.name }
        let note: String
        if facts.homePackage == nil {
            note = CleanupCopy.homeDidNotAnswer
        } else if !CleanupProfileDetector.ticksSuggestions(profile) {
            note = "Nothing is selected. Choose each package yourself."
        } else {
            note = "Suggested packages are selected. Untick any you want to keep."
        }
        return CleanupPreview(
            profile: profile,
            rows: rows,
            warnings: warnings,
            rejected: rejected,
            note: note,
            model: facts.model,
            osVersion: facts.osVersion
        )
    }

    public func disable(names: [String], brand: TvBrand, tvID: String, store: UndoStore, now: Date = Date()) -> CleanupReport {
        if store.fileExists(tvID: tvID) && store.load(tvID: tvID) == nil {
            return CleanupReport(sentence: CleanupCopy.recordUnreadable, isError: true)
        }
        let facts: DeviceFacts
        do {
            facts = try collect()
        } catch {
            return CleanupReport(sentence: CleanupCopy.notAnsweringNothingChanged, isError: true)
        }
        if facts.homePackage == nil {
            return CleanupReport(sentence: CleanupCopy.homeDidNotAnswer, isError: true)
        }

        var accepted: [String] = []
        var skipped: [String] = []
        var seen = Set<String>()
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || !seen.insert(name).inserted { continue }
            let allow = catalog.allows(name)
            if matcher.matchingRule(package: name, facts: facts, allowListed: allow) != nil || !PackageName.isValid(name) {
                skipped.append(name)
                continue
            }
            if !facts.installed.contains(name) || facts.disabled.contains(name) {
                skipped.append(name)
                continue
            }
            accepted.append(name)
        }
        if accepted.isEmpty {
            return CleanupReport(
                sentence: CleanupCopy.finished(disabled: 0, leftOn: skipped.count, refused: 0),
                isError: !skipped.isEmpty,
                skipped: skipped
            )
        }

        var record = store.load(tvID: tvID) ?? UndoRecord(
            version: 1,
            tvID: tvID,
            model: facts.model,
            osVersion: facts.osVersion,
            createdAt: now,
            updatedAt: now,
            packages: []
        )
        record.model = facts.model.isEmpty ? record.model : facts.model
        record.osVersion = facts.osVersion.isEmpty ? record.osVersion : facts.osVersion
        record.updatedAt = now
        for name in accepted {
            upsert(&record, UndoPackage(name: name, wasEnabled: true, phase: .planned))
        }
        do {
            try store.save(record)
        } catch {
            return CleanupReport(sentence: "The undo list could not be saved. Nothing was changed.", isError: true)
        }

        var turnedOff: [String] = []
        var refused: [String] = []
        var halted = false
        for name in accepted {
            var gate = facts
            if let dump = try? shell(["dumpsys", "package", name]) {
                CleanupParse.enrich(&gate, dumpsys: dump, package: name)
            }
            if matcher.matchingRule(package: name, facts: gate, allowListed: catalog.allows(name)) != nil {
                updatePhase(&record, name: name, phase: .blocked, at: nil)
                record.updatedAt = Date()
                try? store.save(record)
                skipped.append(name)
                continue
            }
            do {
                _ = try shell(["pm", "disable-user", "--user", "0", name])
            } catch {
                halted = true
                break
            }
            sleep(pause)
            let disabledNow: Set<String>
            do {
                disabledNow = try readDisabled()
            } catch {
                halted = true
                break
            }
            if disabledNow.contains(name) {
                let stamp = Date()
                updatePhase(&record, name: name, phase: .disabled, at: stamp)
                record.updatedAt = stamp
                try? store.save(record)
                turnedOff.append(name)
            } else {
                updatePhase(&record, name: name, phase: .refused, at: nil)
                record.updatedAt = Date()
                try? store.save(record)
                refused.append(name)
            }
        }

        if halted {
            return restoreAfterFailure(record: &record, store: store, turnedOff: turnedOff)
        }
        switch verify() {
        case .ok:
            return CleanupReport(
                sentence: CleanupCopy.finished(disabled: turnedOff.count, leftOn: skipped.count, refused: refused.count),
                isError: false,
                disabled: turnedOff,
                skipped: skipped
            )
        case .failed:
            return restoreAfterFailure(record: &record, store: store, turnedOff: turnedOff)
        }
    }

    public func restore(names: [String]?, tvID: String, store: UndoStore) -> CleanupReport {
        if store.fileExists(tvID: tvID) && store.load(tvID: tvID) == nil {
            return CleanupReport(sentence: CleanupCopy.recordUnreadable, isError: true)
        }
        guard var record = store.load(tvID: tvID) else {
            return CleanupReport(sentence: CleanupCopy.nothingToRestore, isError: false)
        }
        let targets = names ?? record.restorableNames
        let wanted = targets.filter { name in
            record.packages.contains { $0.name == name && ($0.phase == .planned || $0.phase == .disabled) }
        }
        if wanted.isEmpty {
            return CleanupReport(sentence: CleanupCopy.nothingToRestore, isError: false)
        }
        if !echoAnswers() {
            return CleanupReport(sentence: CleanupCopy.unreachableKeepRecord, isError: true)
        }
        var done: [String] = []
        for name in wanted.reversed() {
            do {
                _ = try shell(["pm", "enable", name])
            } catch {
                return CleanupReport(sentence: CleanupCopy.unreachableKeepRecord, isError: true, disabled: done)
            }
            updatePhase(&record, name: name, phase: .restored, at: record.packages.first { $0.name == name }?.disabledAt)
            record.updatedAt = Date()
            do {
                try store.save(record)
            } catch {
                return CleanupReport(sentence: CleanupCopy.unreachableKeepRecord, isError: true, disabled: done)
            }
            done.append(name)
            sleep(pause)
        }
        let sentence = done.count == 1 ? "Turned \(done[0]) back on." : CleanupCopy.restored
        return CleanupReport(sentence: sentence, isError: false, disabled: done)
    }

    private func restoreAfterFailure(record: inout UndoRecord, store: UndoStore, turnedOff: [String]) -> CleanupReport {
        let targets = record.restorableNames.reversed()
        if !echoAnswers() {
            return CleanupReport(sentence: CleanupCopy.unreachableKeepRecord, isError: true, disabled: turnedOff)
        }
        for name in targets {
            do {
                _ = try shell(["pm", "enable", name])
            } catch {
                return CleanupReport(sentence: CleanupCopy.unreachableKeepRecord, isError: true, disabled: turnedOff)
            }
            updatePhase(&record, name: name, phase: .restored, at: record.packages.first { $0.name == name }?.disabledAt)
            record.updatedAt = Date()
            do {
                try store.save(record)
            } catch {
                return CleanupReport(sentence: CleanupCopy.unreachableKeepRecord, isError: true, disabled: turnedOff)
            }
            sleep(pause)
        }
        return CleanupReport(sentence: CleanupCopy.rolledBack, isError: true, disabled: turnedOff)
    }

    private enum Verify {
        case ok
        case failed
    }

    private func verify() -> Verify {
        guard echoAnswers() else { return .failed }
        do {
            let home = try shell([
                "cmd", "package", "resolve-activity",
                "-a", "android.intent.action.MAIN",
                "-c", "android.intent.category.HOME"
            ])
            return CleanupParse.homeResolved(home) ? .ok : .failed
        } catch {
            return .failed
        }
    }

    private func echoAnswers() -> Bool {
        guard let text = try? shell(["echo", "ok"]) else { return false }
        return text.lowercased().contains("ok")
    }

    func collect() throws -> DeviceFacts {
        guard echoAnswers() else {
            throw CleanupFailure.unreachable
        }
        let installed = try readPackages(["pm", "list", "packages"])
        let thirdParty = (try? readPackages(["pm", "list", "packages", "-3"])) ?? []
        let disabled = try readDisabled()
        let homeText = try shell([
            "cmd", "package", "resolve-activity",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.HOME"
        ])
        let home = CleanupParse.componentPackage(from: homeText)
        var homePackages = CleanupParse.componentPackages(from: (try? shell([
            "cmd", "package", "query-activities",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.HOME"
        ])) ?? "")
        if let home { homePackages.insert(home) }
        let imeText = (try? shell(["settings", "get", "secure", "default_input_method"])) ?? ""
        let defaultIME = CleanupParse.componentPackage(from: imeText)
        var enabledIMEs = CleanupParse.componentPackages(from: (try? shell(["ime", "list", "-s"])) ?? "")
        if let defaultIME { enabledIMEs.insert(defaultIME) }
        let web = CleanupParse.webViewPackage(from: (try? shell(["dumpsys", "webviewupdate"])) ?? "")
        let model = CleanupParse.firstLine((try? shell(["getprop", "ro.product.model"])) ?? "")
        let release = CleanupParse.firstLine((try? shell(["getprop", "ro.build.version.release"])) ?? "")
        let setup = CleanupParse.componentPackages(from: (try? shell([
            "cmd", "package", "query-activities",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.SETUP_WIZARD"
        ])) ?? "")
        return DeviceFacts(
            model: model,
            osVersion: release,
            installed: installed,
            thirdParty: thirdParty,
            disabled: disabled,
            homePackage: home,
            homePackages: homePackages,
            defaultIMEPackage: defaultIME,
            enabledIMEPackages: enabledIMEs,
            setupWizardPackages: setup,
            webViewPackage: web
        )
    }

    private func readPackages(_ args: [String]) throws -> Set<String> {
        CleanupParse.packages(from: try shell(args))
    }

    private func readDisabled() throws -> Set<String> {
        try readPackages(["pm", "list", "packages", "-d", "--user", "0"])
    }

    private func shell(_ args: [String]) throws -> String {
        try client.shell(args, serial: serial)
    }

    private func upsert(_ record: inout UndoRecord, _ package: UndoPackage) {
        if let index = record.packages.firstIndex(where: { $0.name == package.name }) {
            record.packages[index] = package
        } else {
            record.packages.append(package)
        }
    }

    private func updatePhase(_ record: inout UndoRecord, name: String, phase: UndoPhase, at: Date?) {
        guard let index = record.packages.firstIndex(where: { $0.name == name }) else { return }
        record.packages[index].phase = phase
        if let at { record.packages[index].disabledAt = at }
    }
}

enum CleanupFailure: Error {
    case unreachable
}

#if SWIFT_PACKAGE
public enum CleanupBundled {
    public static func rules() throws -> NeverTouchRuleSet {
        let data = try Data(contentsOf: try resourceURL("never-touch"))
        return try NeverTouchRuleSet(data: data)
    }

    public static func catalog() throws -> CleanupCatalog {
        let data = try Data(contentsOf: try resourceURL("cleanup-preview"))
        return try CleanupCatalog(data: data)
    }

    private static func resourceURL(_ name: String) throws -> URL {
        if let url = Bundle.module.url(forResource: name, withExtension: "json") { return url }
        if let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") {
            return url
        }
        throw CleanupFailure.unreachable
    }
}
#endif

private struct CatalogFile: Decodable {
    var profiles: CatalogProfiles
}

private struct CatalogProfiles: Decodable {
    var sonyGlobal: [CatalogItem]
    var sonyChina: [CatalogItem]
    var generic: [CatalogItem]
}

private struct CatalogItem: Decodable {
    var pkg: String
    var reason: String
}
#endif
