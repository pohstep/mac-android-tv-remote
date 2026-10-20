import Foundation

public enum HostInput {
    /// Accepts a bare IP or hostname, `host:port`, or a pasted `adb connect` line.
    public static func normalize(_ raw: String) -> (host: String, port: Int?) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "adb connect "
        if text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        text = text.replacingOccurrences(of: " ", with: "")
        if let scheme = text.range(of: "://") {
            text = String(text[scheme.upperBound...])
        }
        if let slash = text.firstIndex(of: "/") {
            text = String(text[..<slash])
        }
        let colons = text.filter { $0 == ":" }.count
        if colons == 1, let colon = text.lastIndex(of: ":") {
            let host = String(text[..<colon])
            let portText = String(text[text.index(after: colon)...])
            if let port = Int(portText), (1...65535).contains(port), !host.isEmpty {
                return (host, port)
            }
        }
        return (text, nil)
    }

    public static func isValidHost(_ host: String) -> Bool {
        if host.isEmpty || host.count > 253 { return false }
        if host.hasPrefix(".") || host.hasSuffix(".") || host.hasPrefix("-") { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return host.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
