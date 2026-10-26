import Foundation

public enum TypeRoute: Equatable {
    case adb
    case sony
    case unsupported(String)
}

/// ASCII goes over adb `input text`. Other characters, including Chinese,
/// go through Sony `setTextForm` when a text field is open. A route that
/// cannot type returns a message instead of sending a partial command.
public enum TypingRoute {
    public static func isASCII(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.isASCII }
    }

    public static func choose(text: String, brand: TvBrand, sonyAvailable: Bool, adbAvailable: Bool) -> TypeRoute {
        if brand == .xiaomi {
            return .unsupported("This TV can't type from the remote.")
        }
        if !isASCII(text) {
            if brand == .sony && sonyAvailable {
                return .sony
            }
            return .unsupported("Those characters need a Sony TV with a text field open. This connection only types plain letters and numbers.")
        }
        if adbAvailable {
            return .adb
        }
        if brand == .sony && sonyAvailable {
            return .sony
        }
        return .unsupported("Typing needs a network debugging connection, or a Sony TV with a text field open.")
    }
}
