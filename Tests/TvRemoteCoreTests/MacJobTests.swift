import XCTest
@testable import TvRemoteCore

final class MacJobTests: XCTestCase {
    private let redPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")!
    private let blackPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAC0lEQVR4nGNgQAYAAA4AAamRc7EAAAAASUVORK5CYII=")!
    private let rgbaBlackPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==")!

    func testInstallKeepsSpacesAndTranslatesTheAdbError() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zapbar install \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let apk = folder.appendingPathComponent("My Show.apk")
        try Data([0x50, 0x4b]).write(to: apk)

        let fake = FakeRunner()
        let session = connectedSession(fake, temporaryDirectory: "/var/folders/zapbar")
        fake.handler = { arguments in
            if arguments == ["-P", "5037", "devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("install") {
                let raw = "Failure [INSTALL_FAILED_VERSION_DOWNGRADE]\n"
                return .success(CommandResult(status: 1, stdout: raw, stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let report = session.installApk(at: apk.path)
        XCTAssertEqual(report.sentence, "The TV already has a newer version of this app.")
        XCTAssertTrue(report.raw.contains("INSTALL_FAILED_VERSION_DOWNGRADE"))
        XCTAssertTrue(report.isError)
        let install = fake.calls.last
        XCTAssertEqual(install?.arguments, ["-P", "5037", "-s", "192.0.2.20:5555", "install", "-r", apk.path])
        XCTAssertEqual(install?.arguments.last, apk.path)
        XCTAssertTrue(apk.path.contains(" "))
        XCTAssertEqual(install?.environment["TMPDIR"], "/var/folders/zapbar")
        XCTAssertEqual(install?.environment["ADB_SERVER_SOCKET"], "tcp:localhost:5037")

        XCTAssertEqual(
            InstallExplain.sentence(status: 1, output: "Failure [INSTALL_FAILED_USER_RESTRICTED]"),
            "The TV blocked the install. Check the TV's install settings."
        )
        XCTAssertEqual(InstallExplain.sentence(status: 0, output: "Success"), "Installed.")

        let before = fake.calls.count
        let rejected = session.installApk(at: folder.appendingPathComponent("notes.txt").path)
        XCTAssertEqual(rejected.sentence, ApkPick.onlyApk)
        XCTAssertEqual(
            InstallLog.text(sentence: rejected.sentence, raw: ""),
            ApkPick.onlyApk
        )
        XCTAssertEqual(
            InstallLog.text(sentence: "The install didn't finish.", raw: "adb: device offline"),
            "The install didn't finish.\nCheck the TV, then choose the .apk again.\nadb: device offline"
        )
        XCTAssertEqual(InstallExplain.recovery(for: "Installed."), nil)
        XCTAssertEqual(fake.calls.count, before)
    }

    func testInstallStatusMappingAndLog() {
        let rows: [(String, String, String)] = [
            ("INSTALL_FAILED_VERSION_DOWNGRADE", "The TV already has a newer version of this app.", "Choose a newer .apk."),
            ("INSTALL_FAILED_UPDATE_INCOMPATIBLE", "This file doesn't match the app already on the TV.", "Remove that app on the TV, then choose the .apk again."),
            ("INSTALL_FAILED_INSUFFICIENT_STORAGE", "The TV doesn't have enough free space.", "Free some space on the TV, then choose the .apk again."),
            ("INSTALL_FAILED_OLDER_SDK", "This app needs a newer system than the TV has.", "Choose an app built for this TV."),
            ("INSTALL_FAILED_NO_MATCHING_ABIS", "This app isn't built for this TV.", "Choose an app built for this TV."),
            ("INSTALL_FAILED_INVALID_APK", "That file isn't an installable app.", "Choose a different .apk."),
            ("INSTALL_FAILED_ABORTED", "The TV cancelled the install.", "Check the TV, then choose the .apk again."),
            ("INSTALL_FAILED_MISSING_SHARED_LIBRARY", "The TV is missing a library this app needs.", "Choose a different .apk.")
        ]
        for row in rows {
            let output = "Failure [\(row.0)]"
            let sentence = InstallExplain.sentence(status: 1, output: output)
            XCTAssertEqual(sentence, row.1, row.0)
            let log = InstallLog.text(sentence: sentence, raw: output)
            XCTAssertEqual(log, "\(row.1)\n\(row.2)\n\(output)")
        }
        XCTAssertEqual(InstallExplain.sentence(status: 1, output: "boom"), "The install didn't finish.")
        XCTAssertEqual(InstallExplain.recovery(for: ApkPick.onlyApk), nil)
        XCTAssertFalse(ApkPick.isApk("/tmp/clip.mp4"))
        XCTAssertTrue(ApkPick.isApk("/tmp/Show.APK"))
    }

    func testScreenshotBlankBrokenAndSaveThenPull() throws {
        XCTAssertEqual(ScreenshotBytes.kind(redPNG), .picture)
        XCTAssertEqual(ScreenshotBytes.kind(blackPNG), .blank)
        XCTAssertEqual(ScreenshotBytes.kind(rgbaBlackPNG), .blank)
        XCTAssertEqual(ScreenshotBytes.kind(Data("not a png".utf8)), .broken)
        XCTAssertEqual(ScreenshotBytes.kind(Data()), .broken)

        var fallbacks = 0
        let black = ScreenshotCapture.resolve(execOut: blackPNG) {
            fallbacks += 1
            return (redPNG, "unused")
        }
        XCTAssertEqual(black.png, blackPNG)
        XCTAssertEqual(black.sentence, "The TV may block screenshots of protected video.")
        XCTAssertFalse(black.isError)
        XCTAssertEqual(fallbacks, 0)

        let pulled = ScreenshotCapture.resolve(execOut: Data("broken".utf8)) {
            fallbacks += 1
            return (redPNG, "pulled")
        }
        XCTAssertEqual(pulled.png, redPNG)
        XCTAssertEqual(pulled.sentence, "Screenshot ready.")
        XCTAssertEqual(fallbacks, 1)

        let stillBlank = ScreenshotCapture.resolve(execOut: Data()) {
            return (blackPNG, "adb: broken pipe")
        }
        XCTAssertEqual(stillBlank.png, blackPNG)
        XCTAssertEqual(stillBlank.sentence, ScreenshotBytes.blankSentence)
        XCTAssertFalse(stillBlank.isError)
        XCTAssertEqual(stillBlank.raw, "adb: broken pipe")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zapbar-shot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fake = FakeRunner()
        let session = connectedSession(fake, temporaryDirectory: folder.path)
        fake.handler = { arguments in
            if arguments == ["-P", "5037", "devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("exec-out") {
                return .success(CommandResult(status: 0, stdout: "", stderr: "", stdoutData: Data("nope".utf8)))
            }
            if arguments.contains(where: { $0.contains("screencap -p") }) {
                return .success(CommandResult(status: 0, stdout: "", stderr: ""))
            }
            if arguments.contains("pull") {
                let dest = arguments.last ?? ""
                try? self.redPNG.write(to: URL(fileURLWithPath: dest))
                return .success(CommandResult(status: 0, stdout: "", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let shot = session.captureScreenshot()
        XCTAssertEqual(shot.png, redPNG)
        XCTAssertFalse(shot.isError)
        XCTAssertTrue(fake.calls.contains { $0.arguments.contains("exec-out") && $0.arguments.contains("screencap") })
        XCTAssertTrue(fake.calls.contains { $0.arguments.contains("pull") && $0.arguments.contains("/sdcard/Download/zapbar-screen.png") })
        XCTAssertTrue(fake.calls.contains { $0.arguments.joined(separator: " ").contains("rm -f") })
        if let local = fake.calls.first(where: { $0.arguments.contains("pull") })?.arguments.last {
            XCTAssertFalse(FileManager.default.fileExists(atPath: local))
        }
        XCTAssertEqual(fake.calls.first { $0.arguments.contains("exec-out") }?.environment["TMPDIR"], folder.path)
    }

    func testInstallKeepsTheRawLogOnSuccess() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zapbar-ok-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let apk = folder.appendingPathComponent("Show.apk")
        try Data([0x50]).write(to: apk)
        let video = folder.appendingPathComponent("Clip.mp4")
        try Data([0]).write(to: video)
        let fake = FakeRunner()
        let session = connectedSession(fake, temporaryDirectory: NSTemporaryDirectory())
        fake.handler = { arguments in
            if arguments == ["-P", "5037", "devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("install") {
                return .success(CommandResult(status: 0, stdout: "Success\n", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let refused = session.installApk(at: video.path)
        XCTAssertEqual(refused.sentence, ApkPick.onlyApk)
        XCTAssertTrue(refused.isError)
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("install") })

        let installed = session.installApk(at: apk.path)
        XCTAssertEqual(installed.sentence, "Installed.")
        XCTAssertFalse(installed.isError)
        XCTAssertTrue(installed.raw.contains("Success"))
        XCTAssertEqual(InstallLog.text(sentence: installed.sentence, raw: installed.raw), "Installed.\nSuccess")
    }

    func testJobsDoNothingWithoutADebuggingConnection() throws {
        let apk = FileManager.default.temporaryDirectory.appendingPathComponent("zapbar-\(UUID().uuidString).apk")
        try Data([0]).write(to: apk)
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.40"
        settings.port = 6095
        settings.brand = .xiaomi
        let fake = FakeRunner()
        let session = RemoteSession(settings: settings, runner: fake, reader: AliveReader(), fileExists: { _ in true })
        _ = session.refresh()
        let report = session.installApk(at: apk.path)
        XCTAssertEqual(report.sentence, "This needs a network debugging connection.")
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("install") })
    }

    func testScreenshotOfASleepingTVSaysSoAndDoesNotCapture() {
        let fake = FakeRunner()
        let session = connectedSession(fake, temporaryDirectory: NSTemporaryDirectory())
        var wakefulness = "  mWakefulness=Asleep\n"
        fake.handler = { arguments in
            if arguments == ["-P", "5037", "devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("dumpsys") {
                return .success(CommandResult(status: 0, stdout: wakefulness, stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let asleep = session.captureScreenshot()
        XCTAssertNil(asleep.png)
        XCTAssertTrue(asleep.isError)
        XCTAssertEqual(asleep.sentence, "The TV is asleep. Turn it on first.")
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("exec-out") || $0.arguments.contains("pull") })

        fake.calls = []
        wakefulness = "  mWakefulness=Dozing\n"
        XCTAssertEqual(session.captureScreenshot().sentence, ScreenshotCapture.asleep)
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("exec-out") })

        // Awake goes on to capture as before.
        fake.calls = []
        wakefulness = "  mWakefulness=Awake\n"
        _ = session.captureScreenshot()
        XCTAssertTrue(fake.calls.contains { $0.arguments.contains("exec-out") })
    }

    private func connectedSession(_ fake: FakeRunner, temporaryDirectory: String) -> RemoteSession {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.port = 5555
        fake.script = [
            .success(CommandResult(status: 0, stdout: "connected to 192.0.2.20:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
        ]
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            homeDirectory: "/Users/tester",
            temporaryDirectory: temporaryDirectory
        )
        _ = session.refresh()
        fake.calls = []
        fake.script = []
        return session
    }
}

private struct AliveReader: HttpReading {
    func get(url: URL, timeout: TimeInterval) throws -> HttpReply {
        HttpReply(status: 200, body: Data(#"{"status":0,"data":{"devicename":"Den"}}"#.utf8))
    }
}
