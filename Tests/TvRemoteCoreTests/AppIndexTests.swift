import XCTest
@testable import TvRemoteCore

final class AppIndexTests: XCTestCase {
    func testLauncherExportPinsFavouritesAndKeepsOrder() {
        let json = """
        {
          "favourites": ["org.smarttube.stable", "com.netflix.ninja"],
          "apps": [
            {"name": "YouTube", "packageName": "com.google.android.youtube.tv"},
            {"name": "Netflix", "packageName": "com.netflix.ninja", "favourite": false},
            {"name": "SmartTube", "packageName": "org.smarttube.stable"},
            {"name": "VLC", "packageName": "org.videolan.vlc", "favorite": true}
          ]
        }
        """
        let apps = AppIndex.parseLauncher(json)
        XCTAssertEqual(apps?.map(\.name), ["SmartTube", "Netflix", "VLC", "YouTube"])
        XCTAssertEqual(apps?.map(\.favourite), [true, true, true, false])
    }

    func testFlaggedFavouritesStayInFileOrder() {
        let json = """
        [
          {"name": "YouTube", "package": "com.google.android.youtube.tv"},
          {"label": "Netflix", "packageName": "com.netflix.ninja", "favourite": true},
          {"title": "VLC", "package_name": "org.videolan.vlc", "pinned": true}
        ]
        """
        let apps = AppIndex.parseLauncher(json)
        XCTAssertEqual(apps?.map(\.packageName), [
            "com.netflix.ninja",
            "org.videolan.vlc",
            "com.google.android.youtube.tv"
        ])
    }

    func testLeanbackQueryUsesLabelsAndPackageLines() {
        let verbose = """
        ActivityInfo:
          packageName=com.netflix.ninja
          nonLocalizedLabel=Netflix
        ActivityInfo:
          packageName=org.videolan.vlc
          nonLocalizedLabel=null
          application-label: VLC
        """
        let apps = AppIndex.parseLeanback(verbose)
        XCTAssertEqual(apps.map(\.name), ["Netflix", "VLC"])
        XCTAssertEqual(apps.map(\.favourite), [false, false])

        let brief = """
        1 activities found:
        com.spotify.tv.android/com.spotify.tv.android.SpotifyTVActivity
        """
        XCTAssertEqual(AppIndex.parseLeanback(brief).map(\.packageName), ["com.spotify.tv.android"])
        XCTAssertEqual(AppIndex.label(in: "application-label: Spotify"), "Spotify")
    }

    func testMissingLauncherFileFallsBackToLeanbackLabels() {
        let runner = FakeRunner()
        runner.script = [
            .success(CommandResult(status: 0, stdout: "connected to 127.0.0.1:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n127.0.0.1:5555\tdevice\n", stderr: "")),
            .success(CommandResult(status: 1, stdout: "", stderr: "No such file or directory")),
            .success(CommandResult(status: 0, stdout: "com.netflix.ninja/com.netflix.ninja.MainActivity\n", stderr: "")),
            .success(CommandResult(status: 0, stdout: "application-label: Netflix\n", stderr: ""))
        ]
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        settings.adbPath = "/usr/local/bin/adb"
        let session = RemoteSession(
            settings: settings,
            runner: runner,
            fileExists: { $0 == "/usr/local/bin/adb" },
            pathEnvironment: ""
        )
        _ = session.refresh()
        let apps = session.readApps()
        XCTAssertEqual(apps?.map(\.name), ["Netflix"])
        XCTAssertEqual(apps?.first?.packageName, "com.netflix.ninja")
        XCTAssertTrue(runner.calls.contains { $0.arguments == AdbCommands.leanbackActivities(serial: "127.0.0.1:5555") })
        XCTAssertTrue(runner.calls.contains { $0.arguments == AdbCommands.packageDump(serial: "127.0.0.1:5555", packageName: "com.netflix.ninja") })
        XCTAssertFalse(runner.calls.contains { $0.arguments.joined(separator: " ").contains("192.0.2.57") })
    }

    func testLauncherExportSkipsTheLeanbackQuery() {
        let json = #"{"apps":[{"name":"SmartTube","packageName":"org.smarttube.stable","favourite":true}]}"#
        let runner = FakeRunner()
        runner.script = [
            .success(CommandResult(status: 0, stdout: "connected to 127.0.0.1:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n127.0.0.1:5555\tdevice\n", stderr: "")),
            .success(CommandResult(status: 0, stdout: json, stderr: ""))
        ]
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        settings.adbPath = "/usr/local/bin/adb"
        let session = RemoteSession(
            settings: settings,
            runner: runner,
            fileExists: { $0 == "/usr/local/bin/adb" },
            pathEnvironment: ""
        )
        _ = session.refresh()
        let apps = session.readApps()
        XCTAssertEqual(apps?.map(\.name), ["SmartTube"])
        XCTAssertEqual(apps?.first?.favourite, true)
        XCTAssertTrue(runner.calls.contains { $0.arguments == AdbCommands.launcherIndex(serial: "127.0.0.1:5555") })
        XCTAssertFalse(runner.calls.contains { $0.arguments.contains("query-activities") })
    }

    func testReadAppsDoesNothingUntilAdbIsConnected() {
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        let runner = FakeRunner()
        let session = RemoteSession(settings: settings, runner: runner, fileExists: { _ in false })
        XCTAssertNil(session.readApps())
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testSavedCatalogRoundTripPinsFavourites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AppCatalogStore(url: directory.appendingPathComponent("apps.json"))
        let apps = [
            TvApp(id: "yt", name: "YouTube", packageName: "com.google.android.youtube.tv"),
            TvApp(id: "nf", name: "Netflix", packageName: "com.netflix.ninja", favourite: true)
        ]
        try store.save(apps)
        let loaded = store.load()
        XCTAssertEqual(loaded?.map(\.name), ["Netflix", "YouTube"])
        XCTAssertEqual(AppListCaption.offlineSaved, "TV offline, saved list")
        XCTAssertEqual(
            AppListCaption.text(loading: false, appsEmpty: false, savedCatalog: true, connected: false, connecting: false),
            "TV offline, saved list"
        )
        XCTAssertEqual(
            AppListCaption.text(loading: true, appsEmpty: true, savedCatalog: false, connected: false, connecting: true),
            AppListCaption.loadingTitle
        )
        XCTAssertEqual(
            AppListCaption.text(loading: false, appsEmpty: false, savedCatalog: true, connected: true, connecting: false),
            "Apps"
        )
    }
}
