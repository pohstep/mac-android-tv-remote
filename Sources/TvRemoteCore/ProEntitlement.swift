import Foundation

public enum ProFeature: String, CaseIterable, Equatable {
    case panelKeyboard
    case globalHotkeys
    case sendClipboard
    case severalTVs
    case screenshot
    case apkInstall
    case appManagement
}

public struct ProAccess: Equatable {
    public var purchased: Bool
    public var preview: Bool

    public init(purchased: Bool, preview: Bool) {
        self.purchased = purchased
        self.preview = preview
    }

    public var isPro: Bool { purchased || preview }

    public static let locked = ProAccess(purchased: false, preview: false)
}

public enum ProProduct {
    public static let id = "app.pohstep.remote.pro"
    public static let displayName = "Zapbar Pro"
    public static let displayPrice = "1.99"
    public static let familyShareable = true
    public static let consumable = false
    public static let trial = false
}

public enum ProGate {
    public static func allows(_ feature: ProFeature, access: ProAccess) -> Bool {
        switch feature {
        case .panelKeyboard, .globalHotkeys, .sendClipboard, .severalTVs, .screenshot, .apkInstall, .appManagement:
            return access.isPro
        }
    }
}

public enum GlobalHotkeyAction: Equatable {
    case power
    case volumeUp
    case volumeDown
    case playPause
    case openPanel
    case sendClipboard
}

public struct BoundHotkey: Codable, Equatable {
    public var keyCode: Int
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var command: Bool

    public init(keyCode: Int, control: Bool, option: Bool, shift: Bool, command: Bool) {
        self.keyCode = keyCode
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
    }

    public var modifiers: KeyModifiers {
        var value = KeyModifiers()
        if control { value.insert(.control) }
        if option { value.insert(.option) }
        if shift { value.insert(.shift) }
        if command { value.insert(.command) }
        return value
    }

    public func matches(keyCode: Int, modifiers: KeyModifiers) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    public var display: String {
        var symbols = ""
        if control { symbols += "⌃" }
        if option { symbols += "⌥" }
        if shift { symbols += "⇧" }
        if command { symbols += "⌘" }
        return symbols + BoundHotkey.name(for: keyCode)
    }

    public static func name(for keyCode: Int) -> String {
        switch keyCode {
        case 126: return "↑"
        case 125: return "↓"
        case 123: return "←"
        case 124: return "→"
        case 49: return "Space"
        case 36: return "Return"
        default:
            if let letter = letter(for: keyCode) { return String(letter).uppercased() }
            return ""
        }
    }

    public static func letter(for keyCode: Int) -> Character? {
        switch keyCode {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 31: return "o"
        case 32: return "u"
        case 34: return "i"
        case 35: return "p"
        case 37: return "l"
        case 38: return "j"
        case 40: return "k"
        case 45: return "n"
        case 46: return "m"
        default: return nil
        }
    }
}

public struct GlobalHotkeys: Codable, Equatable {
    public var power: BoundHotkey
    public var volumeUp: BoundHotkey
    public var volumeDown: BoundHotkey
    public var playPause: BoundHotkey
    public var openPanel: BoundHotkey
    public var sendClipboard: BoundHotkey

    public init(
        power: BoundHotkey,
        volumeUp: BoundHotkey,
        volumeDown: BoundHotkey,
        playPause: BoundHotkey,
        openPanel: BoundHotkey,
        sendClipboard: BoundHotkey
    ) {
        self.power = power
        self.volumeUp = volumeUp
        self.volumeDown = volumeDown
        self.playPause = playPause
        self.openPanel = openPanel
        self.sendClipboard = sendClipboard
    }

    public static let factory = GlobalHotkeys(
        power: BoundHotkey(keyCode: 35, control: true, option: true, shift: false, command: false),
        volumeUp: BoundHotkey(keyCode: 126, control: true, option: true, shift: false, command: false),
        volumeDown: BoundHotkey(keyCode: 125, control: true, option: true, shift: false, command: false),
        playPause: BoundHotkey(keyCode: 49, control: true, option: true, shift: false, command: false),
        openPanel: BoundHotkey(keyCode: 17, control: true, option: true, shift: false, command: false),
        sendClipboard: BoundHotkey(keyCode: 9, control: true, option: true, shift: false, command: true)
    )

    public func action(for keyCode: Int, modifiers: KeyModifiers) -> GlobalHotkeyAction? {
        if power.matches(keyCode: keyCode, modifiers: modifiers) { return .power }
        if volumeUp.matches(keyCode: keyCode, modifiers: modifiers) { return .volumeUp }
        if volumeDown.matches(keyCode: keyCode, modifiers: modifiers) { return .volumeDown }
        if playPause.matches(keyCode: keyCode, modifiers: modifiers) { return .playPause }
        if openPanel.matches(keyCode: keyCode, modifiers: modifiers) { return .openPanel }
        if sendClipboard.matches(keyCode: keyCode, modifiers: modifiers) { return .sendClipboard }
        return nil
    }
}
