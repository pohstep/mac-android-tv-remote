import Foundation

public enum WizardPhase: Equatable {
    case pickBrand
    case find
    case manual
    case sonyTyping
    case debugging
    case pair
    case allow
    case sonyKey
    case xiaomiCheck
    case remember
    case done
}

public struct SetupLine: Equatable {
    public var key: String
    public var text: String

    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

public enum WizardEvent: Equatable {
    case choose(TvBrand)
    case pick(DiscoveredTV)
    case wantManual
    case submitManual(host: String, port: Int?)
    case typing(Bool)
    case chooseWireless
    case chooseLegacy
    case submitPair(port: String, code: String)
    case pairSucceeded
    case pairFailed(String)
    case allowAccepted
    case allowWaiting
    case connectFailed(String)
    case testKey(String)
    case testSucceeded
    case testFailed(String)
    case continueAhead
    case watch(answered: Bool, elapsed: TimeInterval, legacyPort: Int?)
    case watchRetry
    case remember(name: String)
    case back
}

public enum TvSwitch: Equatable {
    case sonyNetwork
    case networkDebugging
}

public enum SwitchPhase: Equatable {
    case waiting
    case detected
    case timedOut
}

/// The TV setting that Zapbar cannot flip. Wait, notice when it answers, or time out.
public struct SwitchWatch: Equatable {
    public static let limit: TimeInterval = 45
    public var kind: TvSwitch
    public private(set) var phase: SwitchPhase

    public init(kind: TvSwitch) {
        self.kind = kind
        self.phase = .waiting
    }

    public mutating func note(answered: Bool, elapsed: TimeInterval) {
        if phase == .detected { return }
        if answered {
            phase = .detected
            return
        }
        if elapsed >= SwitchWatch.limit {
            phase = .timedOut
        }
    }

    public var instruction: String {
        switch kind {
        case .sonyNetwork:
            return "On the TV, open Settings, then Network. Turn on control from the network, and set a control key."
        case .networkDebugging:
            return "On the TV, open Settings, then System, then Developer options. Turn on Network debugging."
        }
    }

    public var timeoutMessage: String {
        switch kind {
        case .sonyNetwork:
            return "The TV didn't answer. On the TV, open Settings, then Network, and turn on control from the network. Then try again."
        case .networkDebugging:
            return "The TV didn't answer. On the TV, open Settings, then System, then Developer options, and turn on Network debugging. Then try again."
        }
    }
}

public enum WizardCopy {
    public static let enterKey = "Enter the control key from the TV."
    public static let keyRefused = "That key was refused. Check the control key on the TV."
    public static let networkOn = "Control from the network is on. Enter the control key."
    public static let xiaomiUnanswered = "This TV didn't answer. You can save it and try again later."
    public static let enterNumberAndCode = "Enter the number and the 6-digit code shown on the TV."

    public static func connected(to name: String) -> String {
        "Connected to \(name)."
    }

    public static func saved(to name: String) -> String {
        "Saved \(name)."
    }

    public static var sentences: [String] {
        [
            enterKey,
            keyRefused,
            networkOn,
            xiaomiUnanswered,
            enterNumberAndCode,
            connected(to: "Living Room"),
            saved(to: "Living Room")
        ]
    }
}

public enum PlainWords {
    /// The first forbidden word in a setup sentence, if any. Settings field labels are not passed here.
    public static func hit(in text: String) -> String? {
        let lowered = text.lowercased()
        if lowered.contains("adb") { return "adb" }
        if lowered.contains("ip control") { return "IP control" }
        if lowered.contains("pre-shared key") || lowered.contains("preshared") { return "pre-shared key" }
        if text.range(of: "\\bport\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            return "port"
        }
        return nil
    }
}

public enum WizardEffect: Equatable {
    case none
    case pairAndConnect(host: String, pairPort: Int, code: String, connectPort: Int)
    case connectLegacy(host: String, port: Int)
    case testSony(host: String, port: Int, psk: String)
    case testXiaomi(host: String, port: Int)
    case save(StoredTV)
}

public enum SetupCopy {
    public static func lines(phase: WizardPhase, brand: TvBrand?, wantsTyping: Bool, debugChoices: Bool = false) -> [SetupLine] {
        _ = wantsTyping
        switch phase {
        case .debugging:
            var lines = [
                SetupLine(key: "setup.debug.wireless.1", text: SwitchWatch(kind: .networkDebugging).instruction)
            ]
            if debugChoices {
                lines.append(contentsOf: [
                    SetupLine(key: "setup.debug.wireless.2", text: "When the TV shows a number and a code, enter both."),
                    SetupLine(key: "setup.debug.wireless.3", text: "Choose pair with a code. You will need the number and the code shown on the TV."),
                    SetupLine(key: "setup.debug.legacy.1", text: "Older sets connect without a pairing code."),
                    SetupLine(key: "setup.debug.legacy.2", text: "When this Mac connects, accept Allow on the TV.")
                ])
            }
            return lines
        case .sonyKey:
            return [
                SetupLine(key: "setup.sony.ip.1", text: SwitchWatch(kind: .sonyNetwork).instruction),
                SetupLine(key: "setup.sony.ip.2", text: "Enter that key here. It stays in the Keychain. Zapbar continues when the TV answers.")
            ]
        case .xiaomiCheck:
            return [
                SetupLine(key: "setup.xiaomi.check.1", text: "This TV can use the remote buttons. Typing and turning it on from here aren't available.")
            ]
        case .find:
            return [
                SetupLine(key: "setup.find.1", text: "Pick a TV on this network, or enter an address.")
            ]
        case .remember where brand == .xiaomi:
            return [
                SetupLine(key: "setup.xiaomi.1", text: "This TV can use the remote buttons. Typing and turning it on from here aren't available.")
            ]
        case .pair:
            return [
                SetupLine(key: "setup.pair.1", text: WizardCopy.enterNumberAndCode)
            ]
        case .allow:
            return [
                SetupLine(key: "setup.allow.1", text: "Accept the Allow prompt on the TV. This Mac then connects.")
            ]
        case .sonyTyping:
            return [
                SetupLine(key: "setup.sony.choice.1", text: "The control key runs the remote. Allow this Mac on the TV only if you want to type.")
            ]
        case .pickBrand, .manual, .remember, .done:
            return []
        }
    }
}

public struct SetupWizard: Equatable {
    public private(set) var phase: WizardPhase
    public private(set) var brand: TvBrand?
    public private(set) var host: String
    public private(set) var port: Int
    public private(set) var controlPort: Int
    public private(set) var macAddress: String
    public private(set) var pairingPortHint: Int?
    public private(set) var legacyAdbPort: Int?
    /// False when this copy of Zapbar has no helper that can type. Defaults to true so a test can opt out.
    public private(set) var adbReady: Bool
    public private(set) var wantsTyping: Bool
    public private(set) var message: String?
    public private(set) var switchWatch: SwitchWatch?
    public private(set) var name: String
    /// True only after the TV answered a connection check.
    public private(set) var verified: Bool
    private var stack: [WizardPhase]

    public init() {
        phase = .pickBrand
        brand = nil
        host = ""
        port = 5555
        controlPort = 80
        macAddress = ""
        pairingPortHint = nil
        legacyAdbPort = nil
        adbReady = true
        wantsTyping = false
        message = nil
        switchWatch = nil
        name = ""
        verified = false
        stack = []
    }

    public mutating func setAdbReady(_ ready: Bool) {
        adbReady = ready
    }

    /// Choice buttons stay off while the debugging step is still waiting.
    public var showsDebugChoices: Bool {
        phase == .debugging && switchWatch?.phase == .timedOut
    }

    public func lines() -> [SetupLine] {
        SetupCopy.lines(phase: phase, brand: brand, wantsTyping: wantsTyping, debugChoices: showsDebugChoices)
    }

    public func draft(id: String = UUID().uuidString) -> StoredTV {
        let debugging: Bool
        switch brand {
        case .generic: debugging = true
        case .sony: debugging = wantsTyping
        case .xiaomi, .none: debugging = false
        }
        return StoredTV(
            id: id,
            name: name.isEmpty ? host : name,
            brand: brand ?? .generic,
            host: host,
            port: port,
            macAddress: macAddress,
            preferred: false,
            controlPort: controlPort,
            useDebugging: debugging
        )
    }

    public mutating func handle(_ event: WizardEvent) -> WizardEffect {
        let previousMessage = message
        message = nil
        switch (phase, event) {
        case (.pickBrand, .choose(let picked)):
            brand = picked
            switch picked {
            case .sony: controlPort = 80; port = 5555
            case .xiaomi: controlPort = 6095; port = 6095
            case .generic: controlPort = 5555; port = 5555
            }
            go(.find)
            return .none
        case (.find, .pick(let tv)):
            apply(tv)
            return routeAfterFound()
        case (.find, .wantManual):
            go(.manual)
            return .none
        case (.manual, .submitManual(let rawHost, let rawPort)):
            let normalized = HostInput.normalize(rawHost)
            guard HostInput.isValidHost(normalized.host) else {
                message = "Enter the TV's address."
                return .none
            }
            host = normalized.host
            pairingPortHint = nil
            legacyAdbPort = nil
            macAddress = ""
            if let explicit = rawPort ?? normalized.port {
                port = explicit
            }
            if brand == .sony { controlPort = 80 }
            if brand == .xiaomi {
                controlPort = rawPort ?? normalized.port ?? 6095
                port = controlPort
            }
            if brand == .generic { controlPort = port }
            if name.isEmpty { name = host }
            return routeAfterFound()
        case (.sonyTyping, .typing(let yes)):
            wantsTyping = yes
            if !yes {
                go(.remember)
                return .none
            }
            guard adbReady else {
                wantsTyping = false
                message = "Typing needs the built-in helper, and this copy does not have it. Remote keys still work."
                return .none
            }
            return routeDebugging()
        case (.sonyKey, .testKey(let raw)):
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                message = WizardCopy.enterKey
                return .none
            }
            message = "Checking the key…"
            return .testSony(host: host, port: controlPort, psk: key)
        case (.sonyKey, .testSucceeded):
            verified = true
            switchWatch = nil
            go(.sonyTyping)
            return .none
        case (.sonyKey, .testFailed(let detail)):
            message = detail
            return .none
        case (.sonyKey, .continueAhead):
            switchWatch = nil
            go(.sonyTyping)
            return .none
        case (.sonyKey, .watch(let answered, let elapsed, let legacyPort)),
             (.debugging, .watch(let answered, let elapsed, let legacyPort)):
            return applyWatch(answered: answered, elapsed: elapsed, legacyPort: legacyPort, previousMessage: previousMessage)
        case (.sonyKey, .watchRetry), (.debugging, .watchRetry):
            if let kind = switchWatch?.kind {
                switchWatch = SwitchWatch(kind: kind)
            }
            return .none
        case (.xiaomiCheck, .testSucceeded):
            verified = true
            go(.remember)
            return .none
        case (.xiaomiCheck, .testFailed(let detail)):
            message = detail
            return .none
        case (.xiaomiCheck, .continueAhead):
            go(.remember)
            return .none
        case (.debugging, .chooseWireless):
            switchWatch = nil
            go(.pair)
            return .none
        case (.debugging, .chooseLegacy):
            switchWatch = nil
            port = 5555
            go(.allow)
            return .connectLegacy(host: host, port: 5555)
        case (.pair, .submitPair(let portText, let codeText)):
            let code = codeText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pairPort = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...65535).contains(pairPort),
                  code.count == 6,
                  code.allSatisfy(\.isNumber) else {
                message = WizardCopy.enterNumberAndCode
                return .none
            }
            return .pairAndConnect(host: host, pairPort: pairPort, code: code, connectPort: port)
        case (.pair, .pairSucceeded):
            go(.remember)
            return .none
        case (.pair, .pairFailed(let detail)):
            message = detail
            return .none
        case (.allow, .allowAccepted):
            go(.remember)
            return .none
        case (.allow, .allowWaiting):
            message = "Accept the prompt on the TV."
            return .none
        case (.allow, .connectFailed(let detail)):
            message = detail
            return .none
        case (.remember, .remember(let chosen)):
            let trimmed = chosen.trimmingCharacters(in: .whitespacesAndNewlines)
            name = trimmed.isEmpty ? host : trimmed
            switchWatch = nil
            phase = .done
            message = verified ? WizardCopy.connected(to: name) : WizardCopy.saved(to: name)
            return .save(draft())
        case (_, .back):
            switchWatch = nil
            guard let previous = stack.popLast() else { return .none }
            phase = previous
            return .none
        default:
            return .none
        }
    }

    private mutating func apply(_ tv: DiscoveredTV) {
        brand = tv.brand
        host = tv.host
        macAddress = tv.macAddress
        pairingPortHint = tv.pairingPort
        legacyAdbPort = tv.legacyAdbPort
        name = tv.friendlyName
        switch tv.brand {
        case .sony:
            controlPort = tv.controlPort == 0 ? 80 : tv.controlPort
            port = tv.legacyAdbPort ?? 5555
        case .xiaomi:
            controlPort = tv.controlPort == 0 ? 6095 : tv.controlPort
            port = controlPort
        case .generic:
            port = tv.legacyAdbPort ?? (tv.port == 0 ? 5555 : tv.port)
            controlPort = port
        }
    }

    private mutating func routeAfterFound() -> WizardEffect {
        switch brand {
        case .sony:
            switchWatch = SwitchWatch(kind: .sonyNetwork)
            go(.sonyKey)
            return .none
        case .generic:
            return routeDebugging()
        case .xiaomi:
            go(.xiaomiCheck)
            message = "Checking this TV…"
            return .testXiaomi(host: host, port: controlPort)
        case nil:
            return .none
        }
    }

    /// Least clicks: an open legacy debugging port goes straight to Allow.
    /// A pairing advertisement opens the code screen with the port filled in.
    private mutating func routeDebugging() -> WizardEffect {
        if let adbPort = legacyAdbPort {
            switchWatch = nil
            port = adbPort
            if brand == .generic { controlPort = adbPort }
            go(.allow)
            return .connectLegacy(host: host, port: adbPort)
        }
        if pairingPortHint != nil {
            switchWatch = nil
            go(.pair)
            return .none
        }
        switchWatch = SwitchWatch(kind: .networkDebugging)
        go(.debugging)
        return .none
    }

    private mutating func applyWatch(
        answered: Bool,
        elapsed: TimeInterval,
        legacyPort: Int?,
        previousMessage: String?
    ) -> WizardEffect {
        guard var watch = switchWatch else { return .none }
        if let legacyPort {
            legacyAdbPort = legacyPort
        }
        watch.note(answered: answered, elapsed: elapsed)
        switchWatch = watch
        switch watch.phase {
        case .waiting:
            message = previousMessage
            return .none
        case .timedOut:
            message = watch.timeoutMessage
            return .none
        case .detected:
            switch watch.kind {
            case .sonyNetwork:
                message = WizardCopy.networkOn
                return .none
            case .networkDebugging:
                switchWatch = nil
                if legacyAdbPort != nil || pairingPortHint != nil {
                    return routeDebugging()
                }
                go(.pair)
                message = WizardCopy.enterNumberAndCode
                return .none
            }
        }
    }

    private mutating func go(_ next: WizardPhase) {
        stack.append(phase)
        phase = next
    }
}
