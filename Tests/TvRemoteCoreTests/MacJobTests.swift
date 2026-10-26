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
            if arguments == ["devices"] {
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
        XCTAssertEqual(install?.arguments, ["-s", "192.0.2.20:5555", "install", "-r", apk.path])
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
        XCTAssertEqual(rejected.sentence, "Drop an app file ending in .apk.")
        XCTAssertEqual(fake.calls.count, before)
    }

    func testSendLinkAcceptsOnlyWebURLs() {
        XCTAssertEqual(LinkSend.httpURL(from: " https://example.com/a?b=1&c=2 "), "https://example.com/a?b=1&c=2")
        XCTAssertEqual(LinkSend.httpURL(from: "HTTP://example.com/x"), "http://example.com/x")
        XCTAssertNil(LinkSend.httpURL(from: "file:///tmp/a.mp4"))
        XCTAssertNil(LinkSend.httpURL(from: "javascript:alert(1)"))
        XCTAssertNil(LinkSend.httpURL(from: "just words"))
        XCTAssertNil(LinkSend.httpURL(from: "http://"))

        let fake = FakeRunner()
        let session = connectedSession(fake, temporaryDirectory: NSTemporaryDirectory())
        let refused = session.sendLink("file:///tmp/a.mp4")
        XCTAssertEqual(refused.sentence, "Only web links can be sent. Use http or https.")
        XCTAssertTrue(fake.calls.isEmpty)

        fake.handler = { arguments in
            if arguments == ["devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "Starting: Intent", stderr: ""))
        }
        let sent = session.sendLink("https://example.com/a?b=1&c=2")
        XCTAssertEqual(sent.sentence, "Opened on the TV.")
        XCTAssertFalse(sent.isError)
        XCTAssertEqual(
            fake.calls.last?.arguments,
            ["-s", "192.0.2.20:5555", "shell", "am start -a android.intent.action.VIEW -d 'https://example.com/a?b=1&c=2'"]
        )

        fake.handler = { arguments in
            if arguments == ["devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            return .success(CommandResult(status: 1, stdout: "", stderr: "Error: Activity not started"))
        }
        let failed = session.sendLink("https://example.com")
        XCTAssertEqual(failed.sentence, "The TV didn't open that link. It needs a browser.")
        XCTAssertTrue(failed.raw.contains("Activity not started"))
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
            if arguments == ["devices"] {
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

    func testSendFilePushesToDownloadsAndAsksForAPlayer() throws {
        XCTAssertEqual(FileSend.downloadPath(for: "/Users/me/My Video.mp4"), "/sdcard/Download/My Video.mp4")
        XCTAssertEqual(FileSend.fileURL(remotePath: "/sdcard/Download/My Video.mp4"), "file:///sdcard/Download/My%20Video.mp4")
        XCTAssertEqual(FileSend.mimeType(for: "clip.mp4"), "video/mp4")
        XCTAssertEqual(FileSend.mimeType(for: "song.mp3"), "audio/mpeg")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zapbar file \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let video = folder.appendingPathComponent("My Video.mp4")
        try Data([0]).write(to: video)

        let fake = FakeRunner()
        let session = connectedSession(fake, temporaryDirectory: NSTemporaryDirectory())
        fake.handler = { arguments in
            if arguments == ["devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("push") {
                return .success(CommandResult(status: 0, stdout: "1 file pushed", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "Starting: Intent", stderr: ""))
        }
        let sent = session.sendFile(at: video.path)
        XCTAssertEqual(sent.sentence, "Sent. The TV needs a player to open it.")
        XCTAssertFalse(sent.isError)
        XCTAssertEqual(
            fake.calls.first { $0.arguments.contains("push") }?.arguments,
            ["-s", "192.0.2.20:5555", "push", video.path, "/sdcard/Download/My Video.mp4"]
        )
        XCTAssertEqual(
            fake.calls.last?.arguments,
            ["-s", "192.0.2.20:5555", "shell", "am start -a android.intent.action.VIEW -d 'file:///sdcard/Download/My%20Video.mp4' -t 'video/mp4'"]
        )

        fake.calls = []
        fake.handler = { arguments in
            if arguments == ["devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("push") {
                return .success(CommandResult(status: 1, stdout: "", stderr: "adb: error: failed to copy: No space left on device"))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let full = session.sendFile(at: video.path)
        XCTAssertEqual(full.sentence, "The TV doesn't have enough free space.")
        XCTAssertTrue(full.raw.contains("No space left on device"))
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("shell") })

        fake.calls = []
        fake.handler = { arguments in
            if arguments == ["devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("push") {
                return .success(CommandResult(status: 0, stdout: "1 file pushed", stderr: ""))
            }
            return .success(CommandResult(status: 1, stdout: "Error: Activity not started", stderr: ""))
        }
        let unopened = session.sendFile(at: video.path)
        XCTAssertEqual(unopened.sentence, "The file is in Downloads. The TV needs a player to open it.")
        XCTAssertTrue(unopened.raw.contains("Activity not started"))
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
        XCTAssertEqual(session.sendLink("https://example.com").sentence, "This needs a network debugging connection.")
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
