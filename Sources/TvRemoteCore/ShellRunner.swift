import Foundation

public final class ShellRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw RemoteError.notFound(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

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

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: stdoutBox.data, encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.data, encoding: .utf8) ?? ""
        )
    }
}

private final class PipeBuffer {
    var data = Data()
}
