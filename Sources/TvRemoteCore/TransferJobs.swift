import Foundation

/// One transfer at a time. A finish call clears the busy flag only for the token that set it.
public final class TransferGate {
    public static let busySentence = "One transfer at a time."
    public static let busyStep = "Wait for the current transfer."

    private let lock = NSLock()
    private var next: UInt = 0
    private var token: UInt = 0
    private var activeLine = ""
    private var directories: [String] = []
    private var isBusy = false

    public init() {}

    public var busy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isBusy
    }

    public var line: String {
        lock.lock()
        defer { lock.unlock() }
        return activeLine
    }

    /// Nil when a job is already running. The previous job is left alone.
    public func begin(line: String, directories: [String] = []) -> UInt? {
        lock.lock()
        defer { lock.unlock() }
        if isBusy { return nil }
        next += 1
        token = next
        isBusy = true
        activeLine = line
        self.directories = directories
        return token
    }

    public func update(token: UInt, line: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isBusy, token == self.token else { return false }
        activeLine = line
        return true
    }

    /// Directories owned by this job. Nil when `token` is not the job that set the busy flag.
    public func finish(token: UInt) -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        guard isBusy, token == self.token else { return nil }
        let owned = directories
        isBusy = false
        directories = []
        self.token = 0
        return owned
    }
}

public enum ReadableStage {
    public static func directory(in temporaryDirectory: String, jobID: String) -> String {
        URL(fileURLWithPath: temporaryDirectory, isDirectory: true)
            .appendingPathComponent("zapbar-transfer-\(jobID)", isDirectory: true)
            .path
    }

    /// Copies `url` into a new directory. The caller removes that directory when the job ends.
    public static func copy(url: URL, into directory: String) throws -> String {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let dest = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(url.lastPathComponent)
        if dest.path == url.path { return url.path }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest.path
    }

    public static func remove(_ directory: String) {
        guard directory.contains("zapbar-transfer-") else { return }
        try? FileManager.default.removeItem(atPath: directory)
    }
}
