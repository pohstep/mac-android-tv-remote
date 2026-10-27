import Foundation

public struct KeyModifiers: OptionSet, Equatable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
}

public enum InputKey: Equatable {
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case returnKey
    case keypadEnter
    case esc
    case delete
    case forwardDelete
    case home
    case f1
    case space
    case ansi(Character)
    case mediaPlayPause
    case volumeUp
    case volumeDown
    case mute
    case other
}

public struct KeyChord: Equatable {
    public var key: InputKey
    public var modifiers: KeyModifiers
    public var characters: String

    public init(key: InputKey, modifiers: KeyModifiers = [], characters: String = "") {
        self.key = key
        self.modifiers = modifiers
        self.characters = characters
    }
}

public struct Hotkey: Equatable, Codable {
    public var letter: String
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var command: Bool

    public init(letter: String, control: Bool, option: Bool, shift: Bool, command: Bool) {
        self.letter = letter
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
    }

    public static let `default` = Hotkey(letter: "k", control: true, option: true, shift: false, command: false)
    /// Opens the panel and focuses the type field. Carbon registers this, including in the sandbox.
    public static let typeDefault = Hotkey(letter: "t", control: true, option: true, shift: false, command: false)

    public var display: String {
        var symbols = ""
        if control { symbols += "⌃" }
        if option { symbols += "⌥" }
        if shift { symbols += "⇧" }
        if command { symbols += "⌘" }
        return symbols + letter.uppercased()
    }

    public func matches(_ chord: KeyChord) -> Bool {
        guard case .ansi(let character) = chord.key else { return false }
        guard String(character) == letter.lowercased() else { return false }
        return chord.modifiers.contains(.control) == control
            && chord.modifiers.contains(.option) == option
            && chord.modifiers.contains(.shift) == shift
            && chord.modifiers.contains(.command) == command
    }
}

public enum KeyEffect: Equatable {
    case ignore
    case passthrough
    case toggleKeyboardMode
    case send(RemoteAction)
}

public enum KeyMapping {
    /// When keyboard mode is off, only the global hotkey is captured.
    /// Arrows are the D-pad, Return is OK, Esc and Delete are Back,
    /// and H (also the Home key, F1, and Control-H) goes Home.
    /// Other letters are text for search boxes. The trackpad and mouse are not a remote.
    public static func effect(
        for chord: KeyChord,
        keyboardMode: Bool,
        hotkey: Hotkey = .default
    ) -> KeyEffect {
        if hotkey.matches(chord) {
            return .toggleKeyboardMode
        }
        // Stop chord ⌃⌥⌘K: never forwarded; turns keyboard mode off.
        if case .ansi(let c) = chord.key, c == "k",
           chord.modifiers.contains([.control, .option, .command]) {
            return keyboardMode ? .toggleKeyboardMode : .ignore
        }
        guard keyboardMode else { return .ignore }
        if chord.modifiers.contains(.command) {
            return .passthrough
        }

        switch chord.key {
        case .arrowUp:
            return .send(.key(.dpadUp))
        case .arrowDown:
            return .send(.key(.dpadDown))
        case .arrowLeft:
            return .send(.key(.dpadLeft))
        case .arrowRight:
            return .send(.key(.dpadRight))
        case .returnKey, .keypadEnter:
            return .send(.key(.dpadCenter))
        case .esc:
            return .send(.key(.back))
        case .delete:
            // Backspace deletes a character in TV text fields.
            return .send(.key(.del))
        case .forwardDelete:
            return .send(.key(.forwardDel))
        case .home, .f1:
            return .send(.key(.home))
        case .mediaPlayPause:
            return .send(.key(.mediaPlayPause))
        case .volumeUp:
            return .send(.key(.volumeUp))
        case .volumeDown:
            return .send(.key(.volumeDown))
        case .mute:
            return .send(.key(.volumeMute))
        case .space:
            return .send(.text(chord.characters.isEmpty ? " " : chord.characters))
        case .ansi(let letter):
            let plainH = letter == "h"
                && !chord.modifiers.contains(.control)
                && !chord.modifiers.contains(.option)
                && !chord.modifiers.contains(.command)
            let controlH = letter == "h"
                && chord.modifiers.contains(.control)
                && !chord.modifiers.contains(.option)
                && !chord.modifiers.contains(.command)
            // Plain h is a letter now (typing); Control-H stays Home.
            _ = plainH
            if controlH {
                return .send(.key(.home))
            }
            if chord.modifiers.contains(.control) {
                return .passthrough
            }
            if !chord.characters.isEmpty {
                return .send(.text(chord.characters))
            }
            let glyph = chord.modifiers.contains(.shift) ? String(letter).uppercased() : String(letter)
            return .send(.text(glyph))
        case .other:
            if !chord.characters.isEmpty && !chord.modifiers.contains(.control) {
                return .send(.text(chord.characters))
            }
            return .passthrough
        }
    }
}

/// Hardware key codes shared by macOS event taps. Mapped here so the table is tested on Linux.
public enum MacVirtualKey {
    public static func inputKey(for code: Int) -> InputKey {
        switch code {
        case 126: return .arrowUp
        case 125: return .arrowDown
        case 123: return .arrowLeft
        case 124: return .arrowRight
        case 36: return .returnKey
        case 76: return .keypadEnter
        case 53: return .esc
        case 51: return .delete
        case 117: return .forwardDelete
        case 115: return .home
        case 122: return .f1
        case 49: return .space
        case 72: return .volumeUp
        case 73: return .volumeDown
        case 74: return .mute
        default:
            if let letter = ansi[code] {
                return .ansi(letter)
            }
            return .other
        }
    }

    private static let ansi: [Int: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g",
        6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        25: "9", 26: "7", 28: "8", 29: "0",
        31: "o", 32: "u", 34: "i", 35: "p",
        37: "l", 38: "j", 40: "k",
        45: "n", 46: "m"
    ]
}
