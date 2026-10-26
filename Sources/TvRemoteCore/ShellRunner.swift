import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class ShellRunner: CommandRunning {
    private let state = NSLock()
    private var running: Process?

    public init() {}

    public func cancel() {
        state.lock()
        let process = running
        state.unlock()
        guard let process else { return }
        let pid = process.processIdentifier
        // SIGKILL. Process.terminate() from another thread does not stop the child.
        if pid > 0 {
            _ = kill(pid, SIGKILL)
        }
    }

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        try run(executable, arguments: arguments, timeout: timeout, environment: [:])
    }

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval, environment: [String: String]) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw RemoteError.notFound(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment where !value.isEmpty {
                env[key] = value
            }
            process.environment = env
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let queue = DispatchQueue(label: "app.pohstep.remote.shell", attributes: .concurrent)
        let stdoutBox = PipeBuffer()
        let stderrBox = PipeBuffer()
        let group = DispatchGroup()

        group.enter()
        queue.async {
            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        queue.async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        state.lock()
        running = process
        state.unlock()
        defer {
            state.lock()
            if running === process { running = nil }
            state.unlock()
        }

        do {
            try process.run()
        } catch {
            throw RemoteError.notFound(executable)
        }

        let wait = group.wait(timeout: .now() + timeout)
        if wait == .timedOut {
            if process.isRunning { process.terminate() }
            _ = group.wait(timeout: .now() + 2)
            throw RemoteError.timedOut(executable)
        }
        process.waitUntilExit()

        let bytes = stdoutBox.data
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: bytes, encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.data, encoding: .utf8) ?? "",
            stdoutData: bytes
        )
    }
}

private final class PipeBuffer {
    var data = Data()
}
