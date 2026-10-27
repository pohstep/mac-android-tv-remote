import XCTest
@testable import TvRemoteCore

final class AppNameTests: XCTestCase {
    func testKnownPackagesUseTheTableEvenWhenTheLabelIsALetter() {
        XCTAssertEqual(AppNames.displayName(package: "com.netflix.ninja", label: nil), "Netflix")
        XCTAssertEqual(AppNames.displayName(package: "com.netflix.ninja", label: "A"), "Netflix")
        XCTAssertEqual(AppNames.displayName(package: "com.google.android.youtube.tv", label: "tv"), "YouTube")
        XCTAssertEqual(AppNames.displayName(package: "com.google.android.youtube.tvmusic", label: nil), "YouTube Music")
        XCTAssertEqual(AppNames.displayName(package: "com.google.android.youtube.tvkids", label: nil), "YouTube Kids")
        XCTAssertEqual(AppNames.displayName(package: "com.amazon.amazonvideo.livingroom", label: nil), "Prime Video")
        XCTAssertEqual(AppNames.displayName(package: "com.disney.disneyplus", label: nil), "Disney+")
        XCTAssertEqual(AppNames.displayName(package: "com.apple.atve.androidtv.appletv", label: nil), "Apple TV")
        XCTAssertEqual(AppNames.displayName(package: "com.apple.android.music", label: nil), "Apple Music")
        XCTAssertEqual(AppNames.displayName(package: "com.spotify.tv.android", label: "android"), "Spotify")
        XCTAssertEqual(AppNames.displayName(package: "com.plexapp.android", label: nil), "Plex")
        XCTAssertEqual(AppNames.displayName(package: "org.xbmc.kodi", label: nil), "Kodi")
        XCTAssertEqual(AppNames.displayName(package: "org.videolan.vlc", label: nil), "VLC")
        XCTAssertEqual(AppNames.displayName(package: "tv.twitch.android.app", label: nil), "Twitch")
        XCTAssertEqual(AppNames.displayName(package: "com.hbo.hbonow", label: nil), "HBO Max")
        XCTAssertEqual(AppNames.displayName(package: "com.wbd.stream", label: nil), "Max")
        XCTAssertEqual(AppNames.displayName(package: "com.hulu.livingroomplus", label: nil), "Hulu")
        XCTAssertEqual(AppNames.displayName(package: "com.tubitv", label: nil), "Tubi")
        XCTAssertEqual(AppNames.displayName(package: "tv.pluto.android", label: nil), "Pluto TV")
        XCTAssertEqual(AppNames.displayName(package: "com.crunchyroll.crunchyroid", label: nil), "Crunchyroll")
        XCTAssertEqual(AppNames.displayName(package: "com.android.chrome", label: nil), "Chrome")
        XCTAssertEqual(AppNames.displayName(package: "com.android.vending", label: nil), "Google Play Store")
        XCTAssertEqual(AppNames.displayName(package: "com.google.android.videos", label: nil), "Google Play Movies")
        XCTAssertEqual(AppNames.displayName(package: "com.android.tv.settings", label: nil), "Settings")
        XCTAssertEqual(AppNames.displayName(package: "com.android.documentsui", label: nil), "Files")
        XCTAssertEqual(AppNames.displayName(package: "com.google.android.apps.mediashell", label: nil), "Cast")
        XCTAssertEqual(AppNames.displayName(package: "com.aspiro.tidal", label: nil), "Tidal")
        XCTAssertEqual(AppNames.displayName(package: "deezer.android.tv", label: nil), "Deezer")
        XCTAssertEqual(AppNames.displayName(package: "com.bilibili.bilithings", label: nil), "bilibili")
        XCTAssertEqual(AppNames.displayName(package: "com.qiyi.video", label: nil), "iQIYI")
        XCTAssertEqual(AppNames.displayName(package: "com.tencent.qqlive", label: nil), "Tencent Video")
        XCTAssertEqual(AppNames.displayName(package: "com.youku.tv", label: nil), "Youku")
        XCTAssertEqual(AppNames.displayName(package: "com.hunantv.imgo.activity", label: nil), "Mango TV")
        XCTAssertEqual(AppNames.displayName(package: "org.smarttube.stable", label: "stable"), "SmartTube")
        XCTAssertEqual(AppNames.displayName(package: "com.phlox.tvwebbrowser", label: nil), "TV Bro")
        for (package, name) in AppNames.names {
            XCTAssertGreaterThan(name.count, 1, package)
            XCTAssertEqual(AppNames.displayName(package: package, label: "A"), name)
        }
    }

    func testDerivationNeverYieldsASingleCharacter() {
        XCTAssertEqual(AppNames.displayName(package: "com.foo.musicplayer", label: nil), "Music Player")
        XCTAssertEqual(AppNames.displayName(package: "com.foo.musicplayer", label: "musicplayer"), "Music Player")
        XCTAssertEqual(AppNames.displayName(package: "com.foo.music_player", label: nil), "Music Player")
        XCTAssertEqual(AppNames.displayName(package: "com.example.player", label: "Evening Paper"), "Evening Paper")
        let awkward = ["com.foo.musicplayer", "com.a.b", "com.q.x", "org.example.a", "com.foo.x_y", "com.acme.tv.android"]
        for package in awkward {
            let name = AppNames.displayName(package: package, label: "A")
            XCTAssertGreaterThan(name.count, 1, package)
            let face = AppNames.faceText(package: package, label: nil)
            let visible = face.filter { !$0.isWhitespace && $0 != "\n" }
            XCTAssertGreaterThan(visible.count, 1, package)
        }
        let netflixFace = AppNames.faceText(package: "com.netflix.ninja", label: nil)
        XCTAssertFalse(netflixFace == "N")
        XCTAssertTrue(netflixFace.contains("Net"))
    }

    func testSwatchesAreStableAndUseSeveralHuePairs() {
        let samples = [
            "com.netflix.ninja",
            "com.google.android.youtube.tv",
            "com.google.android.youtube.tvmusic",
            "com.google.android.youtube.tvkids",
            "com.amazon.amazonvideo.livingroom",
            "com.disney.disneyplus",
            "com.apple.atve.androidtv.appletv",
            "com.apple.android.music",
            "com.spotify.tv.android",
            "com.plexapp.android",
            "org.xbmc.kodi",
            "org.videolan.vlc",
            "tv.twitch.android.app",
            "com.hbo.hbonow",
            "com.wbd.stream",
            "com.hulu.livingroomplus",
            "com.tubitv",
            "tv.pluto.android",
            "com.crunchyroll.crunchyroid",
            "com.android.chrome"
        ]
        XCTAssertEqual(samples.count, 20)
        var pairs = Set<String>()
        for package in samples {
            let pair = AppSwatch.pair(for: package)
            XCTAssertNotEqual(pair.start, pair.end, package)
            XCTAssertEqual(pair, AppSwatch.pair(for: package))
            XCTAssertTrue((0..<AppSwatch.stopCount).contains(pair.start))
            XCTAssertTrue((0..<AppSwatch.stopCount).contains(pair.end))
            pairs.insert("\(pair.start)-\(pair.end)")
        }
        XCTAssertGreaterThanOrEqual(pairs.count, 6)
    }

    func testZipReaderPicksTheSharpestRasterAndSkipsXml() {
        let small = Data([1, 2, 3, 4])
        let sharp = Data([9, 8, 7, 6, 5, 4, 3, 2])
        var archive = Data()
        archive.append(zipEntry(name: "res/xml/ic_launcher.xml", data: Data([60, 120, 109, 108]), method: 0))
        archive.append(zipEntry(name: "res/mipmap-mdpi/ic_launcher.png", data: small, method: 0))
        archive.append(zipEntry(name: "res/drawable/readme.txt", data: Data([1]), method: 0))
        archive.append(zipEntry(name: "res/mipmap-xxhdpi/ic_launcher.png", data: sharp, method: 8))
        archive.append(zipEntry(name: "res/drawable/icon.png", data: Data(repeating: 3, count: 30), method: 0))
        XCTAssertEqual(ZipArchive.icon(in: archive), sharp)
        let xmlOnly = zipEntry(name: "res/mipmap-xxhdpi/ic_launcher.xml", data: Data([1, 2, 3, 4, 5, 6, 7, 8]), method: 0)
        XCTAssertNil(ZipArchive.icon(in: xmlOnly))
        let huffman = Data([227, 228, 96, 103, 99, 101, 97, 102, 2, 0])
        let packed = zipEntryCompressed(
            name: "res/mipmap-xxxhdpi/ic_launcher.png",
            compressed: huffman,
            uncompressed: sharp
        )
        XCTAssertEqual(ZipArchive.icon(in: packed), sharp)
    }

    func testCacheKeyIncludesPackageAndVersion() throws {
        XCTAssertEqual(AppIconCache.fileName(package: "com.netflix.ninja", versionCode: "42"), "com.netflix.ninja@42.png")
        XCTAssertNotEqual(
            AppIconCache.fileName(package: "com.netflix.ninja", versionCode: "42"),
            AppIconCache.fileName(package: "com.netflix.ninja", versionCode: "43")
        )
        XCTAssertEqual(AppIconFetch.versionCode(in: "versionCode=8012 minSdk=21"), "8012")
        XCTAssertEqual(AppIconFetch.baseApkPath("package:/data/app/com.foo/split.apk\npackage:/data/app/com.foo/base.apk\n"), "/data/app/com.foo/base.apk")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bytes = Data([9, 8, 7, 6])
        let stored = try AppIconCache.store(directory: directory, package: "com.foo.musicplayer", versionCode: "7", bytes: bytes)
        XCTAssertEqual(stored.lastPathComponent, "com.foo.musicplayer@7.png")
        XCTAssertEqual(AppIconCache.existing(directory: directory, package: "com.foo.musicplayer", versionCode: "7"), stored)
        XCTAssertNil(AppIconCache.existing(directory: directory, package: "com.foo.musicplayer", versionCode: "8"))
        XCTAssertEqual(try Data(contentsOf: stored), bytes)
    }

    func testIconFetchPullsBaseApkThenDeletesIt() throws {
        let sharp = Data([9, 8, 7, 6, 5])
        let archive = zipEntry(name: "res/mipmap-xxhdpi/ic_launcher.png", data: sharp, method: 8)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let runner = FakeRunner()
        runner.handler = { arguments in
            if arguments.contains("dump") {
                return .success(CommandResult(status: 0, stdout: "versionCode=15\n", stderr: ""))
            }
            if arguments.contains("path") {
                return .success(CommandResult(status: 0, stdout: "package:/data/app/com.foo.musicplayer/base.apk\n", stderr: ""))
            }
            if arguments.contains("stat") {
                return .success(CommandResult(status: 0, stdout: "\(archive.count)\n", stderr: ""))
            }
            if arguments.contains("pull") {
                let local = arguments.last ?? ""
                try? archive.write(to: URL(fileURLWithPath: local))
                return .success(CommandResult(status: 0, stdout: "", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let client = AdbClient(
            runner: runner,
            adbPath: "/usr/bin/adb",
            temporaryDirectory: temp.path,
            serverSocket: "tcp:localhost:5037"
        )
        let url = AppIconFetch.fetch(package: "com.foo.musicplayer", serial: "127.0.0.1:5555", client: client, cacheDirectory: cache)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(url)), sharp)
        let leftovers = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
        XCTAssertTrue(leftovers.filter { $0.pathExtension == "apk" }.isEmpty)
        XCTAssertTrue(runner.calls.allSatisfy { $0.timeout <= AppIconFetch.timeout })
        XCTAssertTrue(runner.calls.contains { $0.arguments.contains("pull") })
    }

    func testIconFetchSkipsAnOversizedApk() {
        let runner = FakeRunner()
        runner.handler = { arguments in
            if arguments.contains("dump") {
                return .success(CommandResult(status: 0, stdout: "versionCode=1\n", stderr: ""))
            }
            if arguments.contains("path") {
                return .success(CommandResult(status: 0, stdout: "package:/data/app/com.foo.big/base.apk\n", stderr: ""))
            }
            if arguments.contains("stat") {
                return .success(CommandResult(status: 0, stdout: "\(AppIconFetch.maxApkBytes + 1)\n", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let client = AdbClient(runner: runner, adbPath: "/usr/bin/adb", serverSocket: "tcp:localhost:5037")
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        XCTAssertNil(AppIconFetch.fetch(package: "com.foo.big", serial: "127.0.0.1:5555", client: client, cacheDirectory: cache))
        XCTAssertFalse(runner.calls.contains { $0.arguments.contains("pull") })
    }

    func testScheduleKeepsOneInFlightAndRetriesOnce() {
        let schedule = AppIconSchedule()
        schedule.enqueue(["com.netflix.ninja", "org.videolan.vlc", "not a package"])
        XCTAssertEqual(schedule.next(), "com.netflix.ninja")
        XCTAssertNil(schedule.next())
        schedule.finish("com.netflix.ninja", success: false)
        XCTAssertEqual(schedule.next(), "org.videolan.vlc")
        schedule.finish("org.videolan.vlc", success: true)
        XCTAssertEqual(schedule.next(), "com.netflix.ninja")
        schedule.finish("com.netflix.ninja", success: false)
        XCTAssertNil(schedule.next())
        schedule.enqueue(["com.netflix.ninja", "org.videolan.vlc"])
        XCTAssertNil(schedule.next())
    }
}

private func zipEntry(name: String, data: Data, method: UInt16) -> Data {
    let nameBytes = Array(name.utf8)
    let payload: Data
    if method == 0 {
        payload = data
    } else {
        var raw = Data([0x01])
        let length = UInt16(data.count)
        raw.append(UInt8(length & 0xFF))
        raw.append(UInt8((length >> 8) & 0xFF))
        let complement = length ^ 0xFFFF
        raw.append(UInt8(complement & 0xFF))
        raw.append(UInt8((complement >> 8) & 0xFF))
        raw.append(data)
        payload = raw
    }
    var out = Data([0x50, 0x4B, 0x03, 0x04])
    out.append(le(UInt16(20)))
    out.append(le(UInt16(0)))
    out.append(le(method))
    out.append(le(UInt16(0)))
    out.append(le(UInt16(0)))
    out.append(le(UInt32(0)))
    out.append(le(UInt32(payload.count)))
    out.append(le(UInt32(data.count)))
    out.append(le(UInt16(nameBytes.count)))
    out.append(le(UInt16(0)))
    out.append(contentsOf: nameBytes)
    out.append(payload)
    return out
}

private func zipEntryCompressed(name: String, compressed: Data, uncompressed: Data) -> Data {
    let nameBytes = Array(name.utf8)
    var out = Data([0x50, 0x4B, 0x03, 0x04])
    out.append(le(UInt16(20)))
    out.append(le(UInt16(0)))
    out.append(le(UInt16(8)))
    out.append(le(UInt16(0)))
    out.append(le(UInt16(0)))
    out.append(le(UInt32(0)))
    out.append(le(UInt32(compressed.count)))
    out.append(le(UInt32(uncompressed.count)))
    out.append(le(UInt16(nameBytes.count)))
    out.append(le(UInt16(0)))
    out.append(contentsOf: nameBytes)
    out.append(compressed)
    return out
}

private func le(_ value: UInt16) -> Data {
    Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
}

private func le(_ value: UInt32) -> Data {
    Data([
        UInt8(value & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 24) & 0xFF)
    ])
}
