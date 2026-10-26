import XCTest
@testable import TvRemoteCore

final class XiaomiTests: XCTestCase {
    func testKeyMapAndCommandURLs() {
        XCTAssertEqual(XiaomiKey.code(for: .dpadCenter), 23)
        XCTAssertEqual(XiaomiKey.code(for: .sleep), 223)
        XCTAssertEqual(XiaomiKey.code(for: .volumeMute), 164)
        XCTAssertNil(XiaomiKey.code(for: .wakeup))
        XCTAssertNil(XiaomiKey.code(for: .power))
        XCTAssertNil(XiaomiKey.code(for: .hdmi1))

        XCTAssertEqual(
            XiaomiCommand.alive(host: "192.0.2.40", port: 6095)?.absoluteString,
            "http://192.0.2.40:6095/request?action=isalive"
        )
        XCTAssertEqual(
            XiaomiCommand.key(host: "192.0.2.40", port: 6095, code: 23)?.absoluteString,
            "http://192.0.2.40:6095/controller?action=keyevent&keycode=23"
        )
        let launch = XiaomiCommand.launch(host: "192.0.2.40", port: 6095, package: "com.netflix.ninja")?.absoluteString ?? ""
        XCTAssertTrue(launch.contains("action=startapp"))
        XCTAssertTrue(launch.contains("type=packagename"))
        XCTAssertTrue(launch.contains("packagename=com.netflix.ninja"))
        XCTAssertEqual(
            XiaomiCommand.source(host: "192.0.2.40", port: 6095, hdmi: 2)?.absoluteString,
            "http://192.0.2.40:6095/controller?action=changesource&source=hdmi2"
        )
        XCTAssertNil(XiaomiCommand.source(host: "192.0.2.40", port: 6095, hdmi: 9))
        XCTAssertTrue(XiaomiCommand.succeeded(status: 200, body: #"{"status":0}"#))
        XCTAssertFalse(XiaomiCommand.succeeded(status: 200, body: #"{"status":1}"#))
        XCTAssertFalse(XiaomiCommand.succeeded(status: 500, body: #"{"status":0}"#))
    }

    func testClientUsesTheInjectedReader() {
        let reader = ScriptedReader()
        reader.script = [
            HttpReply(status: 200, body: Data(#"{"status":0,"data":{"devicename":"Den"}}"#.utf8)),
            HttpReply(status: 200, body: Data(#"{"status":0}"#.utf8)),
            HttpReply(status: 200, body: Data(#"{"status":0}"#.utf8)),
            HttpReply(status: 200, body: Data(#"{"status":0}"#.utf8))
        ]
        let client = XiaomiClient(reader: reader)
        XCTAssertEqual(client.alive(host: "192.0.2.40", port: 6095), "Den")
        XCTAssertTrue(client.sendKey(23, host: "192.0.2.40", port: 6095))
        XCTAssertTrue(client.launch(package: "com.netflix.ninja", host: "192.0.2.40", port: 6095))
        XCTAssertTrue(client.selectHDMI(2, host: "192.0.2.40", port: 6095))
        XCTAssertEqual(reader.urls.map(\.path), ["/request", "/controller", "/controller", "/controller"])
        XCTAssertTrue(reader.urls[1].absoluteString.contains("keycode=23"))

        let backend = XiaomiTVBackend()
        let context = TvActionContext(
            host: "192.0.2.40",
            adbPort: 6095,
            controlPort: 6095,
            psk: "",
            serial: nil,
            adb: nil,
            http: ScriptedHTTP(),
            reader: reader,
            isPlaying: false,
            allowSony: false
        )
        let wake = backend.power(on: true, context: context)
        XCTAssertTrue(wake.isError)
        XCTAssertEqual(wake.title, "Couldn't wake the TV")
        let typed = backend.sendText("hi", context: context)
        XCTAssertTrue(typed.isError)
        XCTAssertEqual(typed.detail, "This TV can't type from the remote.")
    }

    func testMockScriptAnswersOnLocalhost() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = root.appendingPathComponent("scripts/mock-xiaomi.py")
        let refused = Process()
        refused.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        refused.arguments = [script.path, "9", "/tmp/zapbar-mock-should-not"]
        refused.environment = ProcessInfo.processInfo.environment.merging(["POHSTEP_REAL_TV": "9"], uniquingKeysWith: { $1 })
        try refused.run()
        refused.waitUntilExit()
        XCTAssertEqual(refused.terminationStatus, 3)

        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("zapbar-xiaomi-\(UUID().uuidString).log")
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [script.path, "0", logURL.path]
        let output = Pipe()
        server.standardOutput = output
        server.standardError = Pipe()
        try server.run()
        defer { server.terminate() }
        let announced = output.fileHandleForReading.availableData
        let line = String(data: announced, encoding: .utf8) ?? ""
        XCTAssertTrue(line.hasPrefix("READY "))
        let port = Int(line.replacingOccurrences(of: "READY ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        XCTAssertGreaterThan(port, 0)

        let client = XiaomiClient(reader: URLSessionHttp(), timeout: 3)
        XCTAssertEqual(client.alive(host: "127.0.0.1", port: port), "Mock TV")
        XCTAssertTrue(client.sendKey(23, host: "127.0.0.1", port: port))
        XCTAssertTrue(client.launch(package: "com.netflix.ninja", host: "127.0.0.1", port: port))
        XCTAssertTrue(client.selectHDMI(2, host: "127.0.0.1", port: port))
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(log.contains("\"action\": \"keyevent\""))
        XCTAssertTrue(log.contains("\"keycode\": \"23\""))
        XCTAssertTrue(log.contains("\"action\": \"startapp\""))
        XCTAssertTrue(log.contains("\"source\": \"hdmi2\""))
    }
}

private final class ScriptedReader: HttpReading {
    var urls: [URL] = []
    var script: [HttpReply] = []

    func get(url: URL, timeout: TimeInterval) throws -> HttpReply {
        urls.append(url)
        if script.isEmpty {
            throw RemoteError.commandFailed("no scripted reply")
        }
        return script.removeFirst()
    }
}
