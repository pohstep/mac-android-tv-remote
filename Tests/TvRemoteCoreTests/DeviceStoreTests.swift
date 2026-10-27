import XCTest
@testable import TvRemoteCore

final class DeviceStoreTests: XCTestCase {
    func testLegacySettingsBecomeTheFirstTelevision() throws {
        let raw = """
        {"host":"192.0.2.8","port":5555,"adbPath":"/usr/local/bin/adb","wolEnabled":true,\
        "macAddress":"aa:bb:cc:dd:ee:ff","broadcastAddress":"192.0.2.255","apps":[{"id":"netflix","name":"Netflix","packageName":"com.netflix.ninja","favourite":true}],\
        "keyboardMode":true,"sonyPort":20080}
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(raw.utf8))
        XCTAssertEqual(decoded.host, "192.0.2.8")
        XCTAssertEqual(decoded.port, 5555)
        XCTAssertEqual(decoded.adbPath, "/usr/local/bin/adb")
        XCTAssertEqual(decoded.macAddress, "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(decoded.broadcastAddress, "192.0.2.255")
        XCTAssertTrue(decoded.keyboardMode)
        XCTAssertEqual(decoded.sonyPort, 20080)
        XCTAssertEqual(decoded.apps.map(\.packageName), ["com.netflix.ninja"])
        XCTAssertEqual(decoded.devices.count, 1)
        let tv = try XCTUnwrap(decoded.devices.first)
        XCTAssertEqual(tv.id, "legacy")
        XCTAssertEqual(tv.brand, .sony)
        XCTAssertEqual(tv.host, "192.0.2.8")
        XCTAssertEqual(tv.port, 5555)
        XCTAssertEqual(tv.macAddress, "aa:bb:cc:dd:ee:ff")
        XCTAssertEqual(tv.controlPort, 20080)
        XCTAssertTrue(tv.preferred)
        XCTAssertTrue(tv.useDebugging)
        XCTAssertEqual(decoded.activeDeviceID, "legacy")

        let saved = try JSONEncoder().encode(decoded)
        let text = String(data: saved, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("psk"))
        XCTAssertFalse(text.contains("secret-key"))
        XCTAssertFalse(text.contains("wolEnabled"))
    }

    func testEmptyHostDoesNotInventADevice() throws {
        let raw = #"{"host":"  ","port":5555,"sonyPort":80}"#
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(raw.utf8))
        XCTAssertTrue(decoded.devices.isEmpty)
        XCTAssertEqual(decoded.activeDeviceID, "")
        XCTAssertEqual(StoredTV.migrateLegacy(host: "", port: 5555, macAddress: "", controlPort: 80), [])
    }

    func testPresentDeviceListIsNotReplaced() throws {
        let raw = #"{"host":"192.0.2.8","port":5555,"devices":[]}"#
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(raw.utf8))
        XCTAssertTrue(decoded.devices.isEmpty)
        XCTAssertEqual(decoded.host, "192.0.2.8")
    }

    func testSwitcherReconnectsToTheLastTelevision() {
        let older = StoredTV(id: "a", name: "A", brand: .sony, host: "192.0.2.1", port: 5555, lastSeen: Date(timeIntervalSince1970: 10), preferred: true)
        let newer = StoredTV(id: "b", name: "B", brand: .generic, host: "192.0.2.2", port: 5555, lastSeen: Date(timeIntervalSince1970: 20))
        var switcher = DeviceSwitcher(devices: [older, newer], activeID: "")
        XCTAssertEqual(switcher.reconnectTarget()?.id, "b")
        switcher.activeID = "a"
        XCTAssertEqual(switcher.reconnectTarget()?.id, "a")

        switcher.select("b", seenAt: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(switcher.activeID, "b")
        XCTAssertEqual(switcher.devices.first { $0.id == "b" }?.lastSeen, Date(timeIntervalSince1970: 30))

        switcher.setPreferred("a")
        XCTAssertEqual(switcher.devices.filter(\.preferred).map(\.id), ["a"])

        let added = StoredTV(id: "", name: "Den", brand: .xiaomi, host: "192.0.2.3", port: 6095)
        switcher.remember(added, seenAt: Date(timeIntervalSince1970: 40))
        XCTAssertEqual(switcher.devices.count, 3)
        XCTAssertEqual(switcher.active()?.host, "192.0.2.3")
        XCTAssertFalse(switcher.active()?.id.isEmpty ?? true)
    }

    func testSettingsFolderPrefersZapbarThenTheOldFile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modern = Settings.applicationSupportURL(homeDirectory: home.path)
        let legacy = Settings.legacyApplicationSupportURL(homeDirectory: home.path)
        XCTAssertTrue(modern.path.contains("Zapbar"))
        XCTAssertTrue(legacy.path.contains("Pohstep Remote"))
        XCTAssertEqual(Settings.resolvedSettingsURL(homeDirectory: home.path).path, modern.path)

        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy)
        XCTAssertEqual(Settings.resolvedSettingsURL(homeDirectory: home.path).path, legacy.path)

        try FileManager.default.createDirectory(at: modern.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modern)
        XCTAssertEqual(Settings.resolvedSettingsURL(homeDirectory: home.path).path, modern.path)
    }
}
