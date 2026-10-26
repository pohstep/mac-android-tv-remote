import Foundation

public enum Copy {
    public static let brewHint = "Install it with Homebrew: brew install android-platform-tools"

    public static func adbMissing() -> String {
        "adb isn't installed. \(brewHint)"
    }

    public static func adbMissing(at path: String) -> String {
        "adb wasn't found at \(path). \(brewHint)"
    }

    public static func refused(serial: String) -> String {
        "The TV refused the connection to \(serial). Turn on network debugging and check the address."
    }

    public static func unauthorized(serial: String) -> String {
        "This Mac isn't authorized yet. Accept the debugging prompt on the TV (\(serial))."
    }

    public static func offline(serial: String) -> String {
        "\(serial) is offline. The TV may be asleep or still booting."
    }
}
