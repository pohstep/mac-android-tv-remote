import Foundation

/// Shown on the find step only after the search finishes with nothing.
public enum DemoOffer {
    public static func showWhenNoneFound(searching: Bool, matchCount: Int) -> Bool {
        !searching && matchCount == 0
    }
}

public enum DemoCopy {
    public static let name = "Demo TV"
    public static let mode = "Demo mode"
    public static let leave = "Leave demo"
    public static let tryIt = "Try demo TV"
    public static let noneFound = "No TV found."
    public static let sent = "Sent."
    public static let file = "The file is in Downloads. The TV needs a player to open it."
    public static let install = "Installed."
    public static let shot = "Screenshot."
}

/// Actions a live session and the demo session both answer.
public protocol TvActing: AnyObject {
    func press(_ key: AndroidKey) -> ActionReport
    func type(_ text: String) -> ActionReport
    func launch(_ app: TvApp) -> ActionReport
    func pressPower() -> ActionReport
    func pressSleep() -> ActionReport
    func setVolume(_ level: Int) -> ActionReport
    func selectHdmi(_ port: Int) -> ActionReport
    func selectInput(uri: String) -> ActionReport
    func sendFile(at path: String) -> JobReport
    func installApk(at path: String, clearingCancel: Bool) -> JobReport
    func captureScreenshot() -> ScreenshotResult
    func refresh() -> LinkStatus
}

extension RemoteSession: TvActing {}

/// Same actions as a live session. Holds command, HTTP, and wake probes and never calls them.
public final class DemoSession: TvActing {
    public let commands: any CommandRunning
    public let http: any HttpSending
    public let wake: any WakeOnLanSending

    public init() {
        self.commands = UnusedCommands()
        self.http = UnusedHTTP()
        self.wake = UnusedWake()
    }

    public init(commands: any CommandRunning, http: any HttpSending, wake: any WakeOnLanSending) {
        self.commands = commands
        self.http = http
        self.wake = wake
    }

    public static let connectedPicture = TvPicture(power: .on, inputTitle: DemoCopy.name)

    public func press(_ key: AndroidKey) -> ActionReport {
        _ = key
        return ActionReport(title: DemoCopy.sent, detail: "", isError: false)
    }

    public func type(_ text: String) -> ActionReport {
        _ = text
        return ActionReport(title: DemoCopy.sent, detail: "", isError: false)
    }

    public func launch(_ app: TvApp) -> ActionReport {
        _ = app
        return ActionReport(title: DemoCopy.sent, detail: "", isError: false)
    }

    public func pressPower() -> ActionReport {
        ActionReport(title: DemoCopy.sent, detail: "", isError: false)
    }

    public func pressSleep() -> ActionReport {
        ActionReport(title: DemoCopy.sent, detail: "", isError: false)
    }

    public func setVolume(_ level: Int) -> ActionReport {
        _ = level
        return ActionReport(title: DemoCopy.sent, detail: "", isError: false)
    }

    public func selectHdmi(_ port: Int) -> ActionReport {
        _ = port
        return ActionReport(title: DemoCopy.sent, detail: "", isError: false)
    }

    public func selectInput(uri: String) -> ActionReport {
        _ = uri
        return ActionReport(title: DemoCopy.sent, detail: "", isError: false)
    }

    public func sendFile(at path: String) -> JobReport {
        _ = path
        return JobReport(sentence: DemoCopy.file, raw: "", isError: false)
    }

    public func installApk(at path: String, clearingCancel: Bool = true) -> JobReport {
        _ = path
        _ = clearingCancel
        return JobReport(sentence: DemoCopy.install, raw: "", isError: false)
    }

    public func captureScreenshot() -> ScreenshotResult {
        ScreenshotResult(png: DemoPicture.png(), sentence: DemoCopy.shot, raw: "", isError: false)
    }

    public func refresh() -> LinkStatus {
        .connected(serial: DemoCopy.name)
    }
}

/// A small neutral gray gradient. Built here so the demo ships no outside artwork.
enum DemoPicture {
    static func png(width: Int = 64, height: Int = 36) -> Data {
        let width = max(width, 1)
        let height = max(height, 1)
        var raw: [UInt8] = []
        raw.reserveCapacity(height * (1 + width * 3))
        for y in 0..<height {
            raw.append(0)
            for x in 0..<width {
                let across = x * 140 / max(width - 1, 1)
                let down = y * 24 / max(height - 1, 1)
                let gray = UInt8(min(48 + across + down, 255))
                raw.append(gray)
                raw.append(gray)
                raw.append(gray)
            }
        }
        var ihdr: [UInt8] = []
        ihdr.append(contentsOf: u32(width))
        ihdr.append(contentsOf: u32(height))
        ihdr.append(contentsOf: [8, 2, 0, 0, 0])
        var bytes: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        bytes.append(contentsOf: chunk("IHDR", ihdr))
        bytes.append(contentsOf: chunk("IDAT", zlibStore(raw)))
        bytes.append(contentsOf: chunk("IEND", []))
        return Data(bytes)
    }

    private static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        var body = Array(type.utf8)
        body.append(contentsOf: data)
        var out = u32(data.count)
        out.append(contentsOf: body)
        out.append(contentsOf: u32(Int(crc32(body))))
        return out
    }

    private static func u32(_ value: Int) -> [UInt8] {
        let n = UInt32(value)
        return [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
    }

    private static func crc32(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    private static func zlibStore(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var index = 0
        while index < data.count || data.isEmpty {
            let remaining = data.count - index
            let length = min(remaining, 65535)
            let final = index + length >= data.count
            out.append(final ? 1 : 0)
            out.append(UInt8(length & 0xFF))
            out.append(UInt8((length >> 8) & 0xFF))
            let complement = UInt16(length) ^ 0xFFFF
            out.append(UInt8(complement & 0xFF))
            out.append(UInt8((complement >> 8) & 0xFF))
            if length > 0 {
                out.append(contentsOf: data[index..<(index + length)])
            }
            index += length
            if final { break }
        }
        let sum = adler32(data)
        out.append(UInt8((sum >> 24) & 0xFF))
        out.append(UInt8((sum >> 16) & 0xFF))
        out.append(UInt8((sum >> 8) & 0xFF))
        out.append(UInt8(sum & 0xFF))
        return out
    }
}

private struct UnusedCommands: CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        throw RemoteError.commandFailed("Demo mode does not run commands.")
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval, environment: [String: String]) throws -> CommandResult {
        _ = environment
        throw RemoteError.commandFailed("Demo mode does not run commands.")
    }
}

private struct UnusedHTTP: HttpSending {
    func send(url: URL, headers: [String: String], body: Data, timeout: TimeInterval) throws -> HttpReply {
        _ = url
        _ = headers
        _ = body
        _ = timeout
        throw RemoteError.commandFailed("Demo mode does not use the network.")
    }
}

private struct UnusedWake: WakeOnLanSending {
    func send(mac: String, broadcastHost: String, port: UInt16) throws {
        _ = mac
        _ = broadcastHost
        _ = port
        throw RemoteError.commandFailed("Demo mode does not use the network.")
    }
}
