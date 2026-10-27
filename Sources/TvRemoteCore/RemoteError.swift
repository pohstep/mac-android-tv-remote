import Foundation

public enum RemoteError: Error, Equatable, CustomStringConvertible {
    case notFound(String)
    case timedOut(String)
    case commandFailed(String)
    case invalidMac(String)
    case invalidBroadcast(String)

    public var description: String {
        switch self {
        case .notFound(let path):
            return "Couldn't run \(path)."
        case .timedOut:
            return Copy.stoppedAnswering
        case .commandFailed(let detail):
            return detail.isEmpty ? "The adb command failed." : detail
        case .invalidMac:
            return PowerActions.couldNotTurnOn
        case .invalidBroadcast(let value):
            return "\(value) isn't an IPv4 broadcast address."
        }
    }
}
