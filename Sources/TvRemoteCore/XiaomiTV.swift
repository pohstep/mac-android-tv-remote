import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Experimental Xiaomi control over the community HTTP API on port 6095.
/// Written against scripts/mock-xiaomi.py. Not verified on a real TV.
/// Keys, app launch, and HDMI source only. No text. No power-on.
public enum XiaomiKey {
    public static func code(for key: AndroidKey) -> Int? {
        switch key {
        case .wakeup, .power:
            return nil
        case .home: return 3
        case .back: return 4
        case .dpadUp: return 19
        case .dpadDown: return 20
        case .dpadLeft: return 21
        case .dpadRight: return 22
        case .dpadCenter: return 23
        case .volumeUp: return 24
        case .volumeDown: return 25
        case .volumeMute: return 164
        case .mediaPlayPause: return 85
        case .mediaNext: return 87
        case .mediaPrevious: return 88
        case .menu: return 82
        case .sleep: return 223
        case .del: return 67
        case .forwardDel: return 112
        case .hdmi1: return nil
        case .hdmi2: return nil
        case .hdmi3: return nil
        case .hdmi4: return nil
        case .num0: return 7
        case .num1: return 8
        case .num2: return 9
        case .num3: return 10
        case .num4: return 11
        case .num5: return 12
        case .num6: return 13
        case .num7: return 14
        case .num8: return 15
        case .num9: return 16
        }
    }
}

public enum XiaomiCommand {
    public static func alive(host: String, port: Int) -> URL? {
        url(host: host, port: port, path: "/request", items: [URLQueryItem(name: "action", value: "isalive")])
    }

    public static func key(host: String, port: Int, code: Int) -> URL? {
        url(host: host, port: port, path: "/controller", items: [
            URLQueryItem(name: "action", value: "keyevent"),
            URLQueryItem(name: "keycode", value: String(code))
        ])
    }

    public static func launch(host: String, port: Int, package: String) -> URL? {
        url(host: host, port: port, path: "/controller", items: [
            URLQueryItem(name: "action", value: "startapp"),
            URLQueryItem(name: "type", value: "packagename"),
            URLQueryItem(name: "packagename", value: package)
        ])
    }

    public static func source(host: String, port: Int, hdmi: Int) -> URL? {
        guard (1...4).contains(hdmi) else { return nil }
        return url(host: host, port: port, path: "/controller", items: [
            URLQueryItem(name: "action", value: "changesource"),
            URLQueryItem(name: "source", value: "hdmi\(hdmi)")
        ])
    }

    public static func succeeded(status: Int, body: String) -> Bool {
        guard (200...299).contains(status) else { return false }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["status"] as? Int else { return true }
        return code == 0
    }

    private static func url(host: String, port: Int, path: String, items: [URLQueryItem]) -> URL? {
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = host
        parts.port = port
        parts.path = path
        parts.queryItems = items
        return parts.url
    }
}

public protocol HttpReading {
    func get(url: URL, timeout: TimeInterval) throws -> HttpReply
}

public struct UnavailableReader: HttpReading {
    public init() {}
    public func get(url: URL, timeout: TimeInterval) throws -> HttpReply {
        throw RemoteError.commandFailed("No network reader.")
    }
}

extension URLSessionHttp: HttpReading {
    public func get(url: URL, timeout: TimeInterval) throws -> HttpReply {
        try perform(method: "GET", url: url, headers: [:], body: nil, timeout: timeout)
    }
}

public struct XiaomiClient {
    public var reader: any HttpReading
    public var timeout: TimeInterval

    public init(reader: any HttpReading, timeout: TimeInterval = 4) {
        self.reader = reader
        self.timeout = timeout
    }

    /// Device name when the set answers, otherwise nil.
    public func alive(host: String, port: Int) -> String? {
        guard let url = XiaomiCommand.alive(host: host, port: port),
              let reply = try? reader.get(url: url, timeout: timeout) else { return nil }
        let body = String(data: reply.body, encoding: .utf8) ?? ""
        return DiscoveryParse.xiaomi(host: host, status: reply.status, body: body)?.name
    }

    public func sendKey(_ code: Int, host: String, port: Int) -> Bool {
        guard let url = XiaomiCommand.key(host: host, port: port, code: code) else { return false }
        return call(url)
    }

    public func launch(package: String, host: String, port: Int) -> Bool {
        guard PackageName.isValid(package),
              let url = XiaomiCommand.launch(host: host, port: port, package: package) else { return false }
        return call(url)
    }

    public func selectHDMI(_ portNumber: Int, host: String, port: Int) -> Bool {
        guard let url = XiaomiCommand.source(host: host, port: port, hdmi: portNumber) else { return false }
        return call(url)
    }

    private func call(_ url: URL) -> Bool {
        guard let reply = try? reader.get(url: url, timeout: timeout) else { return false }
        let body = String(data: reply.body, encoding: .utf8) ?? ""
        return XiaomiCommand.succeeded(status: reply.status, body: body)
    }
}
