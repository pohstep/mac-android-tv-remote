import Foundation

public struct CommandResult: Equatable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combined: String {
        if stderr.isEmpty { return stdout }
        if stdout.isEmpty { return stderr }
        return stdout + "\n" + stderr
    }
}

public protocol CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult
}

public enum ConnectOutcome: Equatable {
    case connected
    case alreadyConnected
    case failed(String)

    public var failureDetail: String {
        if case .failed(let detail) = self { return detail }
        return ""
    }
}

public enum DeviceState: Equatable {
    case device
    case unauthorized
    case offline
    case missing
}

public enum AdbCommands {
    public static func connect(host: String, port: Int) -> [String] {
        ["connect", "\(host):\(port)"]
    }

    public static func devices() -> [String] {
        ["devices"]
    }

    public static func launcherIndex(serial: String) -> [String] {
        ["-s", serial, "shell", "cat", AppIndex.launcherPath]
    }

    public static func leanbackActivities(serial: String) -> [String] {
        [
            "-s", serial, "shell", "cmd", "package", "query-activities",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.LEANBACK_LAUNCHER"
        ]
    }

    public static func packageDump(serial: String, packageName: String) -> [String] {
        ["-s", serial, "shell", "cmd", "package", "dump", packageName]
    }

    public static func keyEvent(serial: String, key: AndroidKey) -> [String] {
        ["-s", serial, "shell", "input", "keyevent", key.rawValue]
    }

    public static func text(serial: String, payload: String) -> [String] {
        ["-s", serial, "shell", "input", "text", payload]
    }

    public static func launchLeanback(serial: String, packageName: String) -> [String] {
        [
            "-s", serial, "shell", "am", "start",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.LEANBACK_LAUNCHER",
            "-p", packageName
        ]
    }

    public static func launchMonkey(serial: String, packageName: String, category: String) -> [String] {
        ["-s", serial, "shell", "monkey", "-p", packageName, "-c", category, "1"]
    }
}

public enum AdbOutput {
    public static func parseConnect(_ text: String) -> ConnectOutcome {
        let lower = text.lowercased()
        if lower.contains("already connected") { return .alreadyConnected }
        if lower.contains("connected to") { return .connected }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failed("adb connect returned nothing") }
        return .failed(trimmed)
    }

    public static func isRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("refused")
            || lower.contains("failed to connect")
            || lower.contains("cannot connect")
            || lower.contains("connection refused")
    }

    public static func parseDevices(_ text: String, serial: String) -> DeviceState {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("List of devices") || line.hasPrefix("*") {
                continue
            }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2, parts[0] == serial else { continue }
            switch parts[1] {
            case "device": return .device
            case "unauthorized": return .unauthorized
            case "offline": return .offline
            default: return .offline
            }
        }
        return .missing
    }

    public static func outputIndicatesFailure(_ text: String, status: Int32) -> Bool {
        if status != 0 { return true }
        let lower = text.lowercased()
        let needles = [
            "error:",
            "unable to resolve",
            "does not exist",
            "no activities found",
            "monkey aborted",
            "securityexception"
        ]
        return needles.contains { lower.contains($0) }
    }
}

public enum PackageName {
    public static func isValid(_ name: String) -> Bool {
        let pattern = #"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
