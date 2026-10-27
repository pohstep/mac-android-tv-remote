import Foundation

public enum JobKind: Equatable {
    case install
    case screenshot
    case other
}

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

    public static let unknownStep = "Check the TV and the network, then choose the .apk again."
    public static let reconnectStep = "Reconnect the TV, then choose the .apk again."

    /// What to do next. Install failures always have a step. Screenshot failures use their own.
    public static func recovery(for sentence: String, kind: JobKind = .install) -> String? {
        if sentence == TransferGate.busySentence {
            return TransferGate.busyStep
        }
        if kind == .screenshot {
            return screenshotRecovery(sentence)
        }
        return installRecovery(sentence)
    }

    private static func installRecovery(_ sentence: String) -> String? {
        switch sentence {
        case "Installed.", "Cancelled.", "Taking a screenshot…", "Screenshot ready.",
             "Copied.", "Saved", "Couldn't save",
             "Couldn't save. Choose another folder and press Save… again.",
             ScreenshotCapture.asleep, ApkPick.onlyApk:
            return nil
        case "The TV already has a newer version of this app.":
            return "Choose a newer .apk."
        case "This file doesn't match the app already on the TV.":
            return "Remove that app on the TV, then choose the .apk again."
        case "The TV doesn't have enough free space.":
            return "Free some space on the TV, then choose the .apk again."
        case "This app needs a newer system than the TV has.", "This app isn't built for this TV.":
            return "Choose an app built for this TV."
        case "The TV blocked the install. Check the TV's install settings.":
            return "Then choose the .apk again."
        case "The TV blocked the install.":
            return "Allow the install on the TV, then choose the .apk again."
        case "That file isn't an installable app.", "The TV is missing a library this app needs.":
            return "Choose a different .apk."
        case "The TV cancelled the install.", "The TV refused the install.", "The install didn't finish.":
            return "Check the TV, then choose the .apk again."
        case "That file can't be read.":
            return "Choose the .apk again."
        case Copy.notConnected:
            return reconnectStep
        case Copy.helperMissing, Copy.helperDidNotStart:
            return nil
        default:
            if sentence.hasPrefix("This Mac isn't allowed yet") || sentence.hasPrefix("This Mac isn't authorized") {
                return "Accept the prompt on the TV, then choose the .apk again."
            }
            if sentence.hasSuffix("is offline. The TV may be asleep or still booting.") {
                return "Wake the TV, then choose the .apk again."
            }
            return unknownStep
        }
    }

    private static func screenshotRecovery(_ sentence: String) -> String? {
        switch sentence {
        case "Screenshot ready.", "Taking a screenshot…", "Copied.", "Saved", "Cancelled.",
             ScreenshotCapture.asleep, ScreenshotBytes.blankSentence:
            return nil
        case "The screenshot didn't come back.":
            return "Press Screenshot again. If the TV is showing protected video, try another screen."
        case "Couldn't save", "Couldn't save. Choose another folder and press Save… again.":
            return nil
        case ScreenshotCapture.needsLink:
            return "Check the connection, then press Screenshot."
        default:
            return "Check the connection, then press Screenshot."
        }
    }

    public static func failureCode(_ text: String) -> String? {
        guard let range = text.range(of: #"INSTALL_[A-Z0-9_]+"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

public enum ApkPick {
    public static let onlyApk = "Only .apk files can be installed. Choose an .apk…"

    public static func isApk(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".apk")
    }

    public static func skipped(_ count: Int) -> String {
        if count == 1 {
            return "Skipped 1 file that isn't an .apk."
        }
        return "Skipped \(count) files that aren't .apk."
    }

    /// Adds the skipped-file sentence onto a finished install result.
    public static func notingSkipped(_ report: JobReport, skipped count: Int) -> JobReport {
        guard count > 0 else { return report }
        let note = skipped(count)
        let sentence = report.sentence.isEmpty ? note : "\(report.sentence) \(note)"
        return JobReport(sentence: sentence, raw: report.raw, isError: report.isError)
    }
}

public enum InstallLog {
    /// The text shown in Show log and copied from it. The cause, the next step, then the raw install output.
    public static func text(sentence: String, raw: String) -> String {
        var lines = [sentence]
        if let step = InstallExplain.recovery(for: sentence), !step.isEmpty {
            lines.append(step)
        }
        let detail = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            lines.append(detail)
        }
        return lines.joined(separator: "\n")
    }

    public static func append(_ log: String, _ entry: String) -> String {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return log }
        if log.isEmpty { return trimmed }
        return log + "\n\n" + trimmed
    }
}

public enum ScreenshotCapture {
    public static let remotePath = "/sdcard/Download/zapbar-screen.png"
    /// A sleeping TV gives no picture, and asking it takes about half a minute. Say so first.
    public static let asleep = "The TV is asleep. Turn it on first."
    public static let needsLink = "The TV isn't connected."

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

    /// Desktop when that folder URL exists, otherwise Pictures. The panel may start there even if this process cannot read the folder.
    public static func startDirectory(desktop: URL?, pictures: URL?) -> URL? {
        desktop ?? pictures
    }

    public static func fileName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Zapbar Screenshot \(formatter.string(from: date)).png"
    }

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
