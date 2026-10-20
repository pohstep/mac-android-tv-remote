import Foundation

public struct AdbLocator {
    public var candidatePaths: [String]
    public var pathEnvironment: String
    public var fileExists: (String) -> Bool

    public init(candidatePaths: [String], pathEnvironment: String, fileExists: @escaping (String) -> Bool) {
        self.candidatePaths = candidatePaths
        self.pathEnvironment = pathEnvironment
        self.fileExists = fileExists
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
