import Foundation

public enum PowerReading: Equatable {
    /// Sony IP said the set is active.
    case on
    /// Sony IP said the set is in standby.
    case off
    /// adb answered, and Sony IP did not give a power reading.
    case reachableOnly
    case unknown
}

public struct TvPicture: Equatable {
    public var power: PowerReading
    public var foregroundPackage: String?
    public var nowPlaying: String?
    public var isPlaying: Bool
    public var volume: Int?
    public var maxVolume: Int
    public var muted: Bool
    public var inputTitle: String?
    public var inputURI: String?
    public var inputs: [BraviaInput]
    public var sonyReady: Bool
    public var adbReady: Bool

    public init(
        power: PowerReading = .unknown,
        foregroundPackage: String? = nil,
        nowPlaying: String? = nil,
        isPlaying: Bool = false,
        volume: Int? = nil,
        maxVolume: Int = 100,
        muted: Bool = false,
        inputTitle: String? = nil,
        inputURI: String? = nil,
        inputs: [BraviaInput] = [],
        sonyReady: Bool = false,
        adbReady: Bool = false
    ) {
        self.power = power
        self.foregroundPackage = foregroundPackage
        self.nowPlaying = nowPlaying
        self.isPlaying = isPlaying
        self.volume = volume
        self.maxVolume = maxVolume
        self.muted = muted
        self.inputTitle = inputTitle
        self.inputURI = inputURI
        self.inputs = inputs
        self.sonyReady = sonyReady
        self.adbReady = adbReady
    }

    public static func shortName(_ package: String?) -> String {
        guard let package, !package.isEmpty else { return "app unknown" }
        if let last = package.split(separator: ".").last, !last.isEmpty {
            return String(last)
        }
        return package
    }

    public func statusLine(appName: String) -> String {
        switch power {
        case .on:
            return "On · \(appName)"
        case .off:
            return "Off"
        case .reachableOnly:
            return "Connected · \(appName)"
        case .unknown:
            return "No answer yet"
        }
    }

    public var detailLine: String {
        [inputTitle, nowPlaying].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public enum RefreshCadence {
    /// Status is polled only while the remote panel is open.
    public static let whileOpen: TimeInterval = 4
}
