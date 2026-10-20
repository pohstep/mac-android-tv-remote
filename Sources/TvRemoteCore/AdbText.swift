import Foundation

public enum AdbText {
    /// Payloads for `adb shell input text`. Spaces become `%s`.
    /// A literal `%` is its own command so it is not eaten when the next
    /// character is `s` (Android treats `%s` as a space).
    public static func shellPayloads(_ text: String) -> [String] {
        var payloads: [String] = []
        var buffer = ""

        func flush() {
            if !buffer.isEmpty {
                payloads.append(quote(buffer))
                buffer = ""
            }
        }

        for character in text {
            if character == "%" {
                flush()
                payloads.append(quote("%"))
            } else if character == " " || character == "\n" || character == "\t" {
                buffer += "%s"
            } else {
                buffer.append(character)
            }
        }
        flush()
        return payloads
    }

    public static func quote(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
