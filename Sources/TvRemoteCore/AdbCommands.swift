import Foundation

public struct CommandResult: Equatable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    /// Raw standard output. Text commands leave this as the UTF-8 bytes of `stdout`.
    /// `screencap` keeps the PNG here, because those bytes are not text.
    public var stdoutData: Data

    public init(status: Int32, stdout: String, stderr: String, stdoutData: Data? = nil) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutData = stdoutData ?? Data(stdout.utf8)
    }

    public var combined: String {
        if stderr.isEmpty { return stdout }
        if stdout.isEmpty { return stderr }
        return stdout + "\n" + stderr
    }
}

public protocol CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult
    func run(_ executable: String, arguments: [String], timeout: TimeInterval, environment: [String: String]) throws -> CommandResult
    /// Stops the command started by `run`, if one is still running.
    func cancel()
}

public extension CommandRunning {
    func cancel() {}
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

    public static func disconnect(host: String, port: Int) -> [String] {
        ["disconnect", "\(host):\(port)"]
    }

    public static func pair(host: String, port: Int, code: String) -> [String] {
        ["pair", "\(host):\(port)", code]
    }

    public static func devices() -> [String] {
        ["devices"]
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

    /// Local path is one argument, so spaces in the filename stay intact.
    public static func install(serial: String, apkPath: String) -> [String] {
        ["-s", serial, "install", "-r", apkPath]
    }

    public static func screencap(serial: String) -> [String] {
        ["-s", serial, "exec-out", "screencap", "-p"]
    }

    public static func screencapFile(serial: String, remotePath: String) -> [String] {
        ["-s", serial, "shell", "screencap -p \(ShellWords.quote(remotePath))"]
    }

    public static func pull(serial: String, remotePath: String, localPath: String) -> [String] {
        ["-s", serial, "pull", remotePath, localPath]
    }

    public static func removeRemote(serial: String, remotePath: String) -> [String] {
        ["-s", serial, "shell", "rm -f \(ShellWords.quote(remotePath))"]
    }

}

public enum ShellWords {
    /// Single-quote a string for the device shell so spaces and `&` stay in one word.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum AdbOutput {
    public static func parsePair(_ text: String) -> Bool {
        text.lowercased().contains("successfully paired")
    }

    public static func parseConnect(_ text: String) -> ConnectOutcome {
        let lower = text.lowercased()
        if lower.contains("already connected") { return .alreadyConnected }
        if lower.contains("connected to") { return .connected }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failed("The TV didn't answer. Check the connection and try again.") }
        return .failed(trimmed)
    }

    /// A TV refusal, such as "Connection refused" for that TV's host and port.
    /// "failed to connect to", "cannot connect to daemon", and "cannot start server"
    /// are the helper failing to start, not the TV turning the Mac away.
    public static func isRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        if isDaemonFailure(lower) || lower.contains("failed to connect to") {
            return false
        }
        return lower.contains("refused")
    }

    /// The helper never started its own server, so the TV was not contacted.
    public static func isDaemonFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("cannot connect to daemon") || lower.contains("cannot start server")
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

    /// `am start` VIEW failed because nothing on the TV handles that link or file.
    public static func cannotOpenView(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("unable to resolve intent")
            || lower.contains("no activity found to handle intent")
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
