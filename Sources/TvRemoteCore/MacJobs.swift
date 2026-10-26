import Foundation

public struct JobReport: Equatable {
    public var sentence: String
    public var raw: String
    public var isError: Bool

    public init(sentence: String, raw: String, isError: Bool) {
        self.sentence = sentence
        self.raw = raw
        self.isError = isError
    }
}

public struct ScreenshotResult: Equatable {
    public var png: Data?
    public var sentence: String
    public var raw: String
    public var isError: Bool

    public init(png: Data?, sentence: String, raw: String, isError: Bool) {
        self.png = png
        self.sentence = sentence
        self.raw = raw
        self.isError = isError
    }
}

public enum InstallExplain {
    public static func sentence(status: Int32, output: String) -> String {
        let lower = output.lowercased()
        if status == 0 && !lower.contains("failure") {
            return "Installed."
        }
        switch failureCode(output) {
        case "INSTALL_FAILED_VERSION_DOWNGRADE":
            return "The TV already has a newer version of this app."
        case "INSTALL_FAILED_UPDATE_INCOMPATIBLE":
            return "This file doesn't match the app already on the TV."
        case "INSTALL_FAILED_INSUFFICIENT_STORAGE":
            return "The TV doesn't have enough free space."
        case "INSTALL_FAILED_OLDER_SDK":
            return "This app needs a newer system than the TV has."
        case "INSTALL_FAILED_NO_MATCHING_ABIS", "INSTALL_FAILED_CPU_ABI_INCOMPATIBLE":
            return "This app isn't built for this TV."
        case "INSTALL_FAILED_USER_RESTRICTED":
            return "The TV blocked the install. Check the TV's install settings."
        case "INSTALL_FAILED_VERIFICATION_FAILURE", "INSTALL_FAILED_VERIFICATION_TIMEOUT":
            return "The TV blocked the install."
        case "INSTALL_FAILED_INVALID_APK", "INSTALL_PARSE_FAILED_NOT_APK":
            return "That file isn't an installable app."
        case "INSTALL_FAILED_ABORTED":
            return "The TV cancelled the install."
        case "INSTALL_FAILED_MISSING_SHARED_LIBRARY":
            return "The TV is missing a library this app needs."
        case nil:
            return "The install didn't finish."
        default:
            return "The TV refused the install."
        }
    }

    public static func failureCode(_ text: String) -> String? {
        guard let range = text.range(of: #"INSTALL_[A-Z0-9_]+"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

public enum LinkSend {
    /// http and https only. Anything else, including a missing host, is refused.
    public static func httpURL(from raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        guard let host = parts.host, !host.isEmpty else { return nil }
        parts.scheme = scheme
        return parts.string
    }

    public static func sentence(status: Int32, output: String) -> String {
        if AdbOutput.cannotOpenView(output) {
            return Copy.nothingCanOpen
        }
        if AdbOutput.outputIndicatesFailure(output, status: status) {
            return "The TV didn't open that link. It needs a browser."
        }
        return "Opened on the TV."
    }
}

public enum FileSend {
    public static let playerSentence = "Sent. The TV needs a player to open it."
    public static let playerLeftBehind = "The file is in Downloads. The TV needs a player to open it."
    /// Push finished and the open command failed. The file is still in Downloads.
    public static let stayedOnTV = "The file is on the TV in Downloads, but it did not open."

    public static func downloadPath(for localPath: String) -> String {
        var name = URL(fileURLWithPath: localPath).lastPathComponent
        if name.isEmpty || name == "." || name == "/" { name = "file" }
        name = name.replacingOccurrences(of: "/", with: "")
        return "/sdcard/Download/\(name)"
    }

    public static func fileURL(remotePath: String) -> String {
        let encoded = remotePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remotePath
        return "file://\(encoded)"
    }

    public static func mimeType(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mkv": return "video/x-matroska"
        case "webm": return "video/webm"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "mp3": return "audio/mpeg"
        case "m4a", "aac": return "audio/mp4"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    public static func pushSentence(status: Int32, output: String) -> String {
        let lower = output.lowercased()
        if status == 0 && !lower.contains("error") && !lower.contains("failed") {
            return playerSentence
        }
        if lower.contains("no space") || lower.contains("insufficient") {
            return "The TV doesn't have enough free space."
        }
        if lower.contains("permission denied") || lower.contains("read-only") {
            return "The TV refused that folder."
        }
        return "The file didn't reach the TV."
    }
}

public enum ScreenshotCapture {
    public static let remotePath = "/sdcard/Download/zapbar-screen.png"

    /// A valid PNG, including an all-black frame, is kept. A broken exec-out result uses the fallback bytes.
    public static func resolve(execOut: Data, fallbackRaw: String = "", fallback: () -> (Data, String)) -> ScreenshotResult {
        switch ScreenshotBytes.kind(execOut) {
        case .picture:
            return ScreenshotResult(png: execOut, sentence: "Screenshot ready.", raw: "", isError: false)
        case .blank:
            return ScreenshotResult(png: execOut, sentence: ScreenshotBytes.blankSentence, raw: "", isError: false)
        case .broken:
            let pulled = fallback()
            switch ScreenshotBytes.kind(pulled.0) {
            case .picture:
                return ScreenshotResult(png: pulled.0, sentence: "Screenshot ready.", raw: pulled.1, isError: false)
            case .blank:
                return ScreenshotResult(png: pulled.0, sentence: ScreenshotBytes.blankSentence, raw: pulled.1, isError: false)
            case .broken:
                return ScreenshotResult(png: nil, sentence: "The screenshot didn't come back.", raw: pulled.1, isError: true)
            }
        }
    }
}

public enum ScreenshotSave {
    public static let defaultName = "Zapbar screenshot.png"

    /// Next free file name. Never returns a name that is already in `existing`.
    public static func availableName(existing: Set<String>, preferred: String = defaultName) -> String {
        if !existing.contains(preferred) { return preferred }
        let url = URL(fileURLWithPath: preferred)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            if !existing.contains(candidate) { return candidate }
            number += 1
            if number > 10000 { return candidate }
        }
    }
}

public enum SerialTransfers {
    /// Runs `body` on each path, and only starts the next after the previous returns. Stops on the first error.
    public static func run(_ paths: [String], body: (String) -> JobReport) -> JobReport {
        var last = JobReport(sentence: "Installed.", raw: "", isError: false)
        for path in paths {
            last = body(path)
            if last.isError { return last }
        }
        return last
    }
}
