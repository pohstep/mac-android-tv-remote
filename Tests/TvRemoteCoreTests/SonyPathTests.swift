import XCTest
@testable import TvRemoteCore

final class ScriptedHTTP: HttpSending {
    struct Call: Equatable {
        var url: String
        var headers: [String: String]
        var body: String
    }

    var calls: [Call] = []
    var script: [HttpReply] = []

    func send(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) throws -> HttpReply {
        calls.append(Call(url: url.absoluteString, headers: headers, body: String(data: body, encoding: .utf8) ?? ""))
        if script.isEmpty {
            throw RemoteError.commandFailed("no scripted reply")
        }
        return script.removeFirst()
    }
}

final class SonyPathTests: XCTestCase {
    private let secret = "pohstep-test-psk-9f3a"

    func testIrccCodesMatchThePublishedTable() {
        XCTAssertEqual(IrccCode.value(.up), "AAAAAQAAAAEAAAB0Aw==")
        XCTAssertEqual(IrccCode.value(.hdmi(1)), "AAAAAgAAABoAAABaAw==")
        XCTAssertEqual(IrccCode.value(.hdmi(4)), "AAAAAgAAABoAAABdAw==")
        XCTAssertEqual(IrccCode.value(.digit(1)), "AAAAAQAAAAEAAAAAAw==")
        XCTAssertEqual(IrccCode.value(.digit(0)), "AAAAAQAAAAEAAAAJAw==")
        let soap = String(data: IrccSoap.body(code: IrccCode.value(.confirm) ?? ""), encoding: .utf8) ?? ""
        XCTAssertTrue(soap.contains("AAAAAQAAAAEAAABlAw=="))
        XCTAssertFalse(soap.contains("X-Auth-PSK"))
    }

    func testParsersReadPowerVolumeAndInputs() {
        let power = Data(#"{"result":[{"status":"active"}],"id":1}"#.utf8)
        XCTAssertEqual(SonyParse.power(power), .on)
        let standby = Data(#"{"result":[{"status":"standby"}],"id":1}"#.utf8)
        XCTAssertEqual(SonyParse.power(standby), .off)
        let volume = Data(#"{"result":[[{"target":"speaker","volume":18,"mute":false,"maxVolume":100}]],"id":1}"#.utf8)
        XCTAssertEqual(SonyParse.volume(volume)?.volume, 18)
        let inputs = Data(#"{"result":[[{"uri":"extInput:hdmi?port=2","title":"HDMI 2","label":"Apple TV","connection":true}]],"id":1}"#.utf8)
        XCTAssertEqual(SonyParse.inputs(inputs).first?.displayName, "Apple TV")
        XCTAssertEqual(SonyParse.inputs(inputs).first?.menuTitle, "HDMI 2 · Apple TV")
        XCTAssertEqual(SonyParse.hdmiURI(port: 3), "extInput:hdmi?port=3")
    }

    func testScreenDumpReadsTheForegroundAppAndNowPlaying() {
        let window = "mCurrentFocus=Window{548e5e0 u0 com.netflix.ninja/com.netflix.ninja.MainActivity}"
        XCTAssertEqual(ScreenDump.foregroundPackage(window), "com.netflix.ninja")
        let media = """
        state=PlaybackState {state=3, position=0}
        android.media.metadata.TITLE=The Beef
        android.media.metadata.ARTIST=The Bear
        """
        let playing = ScreenDump.nowPlaying(media)
        XCTAssertEqual(playing?.line, "The Beef — The Bear")
        XCTAssertEqual(playing?.isPlaying, true)
    }

    func testRedactionStripsTheKeyFromAnythingWeMightPrint() {
        let wire = SonyWire.redacted(
            headers: ["X-Auth-PSK": secret, "Content-Type": "application/json"],
            body: "echo \(secret)",
            secret: secret
        )
        XCTAssertFalse(wire.contains(secret))
        XCTAssertTrue(wire.contains("redacted"))
    }

    func testSonyButtonDoesNotCallAdbAndDoesNotEchoTheKey() {
        let http = ScriptedHTTP()
        http.script = [HttpReply(status: 200, body: Data("{}".utf8))]
        let runner = FakeRunner()
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        let session = RemoteSession(
            settings: settings,
            runner: runner,
            http: http,
            fileExists: { _ in false },
            pathEnvironment: "",
            homeDirectory: "/Users/tester"
        )
        session.setPreSharedKey(secret)
        let report = session.press(.dpadUp)
        XCTAssertFalse(report.isError)
        XCTAssertEqual(report.detail, "Sent over Sony IP")
        XCTAssertFalse(report.title.contains(secret))
        XCTAssertFalse(report.detail.contains(secret))
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertEqual(http.calls.first?.headers["X-Auth-PSK"], secret)
        XCTAssertTrue(http.calls.first?.body.contains("AAAAAQAAAAEAAAB0Aw==") == true)
        XCTAssertTrue(http.calls.first?.url.contains("127.0.0.1") == true)
        XCTAssertFalse(http.calls.first?.url.contains("192.0.2.57") == true)
    }

    func testSonyFailureFallsBackToAdb() {
        let http = ScriptedHTTP()
        http.script = [HttpReply(status: 403, body: Data("{\"error\":[403,\"\(secret)\"]}".utf8))]
        let runner = FakeRunner()
        runner.script = [
            .success(CommandResult(status: 0, stdout: "connected to 127.0.0.1:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n127.0.0.1:5555\tdevice\n", stderr: "")),
            .success(CommandResult(status: 0, stdout: "", stderr: ""))
        ]
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        settings.adbPath = "/usr/local/bin/adb"
        let session = RemoteSession(
            settings: settings,
            runner: runner,
            http: http,
            fileExists: { $0 == "/usr/local/bin/adb" },
            pathEnvironment: "",
            homeDirectory: "/Users/tester"
        )
        session.setPreSharedKey(secret)
        _ = session.refresh()
        let report = session.press(.dpadDown)
        XCTAssertFalse(report.isError)
        XCTAssertFalse(report.detail.contains(secret))
        XCTAssertEqual(runner.calls.last?.arguments, ["-P", "5037"] + AdbCommands.keyEvent(serial: "127.0.0.1:5555", key: .dpadDown))
    }

    func testVolumeAndHdmiUseSonyWhenTheKeyIsSaved() {
        let http = ScriptedHTTP()
        http.script = [
            HttpReply(status: 200, body: Data(#"{"result":[]}"#.utf8)),
            HttpReply(status: 200, body: Data(#"{"result":[]}"#.utf8))
        ]
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        settings.sonyPort = 80
        let session = RemoteSession(
            settings: settings,
            runner: FakeRunner(),
            http: http,
            fileExists: { _ in false }
        )
        session.setPreSharedKey(secret)
        let volume = session.setVolume(25)
        XCTAssertEqual(volume.title, "Volume 25")
        XCTAssertTrue(http.calls[0].body.contains("setAudioVolume"))
        XCTAssertTrue(http.calls[0].body.contains("25"))
        let hdmi = session.selectHdmi(2)
        XCTAssertEqual(hdmi.title, "HDMI 2")
        XCTAssertTrue(http.calls[1].body.contains("setPlayContent"))
        XCTAssertTrue(http.calls[1].body.contains("extInput:hdmi?port=2"))
        XCTAssertFalse(http.calls.contains { $0.body.contains(secret) || $0.url.contains(secret) })
    }

    func testExactVolumeWithoutAKeyExplainsTheGap() {
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        let http = ScriptedHTTP()
        let session = RemoteSession(settings: settings, runner: FakeRunner(), http: http, fileExists: { _ in false })
        let report = session.setVolume(10)
        XCTAssertTrue(report.isError)
        XCTAssertTrue(report.detail.contains("pre-shared key"))
        XCTAssertTrue(http.calls.isEmpty)
    }

    func testPictureRefreshMergesSonyPowerWithAdbNowPlaying() {
        let http = ScriptedHTTP()
        http.script = [
            HttpReply(status: 200, body: Data(#"{"result":[{"status":"active"}]}"#.utf8)),
            HttpReply(status: 200, body: Data(#"{"result":[[{"target":"speaker","volume":18,"mute":false,"maxVolume":100}]]}"#.utf8)),
            HttpReply(status: 200, body: Data(#"{"result":[[{"uri":"extInput:hdmi?port=1","title":"HDMI 1","label":"","connection":true}]]}"#.utf8)),
            HttpReply(status: 200, body: Data(#"{"result":[{"title":"HDMI 1"}]}"#.utf8))
        ]
        let runner = FakeRunner()
        runner.script = [
            .success(CommandResult(status: 0, stdout: "connected to 127.0.0.1:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n127.0.0.1:5555\tdevice\n", stderr: "")),
            .success(CommandResult(status: 0, stdout: "mCurrentFocus=Window{aa u0 com.netflix.ninja/com.netflix.ninja.MainActivity}", stderr: "")),
            .success(CommandResult(status: 0, stdout: "state=PlaybackState {state=3, position=0}\nandroid.media.metadata.TITLE=The Beef\nandroid.media.metadata.ARTIST=The Bear\n", stderr: ""))
        ]
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        settings.adbPath = "/usr/local/bin/adb"
        let session = RemoteSession(
            settings: settings,
            runner: runner,
            http: http,
            fileExists: { $0 == "/usr/local/bin/adb" },
            pathEnvironment: ""
        )
        session.setPreSharedKey(secret)
        _ = session.refresh()
        let picture = session.refreshPicture()
        XCTAssertEqual(picture.power, .on)
        XCTAssertEqual(picture.volume, 18)
        XCTAssertEqual(picture.inputTitle, "HDMI 1")
        XCTAssertEqual(picture.foregroundPackage, "com.netflix.ninja")
        XCTAssertEqual(picture.nowPlaying, "The Beef — The Bear")
        XCTAssertEqual(picture.statusLine(appName: "Netflix"), "On · Netflix")
        XCTAssertFalse(picture.detailLine.contains(secret))
    }

    func testOldSettingsFileStillLoadsAndDoesNotGainAKeyField() throws {
        let raw = #"{"host":"127.0.0.1","port":5555,"adbPath":"","wolEnabled":false,"macAddress":"","broadcastAddress":"255.255.255.255","apps":[],"keyboardMode":false}"#
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(raw.utf8))
        XCTAssertEqual(decoded.sonyPort, 80)
        XCTAssertEqual(decoded.host, "127.0.0.1")
        let saved = try JSONEncoder().encode(decoded)
        let text = String(data: saved, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("psk"))
        XCTAssertFalse(text.contains(secret))
        XCTAssertEqual(Settings.factoryDefaults().host, "")
        XCTAssertEqual(Settings.factoryDefaults().port, 5555)
    }

    func testPretendTelevisionStaysOnLocalhost() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = root.appendingPathComponent("scripts/pretend-tv.py")
        let refused = Process()
        refused.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        refused.arguments = [script.path, "9", "192.0.2.57", "/tmp/pohstep-should-not-write"]
        let err = Pipe()
        refused.standardError = err
        try refused.run()
        refused.waitUntilExit()
        XCTAssertEqual(refused.terminationStatus, 3)

        let secret = "pretend-only-psk"
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("pohstep-pretend-\(UUID().uuidString).log")
        let adbLog = FileManager.default.temporaryDirectory.appendingPathComponent("pohstep-adb-\(UUID().uuidString).log")
        let adbURL = FileManager.default.temporaryDirectory.appendingPathComponent("pohstep-adb-\(UUID().uuidString).sh")
        let adbScript = """
        #!/bin/sh
        echo "$@" >> "\(adbLog.path)"
        echo "$1 $2 $3 $4 $5 $6" | grep -q "192.0.2.57" && exit 2
        case "$*" in
          *connect*) echo "connected to 127.0.0.1:5555" ;;
          *devices*) printf 'List of devices attached\\n127.0.0.1:5555\\tdevice\\n' ;;
          *dumpsys*window*) echo 'mCurrentFocus=Window{aa u0 com.netflix.ninja/com.netflix.ninja.MainActivity}' ;;
          *dumpsys*media_session*) printf '%s\\n' 'state=PlaybackState {state=3, position=0}' 'android.media.metadata.TITLE=The Beef' 'android.media.metadata.ARTIST=The Bear' ;;
          *) exit 0 ;;
        esac
        """
        try adbScript.write(to: adbURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adbURL.path)

        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [script.path, "0", secret, logURL.path]
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

        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        settings.port = 5555
        settings.sonyPort = port
        settings.adbPath = adbURL.path
        let session = RemoteSession(settings: settings, runner: ShellRunner(), http: URLSessionHttp())
        session.setPreSharedKey(secret)
        let status = session.refresh()
        guard case .connected = status else {
            return XCTFail("expected a pretend adb connection, got \(status)")
        }
        let picture = session.refreshPicture()
        XCTAssertEqual(picture.power, .on)
        XCTAssertEqual(picture.volume, 18)
        XCTAssertEqual(picture.foregroundPackage, "com.netflix.ninja")
        XCTAssertEqual(picture.nowPlaying, "The Beef — The Bear")
        let hdmi = session.selectHdmi(3)
        XCTAssertFalse(hdmi.isError)
        let up = session.press(.dpadUp)
        XCTAssertEqual(up.detail, "Sent over Sony IP")

        session.setPreSharedKey("wrong-key")
        let fallback = session.press(.dpadUp)
        XCTAssertFalse(fallback.isError)
        XCTAssertFalse(fallback.detail.contains(secret))
        XCTAssertFalse(fallback.detail.contains("wrong-key"))

        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let adb = (try? String(contentsOf: adbLog, encoding: .utf8)) ?? ""
        XCTAssertTrue(log.contains("setPlayContent"))
        XCTAssertTrue(log.contains("AAAAAQAAAAEAAAB0Aw=="))
        XCTAssertTrue(log.contains("\"psk\": \"mismatch\"") || log.contains("\"psk\": \"match\""))
        XCTAssertFalse(log.contains(secret))
        XCTAssertFalse(log.contains("192.0.2.57"))
        XCTAssertFalse(adb.contains("192.0.2.57"))
        XCTAssertTrue(adb.contains("KEYCODE_DPAD_UP"))
    }
}
