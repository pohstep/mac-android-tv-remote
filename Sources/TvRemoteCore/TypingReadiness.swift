import Foundation

public enum TypingField: Equatable {
    case ready
    case notReady
    case unknown
}

public enum TypingReadiness {
    public static let notReady = "Nothing on the TV is ready for typing. Open a search or text box on the TV, then Send again."

    /// `dumpsys input_method`. A served view or a visible keyboard means a field is ready.
    /// `mServedView=null` or a hidden keyboard means it is not. Anything else is unknown.
    public static func reading(_ dump: String) -> TypingField {
        let lower = dump.lowercased()
        if lower.contains("minputshown=true") { return .ready }
        if lower.range(of: #"mservedview\s*=\s*null\b"#, options: .regularExpression) != nil {
            return .notReady
        }
        if lower.range(of: #"mservedview\s*=\s*\S+"#, options: .regularExpression) != nil {
            return .ready
        }
        if lower.contains("minputshown=false") { return .notReady }
        return .unknown
    }
}

public struct EditMenuItem: Equatable {
    public var title: String
    public var keyEquivalent: String
    public var action: String

    public init(title: String, keyEquivalent: String, action: String) {
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.action = action
    }
}

/// Cut, Copy, Paste, and Select All. The Mac app installs these on the main menu
/// so a menu-bar app can paste into the focused field.
public enum StandardEditMenu {
    public static let items: [EditMenuItem] = [
        EditMenuItem(title: "Cut", keyEquivalent: "x", action: "cut:"),
        EditMenuItem(title: "Copy", keyEquivalent: "c", action: "copy:"),
        EditMenuItem(title: "Paste", keyEquivalent: "v", action: "paste:"),
        EditMenuItem(title: "Select All", keyEquivalent: "a", action: "selectAll:")
    ]
}

public enum DroppedText {
    /// A dropped string or URL, kept as the user dropped it. No scheme check.
    public static func plain(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
