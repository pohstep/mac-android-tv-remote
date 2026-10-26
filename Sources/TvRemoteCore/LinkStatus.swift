import Foundation

public enum LinkStatus: Equatable {
    case idle
    case connecting(serial: String)
    case connected(serial: String)
    case adbMissing(message: String)
    case helperDown
    case unauthorized(serial: String)
    case refused(serial: String, detail: String)
    case unreachable(serial: String)
    case offline(serial: String)
    case failed(message: String)

    public var serial: String? {
        switch self {
        case .connecting(let serial), .connected(let serial), .unauthorized(let serial), .offline(let serial):
            return serial
        case .refused(let serial, _), .unreachable(let serial):
            return serial
        case .idle, .adbMissing, .helperDown, .failed:
            return nil
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var title: String {
        switch self {
        case .idle: return "No TV address yet"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .adbMissing: return "adb isn't installed"
        case .helperDown: return "Helper didn't start"
        case .unauthorized: return "Waiting for the TV"
        case .refused: return "The TV refused the connection"
        case .unreachable: return "Couldn't reach the TV"
        case .offline: return "TV is offline"
        case .failed: return "Couldn't connect"
        }
    }

    public var detail: String {
        switch self {
        case .idle:
            return "Add an IP or Tailscale hostname in Settings."
        case .connecting(let serial):
            return "Reaching \(serial)"
        case .connected(let serial):
            return serial
        case .adbMissing(let message):
            return message
        case .helperDown:
            return Copy.helperDidNotStart
        case .unauthorized(let serial):
            return Copy.unauthorized(serial: serial)
        case .refused(_, let detail):
            return detail
        case .unreachable(let serial):
            return Copy.unreachable(serial: serial)
        case .offline(let serial):
            return Copy.offline(serial: serial)
        case .failed(let message):
            return message
        }
    }
}

public struct ActionReport: Equatable {
    public var title: String
    public var detail: String
    public var isError: Bool

    public init(title: String, detail: String, isError: Bool) {
        self.title = title
        self.detail = detail
        self.isError = isError
    }
}

public struct ReconnectPolicy {
    public init() {}

    /// Connected TVs are polled slowly. Refusals back off so a sleeping TV isn't hammered.
    public func delay(for status: LinkStatus, failures: Int) -> TimeInterval {
        switch status {
        case .connected:
            return 15
        case .idle:
            return 20
        case .adbMissing, .helperDown:
            return 10
        case .connecting:
            return 5
        case .unauthorized, .refused, .unreachable, .offline, .failed:
            let clamped = min(max(failures, 0), 3)
            let multiplier = 1 << clamped
            return min(5 * Double(multiplier), 30)
        }
    }
}
