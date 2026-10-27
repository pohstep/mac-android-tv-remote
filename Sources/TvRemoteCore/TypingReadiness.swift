import Foundation

public enum TypingField: Equatable {
    case ready
    case notReady
    case unknown
}

public enum TypingReadiness {
    public static let notReady = "No text field is focused on the TV. Open a search or text box on the TV, then press Retry."
    public static let empty = "Type something to send."

    /// `dumpsys input_method`. Ready only when the keyboard is actually shown.
    /// A hidden keyboard is not ready even if a view is served (Netflix). A nested
    /// `mServedView=null` is not ready. A served view with no shown keyboard is not ready.
    public static func reading(_ dump: String) -> TypingField {
        let lower = dump.lowercased()
        if lower.contains("minputshown=false") { return .notReady }
        if lower.contains("minputshown=true") { return .ready }
        if lower.range(of: #"mservedview\s*=\s*null\b"#, options: .regularExpression) != nil {
            return .notReady
        }
        if lower.range(of: #"mservedview\s*=\s*\S+"#, options: .regularExpression) != nil {
            return .notReady
        }
        return .unknown
    }

    public static func showRetry(failed: Bool) -> Bool { failed }

    public static func showSetup(failed: Bool, connected: Bool) -> Bool {
        failed && !connected
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

    /// Adds dropped text onto what is already in the field. A file URL is not text.
    public static func append(_ existing: String, _ raw: String) -> String {
        let text = plain(raw)
        guard !text.isEmpty else { return existing }
        if existing.isEmpty { return text }
        if existing.contains("\n") || text.contains("\n") {
            let separator = existing.hasSuffix("\n") ? "" : "\n"
            return existing + separator + text
        }
        let separator = existing.hasSuffix(" ") ? "" : " "
        return existing + separator + text
    }

    /// `public.file-url` belongs to the install drop, not the type field.
    public static func isFileDrop(_ typeIdentifiers: [String]) -> Bool {
        typeIdentifiers.contains("public.file-url")
    }
}
