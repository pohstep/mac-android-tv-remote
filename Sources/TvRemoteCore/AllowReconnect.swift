import Foundation

/// After Allow, some TVs stay unauthorized until `adb disconnect` and `adb connect`
/// on the same address. Others flip to `device` on their own.
public enum AllowReconnect {
    /// Pause between disconnect-and-connect attempts.
    public static let interval: TimeInterval = 3
    /// Stops when the adb command timeout elapses.
    public static let timeout: TimeInterval = 12

    /// Polls with `read`. A `device` result ends the wait. While the TV stays
    /// unauthorized, `reconnect` runs, then the wait sleeps about `interval`,
    /// until `timeout`.
    public static func wait(
        timeout: TimeInterval = timeout,
        interval: TimeInterval = interval,
        sleep: (TimeInterval) -> Void,
        now: () -> Date,
        read: () -> DeviceState,
        reconnect: () -> DeviceState
    ) -> DeviceState {
        let deadline = now().addingTimeInterval(timeout)
        while now() < deadline {
            switch read() {
            case .device:
                return .device
            case .offline:
                return .offline
            case .missing:
                return .missing
            case .unauthorized:
                break
            }
            switch reconnect() {
            case .device:
                return .device
            case .offline:
                return .offline
            case .missing:
                return .missing
            case .unauthorized:
                let remaining = deadline.timeIntervalSince(now())
                if remaining <= 0 { return .unauthorized }
                sleep(min(interval, remaining))
            }
        }
        return .unauthorized
    }
}
