import Foundation

public final class ShellRunner: CommandRunning {
    public init() {}

    public func cancel() {}

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        try run(executable, arguments: arguments, timeout: timeout, environment: [:])
    }

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval, environment: [String: String]) throws -> CommandResult {
        _ = arguments
        _ = timeout
        _ = environment
        throw RemoteError.notFound(executable)
    }
}
