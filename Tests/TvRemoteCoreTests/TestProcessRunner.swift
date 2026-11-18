import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import TvRemoteCore

final class TestProcessRunner: CommandRunning {
    private let state = NSLock()
    private var running: Process?

    func cancel() {
        state.lock()
        let process = running
        state.unlock()
        guard let process else { return }
        let pid = process.processIdentifier
        if pid > 0 {
            _ = kill(pid, SIGKILL)
        }
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        try run(executable, arguments: arguments, timeout: timeout, environment: [:])
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval, environment: [String: String]) throws -> CommandResult {
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
        state.lock()
        running = process
        state.unlock()
        defer {
            state.lock()
            if running === process { running = nil }
            state.unlock()
        }
        try process.run()
        let group = DispatchGroup()
        let stdoutBox = LockedData()
        let stderrBox = LockedData()
        group.enter()
        DispatchQueue.global().async {
            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
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

private final class LockedData {
    var data = Data()
}
