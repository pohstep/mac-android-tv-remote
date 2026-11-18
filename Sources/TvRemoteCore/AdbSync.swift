import Foundation

public enum AdbSync {
    public static let send: UInt32 = id("SEND")
    public static let data: UInt32 = id("DATA")
    public static let done: UInt32 = id("DONE")
    public static let okay: UInt32 = id("OKAY")
    public static let fail: UInt32 = id("FAIL")
    public static let maxChunk = 64 * 1024
    public static let fileMode: UInt32 = 33188

    public static func push(path: String, bytes: Data, mode: UInt32 = fileMode) -> Data {
        let named = path + "," + String(mode)
        var body = Data()
        body.append(uint32(send))
        body.append(uint32(UInt32(named.utf8.count)))
        body.append(Data(named.utf8))
        var offset = 0
        let raw = [UInt8](bytes)
        while offset < raw.count {
            let end = min(offset + maxChunk, raw.count)
            let chunk = Data(raw[offset..<end])
            body.append(uint32(data))
            body.append(uint32(UInt32(chunk.count)))
            body.append(chunk)
            offset = end
        }
        body.append(uint32(done))
        body.append(uint32(0))
        return body
    }

    public static func id(_ text: String) -> UInt32 {
        let bytes = Array(text.utf8)
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }
}

private func uint32(_ value: UInt32) -> Data {
    var little = value.littleEndian
    return Data(bytes: &little, count: 4)
}

public struct NeverTouchGuard: Equatable {
    public struct Prefix: Equatable {
        public var text: String
        public var exceptions: Set<String>
    }

    public var exact: Set<String>
    public var prefixes: [Prefix]

    public init(exact: Set<String>, prefixes: [Prefix]) {
        self.exact = exact
        self.prefixes = prefixes
    }

    public func blocks(_ package: String) -> Bool {
        if exact.contains(package) { return true }
        for prefix in prefixes where package.hasPrefix(prefix.text) {
            if prefix.exceptions.contains(package) { return false }
            return true
        }
        return false
    }

    public static func load(_ data: Data) -> NeverTouchGuard {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return NeverTouchGuard(exact: [], prefixes: [])
        }
        var exact = Set<String>()
        if let rows = json["never_exact"] as? [[String: Any]] {
            for row in rows {
                if let name = row["pkg"] as? String { exact.insert(name) }
            }
        }
        var prefixes: [Prefix] = []
        if let rows = json["never_prefix"] as? [[String: Any]] {
            for row in rows {
                guard let text = row["prefix"] as? String else { continue }
                let exceptions = Set((row["exceptions"] as? [String]) ?? [])
                prefixes.append(Prefix(text: text, exceptions: exceptions))
            }
        }
        return NeverTouchGuard(exact: exact, prefixes: prefixes)
    }
}

public enum AppActionKind: Equatable {
    case uninstall
    case forceStop
}

extension NeverTouchGuard {
    public static func bundledData() -> Data? {
        if let url = Bundle.main.url(forResource: "never-touch", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "never-touch", withExtension: "json") {
            return try? Data(contentsOf: url)
        }
        #endif
        return nil
    }
}

public enum AdbAppCommand {
    public static func isPackage(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "_"
        }
    }

    public static func uninstall(_ package: String, guardList: NeverTouchGuard) -> String? {
        guard isPackage(package), !guardList.blocks(package) else { return nil }
        return "pm uninstall --user 0 \(package)"
    }

    public static func forceStop(_ package: String, guardList: NeverTouchGuard) -> String? {
        guard isPackage(package), !guardList.blocks(package) else { return nil }
        return "am force-stop \(package)"
    }

    public static func screencap() -> String {
        "exec:screencap -p"
    }

    public static func install(remotePath: String) -> String? {
        guard remotePath.hasSuffix(".apk"), !remotePath.contains(" ") else { return nil }
        return "shell:pm install -r \(remotePath)"
    }
}
