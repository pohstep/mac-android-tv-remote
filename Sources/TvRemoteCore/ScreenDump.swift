import Foundation

public struct NowPlaying: Equatable {
    public var title: String
    public var artist: String
    public var isPlaying: Bool

    public var line: String {
        if title.isEmpty { return artist }
        if artist.isEmpty { return title }
        return "\(title) — \(artist)"
    }
}

public enum ScreenDump {
    /// Package in front, from `dumpsys window`.
    public static func foregroundPackage(_ dump: String) -> String? {
        let patterns = [
            #"mCurrentFocus=Window\{[^\n]* ([A-Za-z0-9_.]+)/"#,
            #"mFocusedApp=.*? ([A-Za-z0-9_.]+)/"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(dump.startIndex..., in: dump)
            guard let match = regex.firstMatch(in: dump, range: range), match.numberOfRanges > 1,
                  let hit = Range(match.range(at: 1), in: dump) else { continue }
            let package = String(dump[hit])
            if package.contains(".") { return package }
        }
        return nil
    }

    /// Title and artist from `dumpsys media_session`.
    public static func nowPlaying(_ dump: String) -> NowPlaying? {
        let title = metadata(dump, key: "android.media.metadata.TITLE")
        let artist = metadata(dump, key: "android.media.metadata.ARTIST")
        let playing = dump.contains("state=PLAYING") || dump.contains("state=PlaybackState {state=3")
            || dump.contains("state=PlaybackState {state=PLAYING")
        guard !title.isEmpty || !artist.isEmpty || playing else { return nil }
        return NowPlaying(title: title, artist: artist, isPlaying: playing)
    }

    private static func metadata(_ dump: String, key: String) -> String {
        for raw in dump.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let prefix = key + "="
            guard line.hasPrefix(prefix) else { continue }
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
}
