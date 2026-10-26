import XCTest
@testable import TvRemoteCore

final class CleanupTests: XCTestCase {
    private var rules: NeverTouchRuleSet!
    private var catalog: CleanupCatalog!

    override func setUpWithError() throws {
        rules = try loadRules()
        catalog = try loadCatalog()
    }

    func testBundledNeverTouchResourceLoads() throws {
        let bundled = try CleanupBundled.rules()
        XCTAssertEqual(bundled.version, 1)
        XCTAssertGreaterThanOrEqual(bundled.exactPackages.count, 58)
        XCTAssertEqual(bundled.prefixes.count, 9)
        XCTAssertEqual(bundled.regexSources.count, 1)
        XCTAssertEqual(bundled.denyNamespaces, ["com.sony.", "com.sonyericsson."])
        XCTAssertEqual(bundled.structuralIDs.count, 16)
        XCTAssertTrue(bundled.method.contains("disable-user"))
        XCTAssertTrue(bundled.method.contains("never uninstall"))
        _ = try CleanupBundled.catalog()
    }

    func testExactPrefixRegexAndDeny() throws {
        let matcher = NeverTouchMatcher(rules: rules)
        let empty = DeviceFacts()
        XCTAssertGreaterThanOrEqual(rules.exactPackages.count, 58)
        for name in rules.exactPackages {
            XCTAssertEqual(matcher.matchingRule(package: name, facts: empty, allowListed: true), "exact", name)
        }
        XCTAssertEqual(rules.prefixes.count, 9)
        for entry in rules.prefixes {
            let sample = entry.prefix + "Zz"
            XCTAssertEqual(matcher.matchingRule(package: sample, facts: empty, allowListed: true), "prefix", entry.prefix)
            for exception in entry.exceptions {
                XCTAssertTrue(rules.regexMatches(exception), exception)
                XCTAssertNil(matcher.matchingRule(package: exception, facts: empty, allowListed: true), exception)
            }
        }
        let regexSamples = [
            "android",
            "com.android.systemui",
            "com.android.shell",
            "com.android.phone",
            "com.android.settings",
            "com.android.tv.settings",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.android.ext.services",
            "com.google.android.ext.services",
            "com.android.ext.shared",
            "com.google.android.ext.shared",
            "com.android.modulemetadata",
            "com.google.android.modulemetadata",
            "com.google.android.overlay.modules.foo",
            "com.android.providers.downloads"
        ]
        for sample in regexSamples {
            XCTAssertTrue(rules.regexMatches(sample), sample)
        }
        XCTAssertFalse(rules.regexMatches("com.sony.dtv.promos"))
        XCTAssertEqual(matcher.matchingRule(package: "com.sony.dtv.notreal", facts: empty, allowListed: false), "default_deny")
        XCTAssertEqual(matcher.matchingRule(package: "com.sonyericsson.notreal", facts: empty, allowListed: false), "default_deny")
        XCTAssertNil(matcher.matchingRule(package: "com.sony.dtv.promos", facts: empty, allowListed: true))
        XCTAssertEqual(matcher.matchingRule(package: "com.sony.dtv.tvx", facts: empty, allowListed: true), "exact")
        for name in rules.warningPackages {
            XCTAssertNil(matcher.matchingRule(package: name, facts: empty, allowListed: true), name)
        }
        XCTAssertNil(matcher.matchingRule(package: "com.amazon.wifilocker", facts: empty, allowListed: true))
    }

    func testEveryStructuralCategory() {
        let matcher = NeverTouchMatcher(rules: rules)
        for id in rules.structuralIDs {
            switch id {
            case "home":
                var facts = DeviceFacts(installed: ["com.example.home"])
                facts.homePackage = "com.example.home"
                facts.homePackages = ["com.example.home"]
                XCTAssertEqual(matcher.structuralRule(package: "com.example.home", facts: facts), "home")
                XCTAssertEqual(matcher.matchingRule(package: "com.example.home", facts: facts, allowListed: true), "home")
                XCTAssertEqual(matcher.structuralRule(package: "com.android.tv.settings", facts: DeviceFacts()), "home")
            case "home_pair":
                XCTAssertEqual(
                    matcher.structuralRule(package: "com.google.android.apps.tv.launcherx", facts: DeviceFacts()),
                    "home_pair"
                )
                XCTAssertEqual(
                    matcher.structuralRule(package: "com.google.android.tungsten.setupwraith", facts: DeviceFacts()),
                    "home_pair"
                )
                XCTAssertEqual(
                    matcher.matchingRule(package: "com.google.android.apps.tv.launcherx", facts: DeviceFacts(), allowListed: true),
                    "exact"
                )
            case "ime":
                var facts = DeviceFacts()
                facts.defaultIMEPackage = "com.example.keyboard"
                XCTAssertEqual(matcher.matchingRule(package: "com.example.keyboard", facts: facts, allowListed: true), "ime")
                facts.defaultIMEPackage = nil
                facts.enabledIMEPackages = ["com.example.otherime"]
                XCTAssertEqual(matcher.matchingRule(package: "com.example.otherime", facts: facts, allowListed: true), "ime")
            case "persistent":
                var facts = DeviceFacts()
                facts.persistentPackages = ["com.example.persist"]
                XCTAssertEqual(matcher.matchingRule(package: "com.example.persist", facts: facts, allowListed: true), "persistent")
                facts.persistentPackages = []
                facts.systemUIDPackages = ["com.example.system"]
                XCTAssertEqual(matcher.matchingRule(package: "com.example.system", facts: facts, allowListed: true), "persistent")
            case "tv_input_framework":
                var facts = DeviceFacts()
                facts.tvInputPackages = ["com.example.input"]
                XCTAssertEqual(matcher.matchingRule(package: "com.example.input", facts: facts, allowListed: true), "tv_input_framework")
            case "passthrough_handler":
                var facts = DeviceFacts()
                facts.passthroughPackages = ["com.example.pass"]
                XCTAssertEqual(matcher.matchingRule(package: "com.example.pass", facts: facts, allowListed: true), "passthrough_handler")
                facts.passthroughPackages = []
                facts.settingsHandlerPackages = ["com.example.settingsroute"]
                XCTAssertEqual(matcher.matchingRule(package: "com.example.settingsroute", facts: facts, allowListed: true), "passthrough_handler")
            case "setup_wizard":
                XCTAssertEqual(
                    matcher.matchingRule(package: "com.example.tvsetup", facts: DeviceFacts(), allowListed: true),
                    "setup_wizard"
                )
                XCTAssertEqual(
                    matcher.matchingRule(package: "com.android.provision", facts: DeviceFacts(), allowListed: true),
                    "setup_wizard"
                )
            case "key_events":
                XCTAssertEqual(
                    matcher.matchingRule(package: "com.vendor.kpad", facts: DeviceFacts(), allowListed: true),
                    "key_events"
                )
                var facts = DeviceFacts()
                facts.keyHandlerPackages = ["com.example.keys"]
                XCTAssertEqual(matcher.matchingRule(package: "com.example.keys", facts: facts, allowListed: true), "key_events")
            case "webview":
                var facts = DeviceFacts()
                facts.webViewPackage = "com.example.webview"
                XCTAssertEqual(matcher.matchingRule(package: "com.example.webview", facts: facts, allowListed: true), "webview")
            case "networking":
                XCTAssertEqual(
                    matcher.matchingRule(package: "com.example.networkstack", facts: DeviceFacts(), allowListed: true),
                    "networking"
                )
            case "permission_controller":
                XCTAssertEqual(
                    matcher.structuralRule(package: "com.foo.permissioncontroller", facts: DeviceFacts()),
                    "permission_controller"
                )
                XCTAssertEqual(
                    matcher.matchingRule(package: "com.google.android.permissioncontroller", facts: DeviceFacts(), allowListed: true),
                    "exact"
                )
            case "package_installer":
                XCTAssertEqual(
                    matcher.structuralRule(package: "com.foo.packageinstaller", facts: DeviceFacts()),
                    "package_installer"
                )
            case "vendor_middleware":
                XCTAssertEqual(
                    matcher.matchingRule(package: "com.example.tvapi", facts: DeviceFacts(), allowListed: true),
                    "vendor_middleware"
                )
            case "factory":
                XCTAssertEqual(
                    matcher.structuralRule(package: "com.vendor.factorymode", facts: DeviceFacts()),
                    "factory"
                )
            case "companion_pairs":
                for pair in rules.dependencies {
                    var on = DeviceFacts(installed: [pair.ifEnabled, pair.neverDisable])
                    XCTAssertTrue(matcher.dependencyBlocks(pair.neverDisable, facts: on), pair.neverDisable)
                    on.disabled = [pair.ifEnabled]
                    XCTAssertFalse(matcher.dependencyBlocks(pair.neverDisable, facts: on), pair.neverDisable)
                }
                let facts = DeviceFacts(installed: ["mitv.service", "com.xiaomi.mitv.settings"])
                XCTAssertEqual(
                    matcher.matchingRule(package: "com.xiaomi.mitv.settings", facts: facts, allowListed: true),
                    "companion_pairs"
                )
            case "firmware_refuses":
                XCTAssertNil(matcher.structuralRule(package: "com.example.app", facts: DeviceFacts()))
            default:
                XCTFail("Missing a matcher test for \(id)")
            }
        }
    }

    func testUserFacingCopyAvoidsBannedWords() {
        let sentences = rules.structuralIDs + ["exact", "prefix", "regex", "default_deny", "firmware_refuses"]
        for id in sentences {
            assertSafe(NeverTouchReasons.sentence(id))
        }
        for name in rules.warningPackages {
            assertSafe(NeverTouchReasons.warning(name))
        }
        for item in catalog.sonyGlobal + catalog.sonyChina + catalog.generic {
            assertSafe(item.reason)
            XCTAssertTrue(PackageName.isValid(item.packageName), item.packageName)
            XCTAssertNotEqual(item.reason, rules.exactWhys[item.packageName])
        }
        let copy = [
            CleanupCopy.recoveryTitle,
            CleanupCopy.recoveryBody,
            CleanupCopy.notAnsweringNothingChanged,
            CleanupCopy.homeDidNotAnswer,
            CleanupCopy.rolledBack,
            CleanupCopy.unreachableKeepRecord,
            CleanupCopy.chooseOne,
            CleanupCopy.nothingToRestore,
            CleanupCopy.restored,
            CleanupCopy.recordUnreadable,
            CleanupCopy.finished(disabled: 2, leftOn: 1, refused: 1)
        ]
        for line in copy {
            assertSafe(line)
        }
        XCTAssertFalse(catalog.allows("com.google.android.partnersetup"))
        XCTAssertFalse(catalog.allows("com.google.android.katniss"))
        XCTAssertFalse(catalog.allows("com.sony.dtv.b2b.hotelmode"))
        XCTAssertFalse(catalog.allows("com.google.android.apps.tv.launcherx"))
        XCTAssertFalse(catalog.allows("com.google.android.apps.tv.dreamx"))
        XCTAssertFalse(catalog.sonyChina.map(\.packageName).contains("com.sony.dtv.b2b.ipcontrolsettings"))
        XCTAssertGreaterThanOrEqual(catalog.sonyGlobal.count, 23)
        XCTAssertGreaterThanOrEqual(catalog.sonyChina.count, 19)
        XCTAssertGreaterThanOrEqual(catalog.generic.count, 23)
    }

    func testProfileTicksOnlyKnownGlobalOrGeneric() {
        let china = CleanupProfileDetector.detect(
            brand: .sony,
            model: "VH21",
            installed: ["com.dangbei.TVHomeLauncher", "com.qterics.da.product"]
        )
        XCTAssertEqual(china, .sonyChina)
        XCTAssertFalse(CleanupProfileDetector.ticksSuggestions(china))

        let global = CleanupProfileDetector.detect(
            brand: .sony,
            model: "X900H",
            installed: ["com.google.android.gms", "com.sony.dtv.promos"]
        )
        XCTAssertEqual(global, .sonyGlobal)
        XCTAssertTrue(CleanupProfileDetector.ticksSuggestions(global))

        let unknown = CleanupProfileDetector.detect(brand: .generic, model: "  ", installed: ["com.tcl.bi"])
        XCTAssertEqual(unknown, .unknown)
        XCTAssertFalse(CleanupProfileDetector.ticksSuggestions(unknown))
        XCTAssertEqual(CleanupProfileDetector.detect(brand: .sony, model: "X", installed: []), .unknown)
    }

    func testPreviewFiltersNeverTouchAndLeavesChinaUnticked() {
        let store = UndoStore(directory: temporaryDirectory())
        let runner = makeRunner(fake: CleanupADB(store: store, tvID: "tv-1"), store: store)
        let facts = DeviceFacts(
            model: "VH21",
            osVersion: "12",
            installed: [
                "com.dangbei.TVHomeLauncher",
                "com.qterics.da.product",
                "com.android.settings",
                "com.netflix.ninja",
                "com.sony.dtv.secret",
                "com.android.systemui",
                "com.example.home",
                "com.google.android.katniss"
            ],
            thirdParty: ["com.netflix.ninja", "com.sony.dtv.secret"],
            homePackage: "com.example.home",
            homePackages: ["com.example.home"]
        )
        let preview = runner.makePreview(
            facts: facts,
            brand: .sony,
            extras: ["com.android.systemui", "com.example.added", "com.sony.dtv.secret"]
        )
        XCTAssertEqual(preview.profile, .sonyChina)
        XCTAssertTrue(preview.rows.allSatisfy { !$0.ticked })
        XCTAssertTrue(preview.rows.contains { $0.name == "com.qterics.da.product" })
        XCTAssertTrue(preview.rows.contains { $0.name == "com.netflix.ninja" && $0.reason == "Installed on the TV." })
        XCTAssertFalse(preview.rows.contains { $0.name == "com.android.settings" })
        XCTAssertFalse(preview.rows.contains { $0.name == "com.android.systemui" })
        XCTAssertFalse(preview.rows.contains { $0.name == "com.sony.dtv.secret" })
        XCTAssertTrue(preview.warnings.contains { $0.name == "com.google.android.katniss" && !$0.ticked })
        XCTAssertTrue(preview.rejected.contains { $0.name == "com.android.systemui" })
        XCTAssertTrue(preview.rejected.contains { $0.name == "com.example.added" })
        XCTAssertTrue(preview.rejected.contains { $0.name == "com.sony.dtv.secret" })
        assertSafe(preview.note)
        for row in preview.rows + preview.warnings {
            assertSafe(row.reason)
        }
    }

    func testGlobalPreviewTicksStarterListOnly() {
        let store = UndoStore(directory: temporaryDirectory())
        let runner = makeRunner(fake: CleanupADB(store: store, tvID: "tv-1"), store: store)
        let facts = DeviceFacts(
            model: "X900H",
            osVersion: "12",
            installed: ["com.google.android.gms", "com.sony.dtv.promos", "com.netflix.ninja", "com.example.home"],
            thirdParty: ["com.netflix.ninja"],
            homePackage: "com.example.home",
            homePackages: ["com.example.home"]
        )
        let preview = runner.makePreview(facts: facts, brand: .sony)
        XCTAssertEqual(preview.profile, .sonyGlobal)
        let promos = preview.rows.first { $0.name == "com.sony.dtv.promos" }
        XCTAssertEqual(promos?.ticked, true)
        XCTAssertEqual(preview.rows.first { $0.name == "com.netflix.ninja" }?.ticked, false)
    }

    func testUndoRecordRoundTripAndSafeFileName() throws {
        let directory = temporaryDirectory()
        let store = UndoStore(directory: directory)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        var record = UndoRecord(
            version: 1,
            tvID: "living room/1",
            model: "VH21",
            osVersion: "12",
            createdAt: created,
            updatedAt: created,
            packages: [UndoPackage(name: "com.qterics.da.product", wasEnabled: true, phase: .planned)]
        )
        try store.save(record)
        let loaded = try XCTUnwrap(store.load(tvID: record.tvID))
        XCTAssertEqual(loaded.tvID, record.tvID)
        XCTAssertEqual(loaded.model, "VH21")
        XCTAssertEqual(loaded.osVersion, "12")
        XCTAssertEqual(loaded.packages, record.packages)
        XCTAssertEqual(loaded.createdAt.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 1)
        record.packages[0].phase = .disabled
        record.packages[0].disabledAt = created
        record.updatedAt = created
        try store.save(record)
        XCTAssertEqual(store.load(tvID: record.tvID)?.packages.first?.phase, .disabled)
        XCTAssertEqual(store.load(tvID: record.tvID)?.packages.first?.wasEnabled, true)

        let url = store.fileURL(tvID: "a/b")
        XCTAssertEqual(url.lastPathComponent, "undo-a_b.json")
        XCTAssertTrue(url.path.hasPrefix(directory.path))
        XCTAssertFalse(url.lastPathComponent.contains("/"))
    }

    func testDisableWritesUndoBeforeTheCommandAndUsesDisableUser() throws {
        let directory = temporaryDirectory()
        let store = UndoStore(directory: directory)
        let fake = CleanupADB(store: store, tvID: "tv-1")
        fake.installed = [
            "com.google.android.gms",
            "tv.samba.ssm",
            "com.sony.dtv.promos",
            "com.example.home",
            "com.example.ime"
        ]
        let sleeps = SleepLog()
        let runner = makeRunner(fake: fake, store: store, pause: 0.15, sleeps: sleeps)
        let report = runner.disable(names: ["tv.samba.ssm", "com.sony.dtv.promos"], brand: .sony, tvID: "tv-1", store: store)
        XCTAssertFalse(report.isError, report.sentence)
        XCTAssertEqual(report.disabled, ["tv.samba.ssm", "com.sony.dtv.promos"])
        XCTAssertEqual(fake.sawPlannedAtDisable, ["tv.samba.ssm", "com.sony.dtv.promos"])
        let saved = try XCTUnwrap(store.load(tvID: "tv-1"))
        XCTAssertEqual(saved.model, "LivingRoom")
        XCTAssertEqual(saved.osVersion, "12")
        XCTAssertEqual(saved.packages.map(\.phase), [.disabled, .disabled])
        XCTAssertTrue(saved.packages.allSatisfy { $0.wasEnabled && $0.disabledAt != nil })
        let disables = fake.calls.map(\.arguments).filter { $0.contains("disable-user") }
        XCTAssertEqual(disables.count, 2)
        XCTAssertEqual(Array(disables[0].suffix(5)), ["pm", "disable-user", "--user", "0", "tv.samba.ssm"])
        XCTAssertEqual(Array(disables[1].suffix(5)), ["pm", "disable-user", "--user", "0", "com.sony.dtv.promos"])
        XCTAssertEqual(sleeps.values, [0.15, 0.15])
        XCTAssertTrue(fake.calls.contains { $0.environment["TMPDIR"] == "/tmp/zapbar-cleanup" })
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("uninstall") })
        assertSafe(report.sentence)
    }

    func testRuntimeGateBlocksTypedAndPersistentPackages() throws {
        let directory = temporaryDirectory()
        let store = UndoStore(directory: directory)
        let fake = CleanupADB(store: store, tvID: "tv-1")
        fake.installed = ["com.android.systemui", "com.example.home", "com.example.persist"]
        let runner = makeRunner(fake: fake, store: store)
        let blocked = runner.disable(names: ["com.android.systemui"], brand: .generic, tvID: "tv-1", store: store)
        XCTAssertTrue(blocked.sentence.contains("Nothing was turned off"))
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("disable-user") })
        XCTAssertFalse(store.fileExists(tvID: "tv-1"))
        assertSafe(blocked.sentence)

        fake.dumpsys["com.example.persist"] = "pkgFlags=[ SYSTEM PERSISTENT ]\nsharedUser=android.uid.system\n"
        let gated = runner.disable(names: ["com.example.persist"], brand: .generic, tvID: "tv-1", store: store)
        XCTAssertTrue(fake.sawPlannedAtDumpsys)
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("disable-user") })
        XCTAssertEqual(store.load(tvID: "tv-1")?.packages.first?.phase, .blocked)
        XCTAssertTrue(gated.sentence.contains("Nothing was turned off"))
        assertSafe(gated.sentence)
    }

    func testFirmwareReadBackMarksARefusal() throws {
        let directory = temporaryDirectory()
        let store = UndoStore(directory: directory)
        let fake = CleanupADB(store: store, tvID: "tv-1")
        fake.installed = ["com.google.android.gms", "tv.samba.ssm", "com.example.home"]
        fake.ignoreDisable = true
        let runner = makeRunner(fake: fake, store: store)
        let report = runner.disable(names: ["tv.samba.ssm"], brand: .sony, tvID: "tv-1", store: store)
        XCTAssertEqual(store.load(tvID: "tv-1")?.packages.first?.phase, .refused)
        XCTAssertTrue(report.sentence.contains("The TV left 1 on."))
        XCTAssertTrue(report.disabled.isEmpty)
        assertSafe(report.sentence)
    }

    func testFailedHomeCheckRestoresInReverse() throws {
        let directory = temporaryDirectory()
        let store = UndoStore(directory: directory)
        let fake = CleanupADB(store: store, tvID: "tv-1")
        fake.installed = ["com.google.android.gms", "tv.samba.ssm", "com.sony.dtv.promos", "com.example.home"]
        fake.breakHomeAfterDisable = true
        let runner = makeRunner(fake: fake, store: store)
        let report = runner.disable(names: ["tv.samba.ssm", "com.sony.dtv.promos"], brand: .sony, tvID: "tv-1", store: store)
        XCTAssertEqual(report.sentence, CleanupCopy.rolledBack)
        XCTAssertTrue(report.isError)
        let enables = fake.calls.map(\.arguments).filter { $0.contains("enable") && $0.contains("pm") }
        XCTAssertEqual(Array(enables[0].suffix(3)), ["pm", "enable", "com.sony.dtv.promos"])
        XCTAssertEqual(Array(enables[1].suffix(3)), ["pm", "enable", "tv.samba.ssm"])
        XCTAssertEqual(store.load(tvID: "tv-1")?.packages.map(\.phase), [.restored, .restored])
        assertSafe(report.sentence)
    }

    func testUnreachableRestoreKeepsTheRecord() throws {
        let directory = temporaryDirectory()
        let store = UndoStore(directory: directory)
        let fake = CleanupADB(store: store, tvID: "tv-1")
        fake.installed = ["com.google.android.gms", "tv.samba.ssm", "com.example.home"]
        fake.failEchoAfterDisable = true
        let runner = makeRunner(fake: fake, store: store)
        let report = runner.disable(names: ["tv.samba.ssm"], brand: .sony, tvID: "tv-1", store: store)
        XCTAssertEqual(report.sentence, CleanupCopy.unreachableKeepRecord)
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("enable") && $0.arguments.contains("pm") })
        XCTAssertEqual(store.load(tvID: "tv-1")?.packages.first?.phase, .disabled)
        let again = runner.restore(names: nil, tvID: "tv-1", store: store)
        XCTAssertEqual(again.sentence, CleanupCopy.unreachableKeepRecord)
        XCTAssertEqual(store.load(tvID: "tv-1")?.packages.first?.phase, .disabled)
        assertSafe(again.sentence)
    }

    func testRestoreOneAndAll() throws {
        let directory = temporaryDirectory()
        let store = UndoStore(directory: directory)
        let created = Date(timeIntervalSince1970: 1_700_000_100)
        let record = UndoRecord(
            version: 1,
            tvID: "tv-1",
            model: "LivingRoom",
            osVersion: "12",
            createdAt: created,
            updatedAt: created,
            packages: [
                UndoPackage(name: "tv.samba.ssm", wasEnabled: true, phase: .disabled, disabledAt: created),
                UndoPackage(name: "com.sony.dtv.promos", wasEnabled: true, phase: .disabled, disabledAt: created)
            ]
        )
        try store.save(record)
        let fake = CleanupADB(store: store, tvID: "tv-1")
        let runner = makeRunner(fake: fake, store: store)
        let all = runner.restore(names: nil, tvID: "tv-1", store: store)
        XCTAssertEqual(all.sentence, CleanupCopy.restored)
        XCTAssertEqual(store.load(tvID: "tv-1")?.restorableNames, [])
        let enables = fake.calls.map(\.arguments).filter { $0.contains("pm") && $0.contains("enable") }
        XCTAssertEqual(Array(enables[0].suffix(3)), ["pm", "enable", "com.sony.dtv.promos"])
        XCTAssertEqual(Array(enables[1].suffix(3)), ["pm", "enable", "tv.samba.ssm"])
        try store.save(record)
        let one = runner.restore(names: ["tv.samba.ssm"], tvID: "tv-1", store: store)
        XCTAssertEqual(one.sentence, "Turned tv.samba.ssm back on.")
        XCTAssertEqual(store.load(tvID: "tv-1")?.restorableNames, ["com.sony.dtv.promos"])
        assertSafe(one.sentence)
        assertSafe(all.sentence)
    }

    func testCorruptUndoFileIsLeftInPlace() throws {
        let directory = temporaryDirectory()
        let store = UndoStore(directory: directory)
        let url = store.fileURL(tvID: "tv-1")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let fake = CleanupADB(store: store, tvID: "tv-1")
        fake.installed = ["tv.samba.ssm", "com.example.home", "com.google.android.gms"]
        let runner = makeRunner(fake: fake, store: store)
        let report = runner.disable(names: ["tv.samba.ssm"], brand: .sony, tvID: "tv-1", store: store)
        XCTAssertEqual(report.sentence, CleanupCopy.recordUnreadable)
        XCTAssertEqual(try String(contentsOf: url), "not json")
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("disable-user") })
        let restore = runner.restore(names: nil, tvID: "tv-1", store: store)
        XCTAssertEqual(restore.sentence, CleanupCopy.recordUnreadable)
        XCTAssertEqual(try String(contentsOf: url), "not json")
    }

    func testPreviewAsksTheTVForThirdPartyPackages() throws {
        let store = UndoStore(directory: temporaryDirectory())
        let fake = CleanupADB(store: store, tvID: "tv-1")
        fake.model = "TCL"
        fake.installed = ["com.tcl.bi", "com.example.home", "com.netflix.ninja"]
        fake.thirdParty = ["com.netflix.ninja"]
        let runner = makeRunner(fake: fake, store: store)
        let preview = try runner.preview(brand: .generic)
        XCTAssertEqual(preview.profile, .generic)
        XCTAssertEqual(preview.rows.first { $0.name == "com.tcl.bi" }?.ticked, true)
        XCTAssertEqual(preview.rows.first { $0.name == "com.netflix.ninja" }?.ticked, false)
        let lists = fake.calls.map(\.arguments).filter { $0.contains("list") && $0.contains("packages") }
        XCTAssertTrue(lists.contains { $0.contains("-3") })
        XCTAssertTrue(lists.contains { $0.contains("-d") })
        assertSafe(preview.note)
    }

    func testDeadTVChangesNothing() {
        let store = UndoStore(directory: temporaryDirectory())
        let fake = CleanupADB(store: store, tvID: "tv-1")
        fake.echoDead = true
        let runner = makeRunner(fake: fake, store: store)
        let report = runner.disable(names: ["tv.samba.ssm"], brand: .sony, tvID: "tv-1", store: store)
        XCTAssertEqual(report.sentence, CleanupCopy.notAnsweringNothingChanged)
        XCTAssertFalse(store.fileExists(tvID: "tv-1"))
    }

    func testCleanupConnectionNeedsADebuggingLink() {
        var settings = Settings.factoryDefaults()
        settings.host = ""
        let session = RemoteSession(settings: settings, runner: FakeRunner(), fileExists: { _ in false })
        XCTAssertNil(session.cleanupConnection())
    }

    func testSetupDoesNotMentionCleanUp() {
        let phases: [WizardPhase] = [.pickBrand, .find, .manual, .sonyTyping, .debugging, .pair, .allow, .sonyKey, .remember, .done]
        for phase in phases {
            for brand in [TvBrand.sony, .generic, .xiaomi] {
                for line in SetupCopy.lines(phase: phase, brand: brand, wantsTyping: true) {
                    XCTAssertFalse(line.text.localizedCaseInsensitiveContains("clean up"), line.text)
                    assertSafe(line.text)
                }
            }
        }
    }

    func testReleaseScriptLeavesTheFlagOff() throws {
        let root = repoRoot()
        let release = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        let dev = try String(contentsOf: root.appendingPathComponent("scripts/build-dev.sh"), encoding: .utf8)
        XCTAssertTrue(release.contains("ZAPBAR_ADVANCED:-0"))
        XCTAssertTrue(dev.contains("ZAPBAR_ADVANCED=1"))
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        XCTAssertTrue(readme.contains("until Jim says go"))
        XCTAssertTrue(changelog.contains("until Jim says go"))
    }

    func testEmulatorLabStillSkipped() throws {
        throw XCTSkip("Clean-up on a TV image stays in the emulator lab. See docs/untested-lab.md. Linux tests use a fake adb.")
    }

    private func loadRules() throws -> NeverTouchRuleSet {
        if let bundled = try? CleanupBundled.rules() { return bundled }
        return try NeverTouchRuleSet(data: Data(contentsOf: resourceFile("never-touch.json")))
    }

    private func loadCatalog() throws -> CleanupCatalog {
        if let bundled = try? CleanupBundled.catalog() { return bundled }
        return try CleanupCatalog(data: Data(contentsOf: resourceFile("cleanup-preview.json")))
    }

    private func resourceFile(_ name: String) -> URL {
        repoRoot()
            .appendingPathComponent("Sources/TvRemoteCore/Resources")
            .appendingPathComponent(name)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("zapbar-cleanup-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeRunner(fake: CleanupADB, store: UndoStore, pause: TimeInterval = 0, sleeps: SleepLog? = nil) -> CleanupRunner {
        let client = AdbClient(
            runner: fake,
            adbPath: "/usr/bin/adb",
            temporaryDirectory: "/tmp/zapbar-cleanup",
            serverSocket: "tcp:localhost:5037"
        )
        return CleanupRunner(
            client: client,
            serial: "192.0.2.20:5555",
            rules: rules,
            catalog: catalog,
            pause: pause,
            sleep: { interval in
                fake.sleeps.append(interval)
                sleeps?.values.append(interval)
            }
        )
    }

    private func assertSafe(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(text.contains("Android"), text, file: file, line: line)
        XCTAssertFalse(text.contains("android"), text, file: file, line: line)
        XCTAssertFalse(text.contains("Sony Bravia"), text, file: file, line: line)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("todo"), text, file: file, line: line)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("tbd"), text, file: file, line: line)
    }
}

private final class SleepLog {
    var values: [TimeInterval] = []
}

private final class CleanupADB: CommandRunning {
    struct Call {
        var arguments: [String]
        var environment: [String: String]
    }

    var calls: [Call] = []
    var disabled = Set<String>()
    var installed: [String] = []
    var thirdParty: [String] = []
    var dumpsys: [String: String] = [:]
    var model = "LivingRoom"
    var release = "12"
    var home = "com.example.home/.Home"
    var ime = "com.example.ime/.IME"
    var breakHomeAfterDisable = false
    var failEchoAfterDisable = false
    var ignoreDisable = false
    var homeBroken = false
    var echoDead = false
    var sleeps: [TimeInterval] = []
    var sawPlannedAtDisable: [String] = []
    var sawPlannedAtDumpsys = false
    let store: UndoStore
    let tvID: String

    init(store: UndoStore, tvID: String) {
        self.store = store
        self.tvID = tvID
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        try run(executable, arguments: arguments, timeout: timeout, environment: [:])
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval, environment: [String: String]) throws -> CommandResult {
        calls.append(Call(arguments: arguments, environment: environment))
        let parts = shellParts(arguments)
        if parts.first == "echo" {
            if echoDead { return CommandResult(status: 1, stdout: "", stderr: "closed") }
            return CommandResult(status: 0, stdout: "ok\n", stderr: "")
        }
        if parts.first == "dumpsys" && parts.contains("webviewupdate") {
            return CommandResult(status: 0, stdout: "Current WebView package (name, version): (com.example.webview, 1)\n", stderr: "")
        }
        if parts.first == "dumpsys" && parts.contains("package") {
            let pkg = parts.last ?? ""
            if let record = store.load(tvID: tvID),
               record.packages.contains(where: { $0.name == pkg && $0.phase == .planned }) {
                sawPlannedAtDumpsys = true
            }
            return CommandResult(status: 0, stdout: dumpsys[pkg] ?? "Package [\(pkg)]\n", stderr: "")
        }
        if parts.first == "getprop" && parts.contains("ro.product.model") {
            return CommandResult(status: 0, stdout: model + "\n", stderr: "")
        }
        if parts.first == "getprop" {
            return CommandResult(status: 0, stdout: release + "\n", stderr: "")
        }
        if parts.first == "settings" {
            return CommandResult(status: 0, stdout: ime + "\n", stderr: "")
        }
        if parts.first == "ime" {
            return CommandResult(status: 0, stdout: ime + "\n", stderr: "")
        }
        if parts.contains("disable-user") {
            let pkg = parts.last ?? ""
            if let record = store.load(tvID: tvID),
               record.packages.contains(where: { $0.name == pkg && $0.phase == .planned && $0.wasEnabled }) {
                sawPlannedAtDisable.append(pkg)
            }
            if !ignoreDisable { disabled.insert(pkg) }
            if breakHomeAfterDisable { homeBroken = true }
            if failEchoAfterDisable { echoDead = true }
            return CommandResult(status: 0, stdout: "Package \(pkg) new state: disabled-user\n", stderr: "")
        }
        if parts.first == "pm" && parts.contains("enable") {
            disabled.remove(parts.last ?? "")
            return CommandResult(status: 0, stdout: "Package \(parts.last ?? "") new state: enabled\n", stderr: "")
        }
        if parts.first == "pm" && parts.contains("list") {
            let names: [String]
            if parts.contains("-d") {
                names = Array(disabled)
            } else if parts.contains("-3") {
                names = thirdParty
            } else {
                names = installed
            }
            let text = names.map { "package:\($0)" }.joined(separator: "\n")
            return CommandResult(status: 0, stdout: text + "\n", stderr: "")
        }
        if parts.contains("query-activities") {
            if parts.contains("android.intent.category.SETUP_WIZARD") {
                return CommandResult(status: 0, stdout: "", stderr: "")
            }
            return CommandResult(status: 0, stdout: home + "\n", stderr: "")
        }
        if parts.contains("resolve-activity") {
            if homeBroken {
                return CommandResult(status: 0, stdout: "No activity found\n", stderr: "")
            }
            return CommandResult(status: 0, stdout: "priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true\n\(home)\n", stderr: "")
        }
        return CommandResult(status: 0, stdout: "", stderr: "")
    }

    private func shellParts(_ arguments: [String]) -> [String] {
        guard let index = arguments.firstIndex(of: "shell") else { return arguments }
        return Array(arguments.suffix(from: arguments.index(after: index)))
    }
}
