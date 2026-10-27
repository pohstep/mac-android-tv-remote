import Foundation

public enum Wakefulness {
    /// Awake is on. Asleep and Dozing are off. A missing line is not a power reading.
    public static func reading(_ text: String) -> PowerReading? {
        guard let match = text.range(
            of: #"mWakefulness\s*=\s*(Awake|Asleep|Dozing)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let token = text[match].split(separator: "=").last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch token {
        case "awake":
            return .on
        case "asleep", "dozing":
            return .off
        default:
            return nil
        }
    }
}

public enum PowerMerge {
    /// adb's wake line wins when it parses. Sony is next. Neither answer is unknown, never on.
    public static func choose(adbDump: String?, sony: PowerReading?) -> PowerReading {
        if let adbDump, let parsed = Wakefulness.reading(adbDump) {
            return parsed
        }
        if let sony {
            switch sony {
            case .on, .off:
                return sony
            case .reachableOnly, .unknown:
                return .unknown
            }
        }
        return .unknown
    }
}

public enum MacSources {
    public static func addressFile(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return MACAddress.display(line)
    }

    /// ARP or `ip neigh` line that names this host, or an SSDP/UPnP body that does.
    public static func neighbour(_ text: String, host: String) -> String? {
        let wanted = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard line.contains(wanted), let mac = firstMac(in: line) else { continue }
            return mac
        }
        return nil
    }

    /// Subnet broadcast for an IPv4 host when Settings still has the wide default.
    public static func subnetBroadcast(host: String, configured: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "255.255.255.255" {
            return trimmed
        }
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else {
            return "255.255.255.255"
        }
        return "\(parts[0]).\(parts[1]).\(parts[2]).255"
    }

    private static func firstMac(in line: String) -> String? {
        guard let match = line.range(
            of: #"[0-9a-fA-F]{2}([:\-])[0-9a-fA-F]{2}(?:\1[0-9a-fA-F]{2}){4}"#,
            options: .regularExpression
        ) else { return nil }
        return MACAddress.display(String(line[match]))
    }
}

public enum PowerStep: Equatable {
    case adbWake
    case sonyOn
    case wakeOnLan(port: UInt16)
    case adbSleep
    case sonyOff
}

public enum PowerPress: Equatable {
    case turnOn
    case turnOff
}

/// The one power control. The panel, the menu, and Settings all use this label.
public struct PowerButtonModel: Equatable {
    public var label: String
    public var enabled: Bool
    public var action: PowerPress

    public static let checkingLabel = "Checking…"
    public static let turnOnLabel = "Turn on"
    public static let turnOffLabel = "Turn off"
    public static let unsupportedLabel = "Power isn't supported on this TV."
    public static let turningOn = "Turning on…"
    public static let turningOff = "Turning off…"

    /// Every sentence this control shows. Method names stay out of these lines.
    public static let userFacingLines = [
        checkingLabel,
        turnOnLabel,
        turnOffLabel,
        unsupportedLabel,
        turningOn,
        turningOff,
        PowerActions.didNotRespond
    ]

    public init(label: String, enabled: Bool, action: PowerPress) {
        self.label = label
        self.enabled = enabled
        self.action = action
    }

    public var actions: [PowerPress] { [action] }

    /// Unknown uses Turn on, the one label that cannot switch a live TV off. Checking… is only while a reading is still in flight.
    public static func make(power: PowerReading, busy: Bool, supported: Bool, checking: Bool = false) -> PowerButtonModel {
        if !supported {
            return PowerButtonModel(label: unsupportedLabel, enabled: false, action: .turnOn)
        }
        if checking && power != .on && power != .off {
            return PowerButtonModel(label: checkingLabel, enabled: false, action: .turnOn)
        }
        switch power {
        case .on:
            return PowerButtonModel(label: turnOffLabel, enabled: !busy, action: .turnOff)
        case .off, .unknown, .reachableOnly:
            return PowerButtonModel(label: turnOnLabel, enabled: !busy, action: .turnOn)
        }
    }
}

public struct PowerAttempt: Equatable {
    public var report: ActionReport
    public var power: PowerReading
    public var tried: [PowerStep]
    /// The button is usable again when the attempt has finished.
    public var buttonEnabled: Bool

    public init(report: ActionReport, power: PowerReading, tried: [PowerStep], buttonEnabled: Bool) {
        self.report = report
        self.power = power
        self.tried = tried
        self.buttonEnabled = buttonEnabled
    }
}

public protocol PowerTransport {
    var adbCanPressPower: Bool { get }
    var sonyCanPressPower: Bool { get }
    var canWakeOnLan: Bool { get }
    func readPower() -> PowerReading
    func run(_ step: PowerStep) -> Bool
}

public enum PowerChrome {
    /// Only a real on reading shows Turn off. Asleep, unknown, and a bare connection do not.
    public static func showsOn(_ power: PowerReading) -> Bool {
        power == .on
    }
}

public enum PowerActions {
    public static let didNotRespond = "TV didn't respond — try again"
    public static let couldNotTurnOn = "Couldn't reach the TV to turn it on. Check it's plugged in and on the same Wi-Fi, then try again."
    public static let couldNotTurnOff = "The TV can't be turned off right now. Check that the TV is connected, then try again."
    /// Failure sentences a person can see. Method names stay in the log.
    public static let userFacingFailures = [didNotRespond, couldNotTurnOn, couldNotTurnOff]
    public static let verifyWindow: TimeInterval = 6

    public static func turnOn(
        transport: any PowerTransport,
        sleep: (TimeInterval) -> Void,
        now: () -> Date
    ) -> PowerAttempt {
        var steps: [PowerStep] = []
        if transport.adbCanPressPower { steps.append(.adbWake) }
        if transport.sonyCanPressPower { steps.append(.sonyOn) }
        if transport.canWakeOnLan {
            steps.append(.wakeOnLan(port: 9))
            steps.append(.wakeOnLan(port: 7))
        }
        return attempt(steps: steps, want: .on, transport: transport, sleep: sleep, now: now)
    }

    public static func turnOff(
        transport: any PowerTransport,
        sleep: (TimeInterval) -> Void,
        now: () -> Date
    ) -> PowerAttempt {
        var steps: [PowerStep] = []
        if transport.adbCanPressPower { steps.append(.adbSleep) }
        if transport.sonyCanPressPower { steps.append(.sonyOff) }
        return attempt(steps: steps, want: .off, transport: transport, sleep: sleep, now: now)
    }

    private static func attempt(
        steps: [PowerStep],
        want: PowerReading,
        transport: any PowerTransport,
        sleep: (TimeInterval) -> Void,
        now: () -> Date
    ) -> PowerAttempt {
        guard !steps.isEmpty else {
            log(want == .on
                ? "no debugging connection, no Sony IP, and no MAC address for Wake-on-LAN"
                : "no live adb connection; Wake-on-LAN can only turn the TV on")
            return PowerAttempt(
                report: ActionReport(title: want == .on ? couldNotTurnOn : couldNotTurnOff, detail: "", isError: true),
                power: transport.readPower(),
                tried: [],
                buttonEnabled: true
            )
        }
        var tried: [PowerStep] = []
        var power: PowerReading = .unknown
        for step in steps {
            tried.append(step)
            _ = transport.run(step)
            power = confirm(want: want, transport: transport, sleep: sleep, now: now)
            if let done = finished(want: want, power: power, step: step, tried: tried) {
                return done
            }
        }
        log(tried.map(logLabel).joined(separator: ", "))
        return PowerAttempt(
            report: ActionReport(title: didNotRespond, detail: "", isError: true),
            power: power,
            tried: tried,
            buttonEnabled: true
        )
    }

    private static func finished(
        want: PowerReading,
        power: PowerReading,
        step: PowerStep,
        tried: [PowerStep]
    ) -> PowerAttempt? {
        let title: String
        switch (want, power) {
        case (.on, .on):
            title = "Turned on."
        case (.off, .off):
            title = "Turned off."
        case (.off, .unknown):
            title = "Turned off. The TV stopped answering."
        default:
            return nil
        }
        log(logLabel(step))
        return PowerAttempt(
            report: ActionReport(title: title, detail: "", isError: false),
            power: power,
            tried: tried,
            buttonEnabled: true
        )
    }

    private static func confirm(
        want: PowerReading,
        transport: any PowerTransport,
        sleep: (TimeInterval) -> Void,
        now: () -> Date
    ) -> PowerReading {
        let deadline = now().addingTimeInterval(verifyWindow)
        var unknownStreak = 0
        for _ in 0..<8 {
            let reading = transport.readPower()
            if reading == want { return reading }
            if want == .off && reading == .unknown {
                unknownStreak += 1
                if unknownStreak >= 2 { return .unknown }
                let clock = now()
                if clock >= deadline { return .reachableOnly }
                let pause = min(0.4, deadline.timeIntervalSince(clock))
                if pause <= 0 { return .reachableOnly }
                sleep(pause)
                continue
            }
            unknownStreak = 0
            let clock = now()
            if clock >= deadline { return reading }
            let slice = min(1, deadline.timeIntervalSince(clock))
            if slice <= 0 { return transport.readPower() }
            sleep(slice)
        }
        let last = transport.readPower()
        if want == .off && last == .unknown {
            return unknownStreak >= 1 ? .unknown : .reachableOnly
        }
        return last
    }

    /// Method names for the log. These lines are not shown on the button or the banner.
    private static func logLabel(_ step: PowerStep) -> String {
        switch step {
        case .adbWake:
            return "adb wake"
        case .sonyOn:
            return "Sony IP"
        case .wakeOnLan(let port):
            return "Wake-on-LAN port \(port)"
        case .adbSleep:
            return "adb sleep"
        case .sonyOff:
            return "Sony IP"
        }
    }

    private static func log(_ message: String) {
        NSLog("%@", message)
    }
}
