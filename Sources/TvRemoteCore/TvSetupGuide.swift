import Foundation

public struct GuideStep: Equatable {
    public var symbol: String
    public var label: String
    public var english: String
    public var value: String

    public init(symbol: String, label: String, english: String = "", value: String = "") {
        self.symbol = symbol
        self.label = label
        self.english = english
        self.value = value
    }
}

public struct GuideCard: Equatable {
    public var key: String
    public var title: String
    public var why: String
    public var steps: [GuideStep]
    public var note: String

    public init(key: String, title: String, why: String, steps: [GuideStep], note: String = "") {
        self.key = key
        self.title = title
        self.why = why
        self.steps = steps
        self.note = note
    }
}

public enum TvSetupGuide {
    public static let sonyControl = GuideCard(
        key: "guide.sony.control",
        title: "Turn on control from the network",
        why: "This lets the Mac press the remote buttons. Do it once.",
        steps: [
            GuideStep(symbol: "gearshape", label: "设置", english: "Settings"),
            GuideStep(symbol: "wifi", label: "网络和互联网", english: "Network & Internet"),
            GuideStep(symbol: "house", label: "家庭网络", english: "Home network"),
            GuideStep(symbol: "network", label: "IP控制", english: "IP control"),
            GuideStep(symbol: "lock.shield", label: "认证", english: "Authentication", value: "普通和预共享密钥 · Normal and Pre-Shared Key"),
            GuideStep(symbol: "key", label: "预共享密钥", english: "Pre-Shared Key", value: "Type the key shown below")
        ],
        note: "Use the same key on the TV and here. Numbers are easiest to type with the TV remote."
    )

    public static let sonyRemoteStart = GuideCard(
        key: "guide.sony.remotestart",
        title: "Let the Mac turn the TV on",
        why: "Without this, the TV can be turned off from the Mac but not back on.",
        steps: [
            GuideStep(symbol: "gearshape", label: "设置", english: "Settings"),
            GuideStep(symbol: "wifi", label: "网络和互联网", english: "Network & Internet"),
            GuideStep(symbol: "power", label: "远程启动", english: "Remote start", value: "开（通过应用程序开机） · On (Powered on by apps)")
        ],
        note: "On some sets this switch is under Settings, System, Power & Energy."
    )

    public static let developerMode = GuideCard(
        key: "guide.android.developer",
        title: "Unlock the hidden developer menu",
        why: "Typing on the TV needs one hidden switch. Unlock it once.",
        steps: [
            GuideStep(symbol: "gearshape", label: "Settings"),
            GuideStep(symbol: "cpu", label: "System"),
            GuideStep(symbol: "info.circle", label: "About"),
            GuideStep(symbol: "hand.tap", label: "Build", value: "Press OK on it 7 times")
        ],
        note: "The TV says you are now a developer. On some sets the line is called Android TV OS build."
    )

    public static let networkDebugging = GuideCard(
        key: "guide.android.debugging",
        title: "Turn on Network debugging",
        why: "This lets the Mac type on the TV and install apps.",
        steps: [
            GuideStep(symbol: "gearshape", label: "Settings"),
            GuideStep(symbol: "cpu", label: "System"),
            GuideStep(symbol: "hammer", label: "Developer options"),
            GuideStep(symbol: "dot.radiowaves.left.and.right", label: "Network debugging", value: "On")
        ],
        note: "Newer sets call it Wireless debugging. Turn that on instead."
    )

    public static let pairCode = GuideCard(
        key: "guide.android.pair",
        title: "Show the pairing code on the TV",
        why: "The TV shows a number and a 6-digit code. Type both here.",
        steps: [
            GuideStep(symbol: "hammer", label: "Developer options"),
            GuideStep(symbol: "dot.radiowaves.left.and.right", label: "Wireless debugging"),
            GuideStep(symbol: "number", label: "Pair device with pairing code")
        ],
        note: "The number is the part after the colon, for example 37215."
    )

    public static let allowMac = GuideCard(
        key: "guide.android.allow",
        title: "Say yes on the TV",
        why: "The TV asks once whether this Mac may connect.",
        steps: [
            GuideStep(symbol: "checkmark.square", label: "Always allow from this computer", value: "Tick"),
            GuideStep(symbol: "hand.thumbsup", label: "OK", value: "Press")
        ]
    )

    public static let accessibility = GuideCard(
        key: "guide.mac.accessibility",
        title: "Optional: use the Mac keyboard as the remote",
        why: "Keyboard mode needs one Mac permission. Skip this if you only click the buttons.",
        steps: [
            GuideStep(symbol: "gearshape", label: "System Settings"),
            GuideStep(symbol: "hand.raised", label: "Privacy & Security"),
            GuideStep(symbol: "accessibility", label: "Accessibility"),
            GuideStep(symbol: "switch.2", label: "Zapbar", value: "On")
        ]
    )

    public static func cards(phase: WizardPhase, brand: TvBrand?, keyboardCapture: Bool) -> [GuideCard] {
        switch phase {
        case .sonyKey:
            return [sonyControl, sonyRemoteStart]
        case .debugging:
            return [developerMode, networkDebugging]
        case .pair:
            return [pairCode]
        case .allow:
            return [allowMac]
        case .done:
            return keyboardCapture && brand != .xiaomi ? [accessibility] : []
        case .pickBrand, .find, .manual, .sonyTyping, .xiaomiCheck, .remember:
            return []
        }
    }

    public static func suggestedKey(digits: Int = 6, next: () -> Int = { Int.random(in: 0...9) }) -> String {
        let count = min(max(digits, 4), 8)
        var text = ""
        while text.count < count {
            let digit = next() % 10
            if text.isEmpty && digit == 0 { continue }
            text += String(digit)
        }
        return text
    }
}
