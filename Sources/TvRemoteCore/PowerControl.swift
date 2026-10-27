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
    case wakeOnLan
    case adbSleep
    case sonyOff
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
    public static let verifyWindow: TimeInterval = 6

    public static func turnOn(
        transport: any PowerTransport,
        sleep: (TimeInterval) -> Void,
        now: () -> Date
    ) -> PowerAttempt {
        var steps: [PowerStep] = []
        if transport.adbCanPressPower { steps.append(.adbWake) }
        if transport.sonyCanPressPower { steps.append(.sonyOn) }
        if transport.canWakeOnLan { steps.append(.wakeOnLan) }
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
        guard let first = steps.first else {
            let detail = want == .on
                ? "Wake needs a debugging connection, Sony IP, or a MAC address for Wake-on-LAN."
                : "Sleep needs a live adb connection. Wake-on-LAN can only turn the TV on."
            return PowerAttempt(
                report: ActionReport(title: "The TV isn't reachable", detail: detail, isError: true),
                power: transport.readPower(),
                tried: [],
                buttonEnabled: true
            )
        }
        var tried: [PowerStep] = [first]
        _ = transport.run(first)
        var power = confirm(want: want, transport: transport, sleep: sleep, now: now)
        if power == want {
            return PowerAttempt(
                report: ActionReport(title: want == .on ? "TV is on" : "TV is off", detail: label(first), isError: false),
                power: power,
                tried: tried,
                buttonEnabled: true
            )
        }
        if steps.count > 1 {
            let next = steps[1]
            tried.append(next)
            _ = transport.run(next)
            power = confirm(want: want, transport: transport, sleep: sleep, now: now)
            if power == want {
                return PowerAttempt(
                    report: ActionReport(title: want == .on ? "TV is on" : "TV is off", detail: label(next), isError: false),
                    power: power,
                    tried: tried,
                    buttonEnabled: true
                )
            }
        }
        return PowerAttempt(
            report: ActionReport(title: didNotRespond, detail: "", isError: true),
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
        for _ in 0..<8 {
            let reading = transport.readPower()
            if reading == want { return reading }
            let clock = now()
            if clock >= deadline { return reading }
            let slice = min(1, deadline.timeIntervalSince(clock))
            if slice <= 0 { return transport.readPower() }
            sleep(slice)
        }
        return transport.readPower()
    }

    private static func label(_ step: PowerStep) -> String {
        switch step {
        case .adbWake:
            return "adb wake"
        case .sonyOn:
            return "Sony IP"
        case .wakeOnLan:
            return "Wake-on-LAN"
        case .adbSleep:
            return "adb sleep"
        case .sonyOff:
            return "Sony IP"
        }
    }
}
