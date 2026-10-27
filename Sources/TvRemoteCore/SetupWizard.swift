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
    case continueAhead
    case remember(name: String)
    case back
}

public enum WizardEffect: Equatable {
    case none
    case pairAndConnect(host: String, pairPort: Int, code: String, connectPort: Int)
    case connectLegacy(host: String, port: Int)
    case save(StoredTV)
}

public enum SetupCopy {
    public static func lines(phase: WizardPhase, brand: TvBrand?, wantsTyping: Bool) -> [SetupLine] {
        switch phase {
        case .debugging:
            var lines = [
                SetupLine(key: "setup.debug.wireless.1", text: "On the TV, open Settings, then System, then Developer options."),
                SetupLine(key: "setup.debug.wireless.2", text: "Turn on Wireless debugging."),
                SetupLine(key: "setup.debug.wireless.3", text: "Choose pair with a code. You will need the port and the code shown on the TV."),
                SetupLine(key: "setup.debug.legacy.1", text: "Older sets connect without a pairing code."),
                SetupLine(key: "setup.debug.legacy.2", text: "When this Mac connects, accept Allow on the TV.")
            ]
            if brand == .sony && wantsTyping {
                lines.insert(SetupLine(key: "setup.sony.typing.1", text: "Typing needs this Mac to be allowed on the TV, as well as the control key."), at: 0)
            }
            return lines
        case .sonyKey:
            return [
                SetupLine(key: "setup.sony.ip.1", text: "On the TV, turn on control from the network."),
                SetupLine(key: "setup.sony.ip.2", text: "Set a control key. Enter the same key here. It stays in the Keychain.")
            ]
        case .remember where brand == .xiaomi:
            return [
                SetupLine(key: "setup.xiaomi.1", text: "This TV can use the remote buttons. Typing and turning it on from here aren't available.")
            ]
        case .pair:
            return [
                SetupLine(key: "setup.pair.1", text: "Enter the port and the 6-digit code shown on the TV.")
            ]
        case .allow:
            return [
                SetupLine(key: "setup.allow.1", text: "Accept the Allow prompt on the TV. This Mac then connects.")
            ]
        case .sonyTyping:
            return [
                SetupLine(key: "setup.sony.choice.1", text: "The control key runs the remote. Allow this Mac on the TV only if you want to type.")
            ]
        default:
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
    public private(set) var wantsTyping: Bool
    public private(set) var message: String?
    public private(set) var name: String
    private var stack: [WizardPhase]

    public init() {
        phase = .pickBrand
        brand = nil
        host = ""
        port = 5555
        controlPort = 80
        macAddress = ""
        pairingPortHint = nil
        wantsTyping = false
        message = nil
        name = ""
        stack = []
    }

    public func lines() -> [SetupLine] {
        SetupCopy.lines(phase: phase, brand: brand, wantsTyping: wantsTyping)
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
            go(yes ? .debugging : .sonyKey)
            return .none
        case (.debugging, .chooseWireless):
            go(.pair)
            return .none
        case (.debugging, .chooseLegacy):
            port = 5555
            go(.allow)
            return .connectLegacy(host: host, port: 5555)
        case (.pair, .submitPair(let portText, let codeText)):
            let code = codeText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pairPort = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...65535).contains(pairPort),
                  code.count == 6,
                  code.allSatisfy(\.isNumber) else {
                message = "Enter the port and the 6-digit code shown on the TV."
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
        case (.sonyKey, .continueAhead):
            go(.remember)
            return .none
        case (.remember, .remember(let chosen)):
            let trimmed = chosen.trimmingCharacters(in: .whitespacesAndNewlines)
            name = trimmed.isEmpty ? host : trimmed
            phase = .done
            return .save(draft())
        case (_, .back):
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
        if !tv.name.isEmpty { name = tv.name }
        switch tv.brand {
        case .sony:
            controlPort = tv.controlPort == 0 ? 80 : tv.controlPort
            port = 5555
        case .xiaomi:
            controlPort = tv.port == 0 ? 6095 : tv.port
            port = controlPort
        case .generic:
            port = tv.port == 0 ? 5555 : tv.port
            controlPort = port
        }
    }

    private mutating func routeAfterFound() -> WizardEffect {
        switch brand {
        case .sony:
            go(.sonyTyping)
        case .generic:
            go(.debugging)
        case .xiaomi:
            go(.remember)
        case nil:
            break
        }
        return .none
    }

    private mutating func go(_ next: WizardPhase) {
        stack.append(phase)
        phase = next
    }
}
