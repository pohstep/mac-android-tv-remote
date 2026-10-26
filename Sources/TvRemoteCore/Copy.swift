import Foundation

public enum Copy {
    public static let helperMissing = "Zapbar's built-in helper is missing. Reinstall Zapbar."
    public static let stoppedAnswering = "The TV stopped answering."

    public static func adbMissing() -> String {
        #if SANDBOX_BUILD
        helperMissing
        #else
        "adb isn't installed. \(developerBrewHint)"
        #endif
    }

    public static func adbMissing(at path: String) -> String {
        #if SANDBOX_BUILD
        helperMissing
        #else
        "adb wasn't found at \(path). \(developerBrewHint)"
        #endif
    }

    #if !SANDBOX_BUILD
    /// Developer builds only. The sandboxed app does not compile this sentence.
    static let developerBrewHint = "Install it with Homebrew: brew install android-platform-tools"
    #endif

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
