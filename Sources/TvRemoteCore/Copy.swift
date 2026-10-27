import Foundation

public enum Copy {
    public static let helperMissing = "Zapbar's connection helper is missing. Reinstall Zapbar."
    public static let helperDidNotStart = "Zapbar's helper couldn't start. Quit and reopen Zapbar."
    public static let stoppedAnswering = "The TV stopped answering."
    public static let notConnected = "The TV isn't connected."

    public static func adbMissing() -> String {
        helperMissing
    }

    public static func adbMissing(at _: String) -> String {
        helperMissing
    }

    public static func refused(serial: String) -> String {
        "The TV refused the connection to \(serial). On the TV, allow this Mac, and check the address in Settings."
    }

    public static func unreachable(serial: String) -> String {
        "Couldn't reach the TV at \(serial). Check that it is on and on the same network, then try again."
    }

    public static func unauthorized(serial: String) -> String {
        "This Mac isn't allowed yet. Accept the prompt on the TV (\(serial))."
    }

    public static func offline(serial: String) -> String {
        "\(serial) is offline. The TV may be asleep or still booting."
    }
}
