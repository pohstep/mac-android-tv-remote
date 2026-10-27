import Foundation

public enum LoginItemStatus: Equatable {
    case enabled
    case requiresApproval
    case notFound
    case notRegistered
}

public struct LoginItemPresentation: Equatable {
    public var isOn: Bool
    public var message: String
    public var showsOpenSettings: Bool

    public init(isOn: Bool, message: String, showsOpenSettings: Bool) {
        self.isOn = isOn
        self.message = message
        self.showsOpenSettings = showsOpenSettings
    }
}

public enum LoginItemMapping {
    public static func present(_ status: LoginItemStatus) -> LoginItemPresentation {
        switch status {
        case .enabled:
            return LoginItemPresentation(isOn: true, message: "", showsOpenSettings: false)
        case .requiresApproval:
            return LoginItemPresentation(
                isOn: false,
                message: "macOS needs approval before Zapbar can open at login.",
                showsOpenSettings: true
            )
        case .notFound:
            return LoginItemPresentation(
                isOn: false,
                message: "Zapbar isn't set to open at login. Turn the switch on again.",
                showsOpenSettings: false
            )
        case .notRegistered:
            return LoginItemPresentation(isOn: false, message: "", showsOpenSettings: false)
        }
    }
}
