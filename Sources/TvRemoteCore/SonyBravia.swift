import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sony BRAVIA IP control. Codes are the public IRCC values from
/// `getRemoteControllerInfo`. The pre-shared key travels only in the
/// `X-Auth-PSK` header and is never written into a URL, a SOAP body, or an error string.
public enum SonyButton: Equatable {
    case up, down, left, right, confirm, back, home
    case volumeUp, volumeDown, mute
    case play, pause, next, previous
    case hdmi(Int)
    case digit(Int)

    public static func forKey(_ key: AndroidKey, isPlaying: Bool) -> SonyButton? {
        switch key {
        case .dpadUp: return .up
        case .dpadDown: return .down
        case .dpadLeft: return .left
        case .dpadRight: return .right
        case .dpadCenter: return .confirm
        case .back: return .back
        case .del, .forwardDel: return nil
        case .home: return .home
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .volumeMute: return .mute
        case .mediaPlayPause: return isPlaying ? .pause : .play
        case .mediaNext: return .next
        case .mediaPrevious: return .previous
        case .hdmi1: return .hdmi(1)
        case .hdmi2: return .hdmi(2)
        case .hdmi3: return .hdmi(3)
        case .hdmi4: return .hdmi(4)
        case .num0: return .digit(0)
        case .num1: return .digit(1)
        case .num2: return .digit(2)
        case .num3: return .digit(3)
        case .num4: return .digit(4)
        case .num5: return .digit(5)
        case .num6: return .digit(6)
        case .num7: return .digit(7)
        case .num8: return .digit(8)
        case .num9: return .digit(9)
        case .wakeup, .sleep, .power, .menu:
            return nil
        }
    }
}

public enum IrccCode {
    /// Public codes published with Sony's `getRemoteControllerInfo` sample.
    public static func value(_ button: SonyButton) -> String? {
        switch button {
        case .up: return "AAAAAQAAAAEAAAB0Aw=="
        case .down: return "AAAAAQAAAAEAAAB1Aw=="
        case .left: return "AAAAAQAAAAEAAAA0Aw=="
        case .right: return "AAAAAQAAAAEAAAAzAw=="
        case .confirm: return "AAAAAQAAAAEAAABlAw=="
        case .back: return "AAAAAgAAAJcAAAAjAw=="
        case .home: return "AAAAAQAAAAEAAABgAw=="
        case .volumeUp: return "AAAAAQAAAAEAAAASAw=="
        case .volumeDown: return "AAAAAQAAAAEAAAATAw=="
        case .mute: return "AAAAAQAAAAEAAAAUAw=="
        case .play: return "AAAAAgAAAJcAAAAaAw=="
        case .pause: return "AAAAAgAAAJcAAAAZAw=="
        case .next: return "AAAAAgAAAJcAAAA9Aw=="
        case .previous: return "AAAAAgAAAJcAAAA8Aw=="
        case .hdmi(1): return "AAAAAgAAABoAAABaAw=="
        case .hdmi(2): return "AAAAAgAAABoAAABbAw=="
        case .hdmi(3): return "AAAAAgAAABoAAABcAw=="
        case .hdmi(4): return "AAAAAgAAABoAAABdAw=="
        case .digit(0): return "AAAAAQAAAAEAAAAJAw=="
        case .digit(1): return "AAAAAQAAAAEAAAAAAw=="
        case .digit(2): return "AAAAAQAAAAEAAAABAw=="
        case .digit(3): return "AAAAAQAAAAEAAAACAw=="
        case .digit(4): return "AAAAAQAAAAEAAAADAw=="
        case .digit(5): return "AAAAAQAAAAEAAAAEAw=="
        case .digit(6): return "AAAAAQAAAAEAAAAFAw=="
        case .digit(7): return "AAAAAQAAAAEAAAAGAw=="
        case .digit(8): return "AAAAAQAAAAEAAAAHAw=="
        case .digit(9): return "AAAAAQAAAAEAAAAIAw=="
        case .hdmi, .digit:
            return nil
        }
    }
}

public enum IrccSoap {
    public static let action = "\"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC\""

    public static func body(code: String) -> Data {
        let xml = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:X_SendIRCC xmlns:u="urn:schemas-sony-com:service:IRCC:1">
              <IRCCCode>\(code)</IRCCCode>
            </u:X_SendIRCC>
          </s:Body>
        </s:Envelope>
        """
        return Data(xml.utf8)
    }
}

public struct VolumeReading: Equatable {
    public var volume: Int
    public var maxVolume: Int
    public var muted: Bool
}

public struct BraviaInput: Equatable {
    public var uri: String
    public var title: String
    public var label: String
    public var connected: Bool

    public var displayName: String {
        if !label.isEmpty { return label }
        return title
    }

    /// "HDMI 1 · Apple TV" when the TV has both a port name and a label.
    public var menuTitle: String {
        let port = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !port.isEmpty, !name.isEmpty, port.caseInsensitiveCompare(name) != .orderedSame {
            return "\(port) · \(name)"
        }
        if !name.isEmpty { return name }
        return port
    }
}

public struct HttpReply: Equatable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HttpSending {
    func send(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) throws -> HttpReply
}

public struct URLSessionHttp: HttpSending {
    public init() {}

    public func send(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) throws -> HttpReply {
        try perform(method: "POST", url: url, headers: headers, body: body, timeout: timeout)
    }

    func perform(method: String, url: URL, headers: [String: String], body: Data?, timeout: TimeInterval) throws -> HttpReply {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        if let body, !body.isEmpty {
            request.httpBody = body
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let session = URLSession(configuration: .ephemeral)
        let box = ReplyBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                box.error = error
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                box.reply = HttpReply(status: code, body: data ?? Data())
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + timeout + 1) == .timedOut {
            task.cancel()
            session.invalidateAndCancel()
            throw RemoteError.timedOut(url.host ?? "tv")
        }
        session.finishTasksAndInvalidate()
        if box.reply == nil, box.error != nil {
            throw RemoteError.commandFailed("The TV didn't answer.")
        }
        return box.reply ?? HttpReply(status: 0, body: Data())
    }
}

private final class ReplyBox {
    var reply: HttpReply?
    var error: Error?
}

public enum SecretRedaction {
    public static func scrub(_ text: String, secret: String) -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        return text.replacingOccurrences(of: trimmed, with: "redacted")
    }
}

public enum SonyWire {
    /// Safe to log. The pre-shared key is replaced even if it was copied into a body by mistake.
    public static func redacted(headers: [String: String], body: String, secret: String) -> String {
        var safe = headers
        if safe["X-Auth-PSK"] != nil {
            safe["X-Auth-PSK"] = "redacted"
        }
        let rendered = safe.keys.sorted().map { "\($0)=\(safe[$0] ?? "")" }.joined(separator: " ") + " " + body
        return SecretRedaction.scrub(rendered, secret: secret)
    }
}

enum SonyURL {
    static func make(host: String, port: Int, path: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = host
        parts.port = port
        parts.path = path
        return parts.url
    }
}

public struct SonyClient {
    public var http: any HttpSending
    public var timeout: TimeInterval

    public init(http: any HttpSending, timeout: TimeInterval = 4) {
        self.http = http
        self.timeout = timeout
    }

    public func powerStatus(host: String, port: Int, psk: String) -> PowerReading? {
        guard let data = call(host: host, port: port, path: "/sony/system", psk: psk, method: "getPowerStatus", params: [], version: "1.0") else {
            return nil
        }
        return SonyParse.power(data)
    }

    /// True when network control answers. A refusal still means the switch on the TV is on.
    public func serviceIsUp(host: String, port: Int) -> Bool {
        guard let url = SonyURL.make(host: host, port: port, path: "/sony/system"),
              let body = try? JSONSerialization.data(withJSONObject: [
                "method": "getPowerStatus",
                "params": [],
                "id": 1,
                "version": "1.0"
              ]) else { return false }
        guard let reply = try? http.send(
            url: url,
            headers: ["Content-Type": "application/json"],
            body: body,
            timeout: timeout
        ) else { return false }
        return SonySwitchProbe.serviceIsUp(status: reply.status)
    }

    /// Setup test. Reads power status only. Does not change a setting on the TV.
    public func checkConnection(host: String, port: Int, psk: String) -> SonyConnectCheck.Verdict {
        guard let url = SonyURL.make(host: host, port: port, path: "/sony/system"),
              let body = try? JSONSerialization.data(withJSONObject: [
                "method": "getPowerStatus",
                "params": [],
                "id": 1,
                "version": "1.0"
              ]) else { return .unanswered }
        let headers = [
            "Content-Type": "application/json",
            "X-Auth-PSK": psk
        ]
        guard let reply = try? http.send(url: url, headers: headers, body: body, timeout: timeout) else {
            return .unanswered
        }
        let text = String(data: reply.body, encoding: .utf8) ?? ""
        return SonyConnectCheck.verdict(status: reply.status, body: text)
    }

    public func setPower(on: Bool, host: String, port: Int, psk: String) -> Bool {
        // The TV answers HTTP 200 with {"error":[7,"Illegal State"]} when it can't wake (Remote Start off).
        guard let data = call(host: host, port: port, path: "/sony/system", psk: psk, method: "setPowerStatus", params: [["status": on]], version: "1.0"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["error"] == nil
    }

    public func volume(host: String, port: Int, psk: String) -> VolumeReading? {
        guard let data = call(host: host, port: port, path: "/sony/audio", psk: psk, method: "getVolumeInformation", params: [], version: "1.0") else {
            return nil
        }
        return SonyParse.volume(data)
    }

    public func setVolume(_ level: Int, host: String, port: Int, psk: String) -> Bool {
        let params: [[String: String]] = [["target": "speaker", "volume": String(level)]]
        return call(host: host, port: port, path: "/sony/audio", psk: psk, method: "setAudioVolume", params: params, version: "1.0") != nil
    }

    public func inputs(host: String, port: Int, psk: String) -> [BraviaInput] {
        guard let data = call(host: host, port: port, path: "/sony/avContent", psk: psk, method: "getCurrentExternalInputsStatus", params: [], version: "1.0") else {
            return []
        }
        return SonyParse.inputs(data)
    }

    public func play(uri: String, host: String, port: Int, psk: String) -> Bool {
        call(host: host, port: port, path: "/sony/avContent", psk: psk, method: "setPlayContent", params: [["uri": uri]], version: "1.0") != nil
    }

    public func applications(host: String, port: Int, psk: String) -> [TvApp] {
        guard let data = call(host: host, port: port, path: "/sony/appControl", psk: psk, method: "getApplicationList", params: [], version: "1.0") else {
            return []
        }
        return AppIndex.parseSony(data)
    }

    public func setActiveApp(uri: String, host: String, port: Int, psk: String) -> Bool {
        guard let data = call(host: host, port: port, path: "/sony/appControl", psk: psk, method: "setActiveApp", params: [["uri": uri, "data": ""]], version: "1.0"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["error"] == nil
    }

    /// Sony setTextForm: replaces the text in the focused TV text field. Fails when no field is open.
    public func setTextForm(_ text: String, host: String, port: Int, psk: String) -> Bool {
        guard let data = call(host: host, port: port, path: "/sony/appControl", psk: psk, method: "setTextForm", params: [text], version: "1.0"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["error"] == nil
    }

    public func playingTitle(host: String, port: Int, psk: String) -> String? {
        guard let data = call(host: host, port: port, path: "/sony/avContent", psk: psk, method: "getPlayingContentInfo", params: [], version: "1.0") else {
            return nil
        }
        return SonyParse.playingTitle(data)
    }

    public func sendIRCC(_ button: SonyButton, host: String, port: Int, psk: String) -> Bool {
        guard let code = IrccCode.value(button),
              let url = SonyURL.make(host: host, port: port, path: "/sony/ircc") else { return false }
        let headers = [
            "Content-Type": "text/xml; charset=UTF-8",
            "SOAPACTION": IrccSoap.action,
            "X-Auth-PSK": psk
        ]
        return post(url: url, headers: headers, body: IrccSoap.body(code: code)) != nil
    }

    private func call(host: String, port: Int, path: String, psk: String, method: String, params: Any, version: String) -> Data? {
        guard let url = SonyURL.make(host: host, port: port, path: path),
              let body = try? JSONSerialization.data(withJSONObject: [
                "method": method,
                "params": params,
                "id": 1,
                "version": version
              ]) else { return nil }
        let headers = [
            "Content-Type": "application/json",
            "X-Auth-PSK": psk
        ]
        return post(url: url, headers: headers, body: body)?.body
    }

    private func post(url: URL, headers: [String: String], body: Data) -> HttpReply? {
        guard let reply = try? http.send(url: url, headers: headers, body: body, timeout: timeout) else {
            return nil
        }
        if !(200...299).contains(reply.status) { return nil }
        if SonyParse.failed(reply.body) { return nil }
        return reply
    }
}

public enum SonySwitchProbe {
    /// 200 means the set answered. 403 means control is on and still wants the key.
    public static func serviceIsUp(status: Int) -> Bool {
        if status == 403 { return true }
        return (200...299).contains(status)
    }
}

public enum SonyConnectCheck {
    public enum Verdict: Equatable {
        case connected(PowerReading)
        case rejected
        case unanswered
    }

    public static func verdict(status: Int, body: String) -> Verdict {
        if status == 403 { return .rejected }
        guard let data = body.data(using: .utf8) else { return .unanswered }
        if (200...299).contains(status), let power = SonyParse.power(data) {
            return .connected(power)
        }
        if let code = errorCode(data), code == 403 { return .rejected }
        return .unanswered
    }

    private static func errorCode(_ data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [Any],
              let first = error.first else { return nil }
        if let code = first as? Int { return code }
        if let code = first as? NSNumber { return code.intValue }
        return nil
    }
}

public enum SonyParse {
    public static func failed(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["error"] != nil
    }

    public static func power(_ data: Data) -> PowerReading? {
        for dict in dictionaries(in: data) {
            guard let status = dict["status"] as? String else { continue }
            switch status.lowercased() {
            case "active": return .on
            case "standby": return .off
            default: continue
            }
        }
        return nil
    }

    public static func volume(_ data: Data) -> VolumeReading? {
        let rows = dictionaries(in: data).filter { $0["volume"] != nil }
        let speaker = rows.first { ($0["target"] as? String) == "speaker" } ?? rows.first
        guard let speaker, let level = integer(speaker["volume"]) else { return nil }
        let maxLevel = integer(speaker["maxVolume"]) ?? 100
        let muted = speaker["mute"] as? Bool ?? false
        return VolumeReading(volume: level, maxVolume: max(maxLevel, 1), muted: muted)
    }

    public static func inputs(_ data: Data) -> [BraviaInput] {
        dictionaries(in: data).compactMap { dict in
            guard let uri = dict["uri"] as? String, uri.contains("extInput") else { return nil }
            return BraviaInput(
                uri: uri,
                title: dict["title"] as? String ?? "",
                label: dict["label"] as? String ?? "",
                connected: dict["connection"] as? Bool ?? false
            )
        }
    }

    public static func playingTitle(_ data: Data) -> String? {
        for dict in dictionaries(in: data) {
            if let title = dict["title"] as? String, !title.isEmpty { return title }
        }
        return nil
    }

    public static func hdmiURI(port: Int) -> String {
        "extInput:hdmi?port=\(port)"
    }

    private static func dictionaries(in data: Data) -> [[String: Any]] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return dictionaries(in: object)
    }

    private static func dictionaries(in value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            return [dict] + dict.values.flatMap { dictionaries(in: $0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { dictionaries(in: $0) }
        }
        return []
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? Double { return Int(number) }
        if let text = value as? String { return Int(text) }
        return nil
    }
}
