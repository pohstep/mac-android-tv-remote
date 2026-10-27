import Foundation

/// Familiar names for packages the panel already knows, plus a readable name
/// when the TV did not send one. A tile never falls back to a single letter.
public enum AppNames {
    public static let names: [String: String] = [
        "com.netflix.ninja": "Netflix",
        "com.netflix.mediaclient": "Netflix",
        "com.google.android.youtube.tv": "YouTube",
        "com.google.android.youtube": "YouTube",
        "com.google.android.youtube.tvmusic": "YouTube Music",
        "com.google.android.apps.youtube.music": "YouTube Music",
        "com.google.android.youtube.tvkids": "YouTube Kids",
        "com.google.android.apps.youtube.kids": "YouTube Kids",
        "com.amazon.amazonvideo.livingroom": "Prime Video",
        "com.amazon.avod.thirdpartyclient": "Prime Video",
        "com.amazon.avod": "Prime Video",
        "com.disney.disneyplus": "Disney+",
        "com.apple.atve.androidtv.appletv": "Apple TV",
        "com.apple.android.music": "Apple Music",
        "com.spotify.tv.android": "Spotify",
        "com.spotify.music": "Spotify",
        "com.plexapp.android": "Plex",
        "org.xbmc.kodi": "Kodi",
        "org.videolan.vlc": "VLC",
        "tv.twitch.android.app": "Twitch",
        "com.hbo.hbonow": "HBO Max",
        "com.wbd.stream": "Max",
        "com.hulu.livingroomplus": "Hulu",
        "com.hulu.plus": "Hulu",
        "com.tubitv": "Tubi",
        "tv.pluto.android": "Pluto TV",
        "com.crunchyroll.crunchyroid": "Crunchyroll",
        "com.android.chrome": "Chrome",
        "com.android.vending": "Google Play Store",
        "com.google.android.videos": "Google Play Movies",
        "com.android.tv.settings": "Settings",
        "com.android.settings": "Settings",
        "com.android.documentsui": "Files",
        "com.google.android.apps.nbu.files": "Files",
        "com.google.android.apps.mediashell": "Cast",
        "com.aspiro.tidal": "Tidal",
        "deezer.android.tv": "Deezer",
        "deezer.android.app": "Deezer",
        "com.bilibili.bilithings": "bilibili",
        "tv.danmaku.bili": "bilibili",
        "com.qiyi.video": "iQIYI",
        "com.tencent.qqlive": "Tencent Video",
        "com.youku.phone": "Youku",
        "com.youku.tv": "Youku",
        "com.hunantv.imgo.activity": "Mango TV",
        "org.smarttube.stable": "SmartTube",
        "com.phlox.tvwebbrowser": "TV Bro"
    ]

    /// Known package, otherwise a real TV label, otherwise a name built from the package id.
    public static func displayName(package: String, label: String?) -> String {
        if let known = names[package] ?? names[package.lowercased()] {
            return known
        }
        if let label, let cleaned = TvApp.cleanName(label), isHumanLabel(cleaned, package: package) {
            return cleaned
        }
        return derive(package)
    }

    /// Same name, with a line break in a long single word so the square can use two lines.
    public static func faceText(package: String, label: String?) -> String {
        let name = displayName(package: package, label: label)
        if name.contains(where: \.isWhitespace) { return name }
        let characters = Array(name)
        guard characters.count > 6 else { return name }
        let splitAt = max(2, min(characters.count / 2, characters.count - 2))
        return String(characters[..<splitAt]) + "\n" + String(characters[splitAt...])
    }

    private static func isHumanLabel(_ label: String, package: String) -> Bool {
        let letters = label.filter { $0.isLetter || $0.isNumber }
        if letters.count < 2 { return false }
        let last = package.split(separator: ".").last.map(String.init) ?? ""
        let rawSegment = label.compare(last, options: .caseInsensitive) == .orderedSame
            && !label.contains(where: \.isWhitespace)
            && label == label.lowercased()
        return !rawSegment
    }

    private static let generic: Set<String> = [
        "com", "org", "net", "io", "tv", "android", "app", "apps", "free", "mobile",
        "google", "amazon", "leanback", "activity", "activities", "stable", "beta",
        "debug", "release", "androidtv"
    ]

    private static let lexicon: [String] = [
        "streaming", "launcher", "settings", "gallery", "browser", "photos", "movies",
        "sports", "player", "stream", "music", "video", "audio", "media", "movie",
        "radio", "photo", "store", "files", "games", "smart", "sport", "tube", "kids",
        "live", "news", "game", "cast", "home", "play"
    ].sorted { $0.count > $1.count }

    private static func derive(_ package: String) -> String {
        let segments = package.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        let meaningful = segments.filter { !generic.contains($0.lowercased()) }
        let chosen = meaningful.last ?? segments.last ?? package
        var words = splitToken(chosen)
        if words.joined().count < 2, meaningful.count >= 2 {
            words = splitToken(meaningful[meaningful.count - 2]) + words
        }
        var name = words.map(capitalize).filter { !$0.isEmpty }.joined(separator: " ")
        if name.count < 2 {
            let fallback = segments.map(capitalize).joined()
            name = fallback.count >= 2 ? fallback : "App"
        }
        return name
    }

    private static func splitToken(_ token: String) -> [String] {
        let rough = token.replacingOccurrences(of: "-", with: "_").split(separator: "_").map(String.init)
        let pieces = rough.flatMap { camelPieces($0) }.flatMap { dictionarySplit($0) }
        return pieces.isEmpty ? [token] : pieces
    }

    private static func camelPieces(_ token: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in token {
            if character.isUppercase, !current.isEmpty {
                chunks.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [token] : chunks
    }

    /// Splits a long lowercase blob only when every piece is a known word, so `musicplayer` becomes two words.
    private static func dictionarySplit(_ token: String) -> [String] {
        let lower = token.lowercased()
        guard token == lower, lower.count >= 8 else { return [token] }
        var index = lower.startIndex
        var found: [String] = []
        while index < lower.endIndex {
            var matched: String?
            for word in lexicon where lower[index...].hasPrefix(word) {
                matched = word
                break
            }
            guard let matched else { return [token] }
            found.append(matched)
            index = lower.index(index, offsetBy: matched.count)
        }
        return found.count >= 2 ? found : [token]
    }

    private static func capitalize(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst().lowercased()
    }
}

/// Two of the four glow stops. The index order is cyan, blue, magenta, amber.
public struct AppSwatch: Equatable {
    public var start: Int
    public var end: Int

    public static let stopCount = 4

    public static func pair(for package: String) -> AppSwatch {
        let hash = fnv(package)
        let start = Int(hash % UInt32(stopCount))
        let end = (start + Int((hash / UInt32(stopCount)) % 3) + 1) % stopCount
        return AppSwatch(start: start, end: end)
    }

    private static func fnv(_ text: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }
        return hash
    }
}
