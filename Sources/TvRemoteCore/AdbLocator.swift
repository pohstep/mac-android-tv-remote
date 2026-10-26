import Foundation

public struct AdbLocator {
    public var candidatePaths: [String]
    public var pathEnvironment: String
    public var fileExists: (String) -> Bool
    /// `Contents/Helpers/adb` inside the app bundle. Preferred when the file is there.
    public var bundledHelperPath: String?
    /// Sandboxed builds do not fall back to a user-installed adb.
    public var allowUserInstall: Bool

    public init(
        candidatePaths: [String],
        pathEnvironment: String,
        fileExists: @escaping (String) -> Bool,
        bundledHelperPath: String? = nil,
        allowUserInstall: Bool = true
    ) {
        self.candidatePaths = candidatePaths
        self.pathEnvironment = pathEnvironment
        self.fileExists = fileExists
        self.bundledHelperPath = bundledHelperPath
        self.allowUserInstall = allowUserInstall
    }

    public static func helperPath(bundlePath: String) -> String {
        let root = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        return root + "/Contents/Helpers/adb"
    }

    public static func defaultCandidates(homeDirectory: String) -> [String] {
        [
            "/usr/local/bin/adb",
            "/opt/homebrew/bin/adb",
            homeDirectory + "/Library/Android/sdk/platform-tools/adb",
            homeDirectory + "/Android/Sdk/platform-tools/adb",
            "/usr/bin/adb"
        ]
    }

    /// GUI apps on macOS do not inherit a Homebrew PATH, so Intel (`/usr/local`)
    /// and Apple Silicon (`/opt/homebrew`) prefixes are checked explicitly.
    public func resolve(customPath: String?) -> String? {
        if let bundledHelperPath {
            let bundled = bundledHelperPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bundled.isEmpty, fileExists(bundled) {
                return bundled
            }
        }
        guard allowUserInstall else { return nil }
        if let customPath {
            let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return fileExists(trimmed) ? trimmed : nil
            }
        }
        for path in candidatePaths where fileExists(path) {
            return path
        }
        for directory in pathEnvironment.split(separator: ":") {
            let full = String(directory) + "/adb"
            if fileExists(full) { return full }
        }
        return nil
    }
}
