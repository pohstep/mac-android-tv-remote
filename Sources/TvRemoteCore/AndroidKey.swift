import Foundation

/// Android `input keyevent` names. Numbers are the platform key codes.
public enum AndroidKey: String, Equatable, CaseIterable {
    case home = "KEYCODE_HOME"
    case back = "KEYCODE_BACK"
    case del = "KEYCODE_DEL"
    case forwardDel = "KEYCODE_FORWARD_DEL"
    case dpadUp = "KEYCODE_DPAD_UP"
    case dpadDown = "KEYCODE_DPAD_DOWN"
    case dpadLeft = "KEYCODE_DPAD_LEFT"
    case dpadRight = "KEYCODE_DPAD_RIGHT"
    case dpadCenter = "KEYCODE_DPAD_CENTER"
    case volumeUp = "KEYCODE_VOLUME_UP"
    case volumeDown = "KEYCODE_VOLUME_DOWN"
    case volumeMute = "KEYCODE_VOLUME_MUTE"
    case mediaPlayPause = "KEYCODE_MEDIA_PLAY_PAUSE"
    case mediaNext = "KEYCODE_MEDIA_NEXT"
    case mediaPrevious = "KEYCODE_MEDIA_PREVIOUS"
    case wakeup = "KEYCODE_WAKEUP"
    case sleep = "KEYCODE_SLEEP"
    case power = "KEYCODE_POWER"
    case menu = "KEYCODE_MENU"
    case hdmi1 = "KEYCODE_TV_INPUT_HDMI_1"
    case hdmi2 = "KEYCODE_TV_INPUT_HDMI_2"
    case hdmi3 = "KEYCODE_TV_INPUT_HDMI_3"
    case hdmi4 = "KEYCODE_TV_INPUT_HDMI_4"
    case num0 = "KEYCODE_0"
    case num1 = "KEYCODE_1"
    case num2 = "KEYCODE_2"
    case num3 = "KEYCODE_3"
    case num4 = "KEYCODE_4"
    case num5 = "KEYCODE_5"
    case num6 = "KEYCODE_6"
    case num7 = "KEYCODE_7"
    case num8 = "KEYCODE_8"
    case num9 = "KEYCODE_9"

    public static let hdmiPorts: [AndroidKey] = [.hdmi1, .hdmi2, .hdmi3, .hdmi4]
    public static let digits: [AndroidKey] = [.num1, .num2, .num3, .num4, .num5, .num6, .num7, .num8, .num9, .num0]

    public var code: Int {
        switch self {
        case .home: return 3
        case .back: return 4
        case .del: return 67
        case .forwardDel: return 112
        case .dpadUp: return 19
        case .dpadDown: return 20
        case .dpadLeft: return 21
        case .dpadRight: return 22
        case .dpadCenter: return 23
        case .volumeUp: return 24
        case .volumeDown: return 25
        case .power: return 26
        case .mediaPlayPause: return 85
        case .mediaNext: return 87
        case .mediaPrevious: return 88
        case .menu: return 82
        case .volumeMute: return 164
        case .sleep: return 223
        case .wakeup: return 224
        case .hdmi1: return 243
        case .hdmi2: return 244
        case .hdmi3: return 245
        case .hdmi4: return 246
        case .num0: return 7
        case .num1: return 8
        case .num2: return 9
        case .num3: return 10
        case .num4: return 11
        case .num5: return 12
        case .num6: return 13
        case .num7: return 14
        case .num8: return 15
        case .num9: return 16
        }
    }

    public var spoken: String {
        switch self {
        case .home: return "Home"
        case .back: return "Back"
        case .del: return "Delete"
        case .forwardDel: return "Forward delete"
        case .dpadUp: return "Up"
        case .dpadDown: return "Down"
        case .dpadLeft: return "Left"
        case .dpadRight: return "Right"
        case .dpadCenter: return "OK"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .volumeMute: return "Mute"
        case .mediaPlayPause: return "Play/pause"
        case .mediaNext: return "Next"
        case .mediaPrevious: return "Previous"
        case .wakeup: return "Wake"
        case .sleep: return "Sleep"
        case .power: return "Power"
        case .menu: return "Menu"
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .hdmi3: return "HDMI 3"
        case .hdmi4: return "HDMI 4"
        case .num0: return "0"
        case .num1: return "1"
        case .num2: return "2"
        case .num3: return "3"
        case .num4: return "4"
        case .num5: return "5"
        case .num6: return "6"
        case .num7: return "7"
        case .num8: return "8"
        case .num9: return "9"
        }
    }
}

public enum RemoteAction: Equatable {
    case key(AndroidKey)
    case text(String)
    case launch(packageName: String, displayName: String)
}
