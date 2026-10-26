import Foundation

public struct TvActionContext {
    public var host: String
    public var adbPort: Int
    public var controlPort: Int
    public var psk: String
    public var serial: String?
    public var adb: AdbClient?
    public var http: any HttpSending
    public var reader: any HttpReading
    public var isPlaying: Bool
    public var allowSony: Bool
    public var replacementText: String
    public var onSonySuccess: () -> Void
    public var onSonyFailure: () -> Void
    public var scrub: (String) -> String
    public var notConnected: () -> ActionReport
    public var failureDetail: (Error) -> String

    public init(
        host: String,
        adbPort: Int,
        controlPort: Int,
        psk: String,
        serial: String?,
        adb: AdbClient?,
        http: any HttpSending,
        reader: any HttpReading,
        isPlaying: Bool,
        allowSony: Bool,
        replacementText: String = "",
        onSonySuccess: @escaping () -> Void = {},
        onSonyFailure: @escaping () -> Void = {},
        scrub: @escaping (String) -> String = { $0 },
        notConnected: @escaping () -> ActionReport = {
            ActionReport(title: "No TV address yet", detail: "", isError: true)
        },
        failureDetail: @escaping (Error) -> String = { _ in "The command failed." }
    ) {
        self.host = host
        self.adbPort = adbPort
        self.controlPort = controlPort
        self.psk = psk
        self.serial = serial
        self.adb = adb
        self.http = http
        self.reader = reader
        self.isPlaying = isPlaying
        self.allowSony = allowSony
        self.replacementText = replacementText
        self.onSonySuccess = onSonySuccess
        self.onSonyFailure = onSonyFailure
        self.scrub = scrub
        self.notConnected = notConnected
        self.failureDetail = failureDetail
    }
}

public protocol TvBackend {
    var brand: TvBrand { get }
    func sendKey(_ key: AndroidKey, context: TvActionContext) -> ActionReport
    func sendText(_ text: String, context: TvActionContext) -> ActionReport
    func launch(package: String, name: String, context: TvActionContext) -> ActionReport
    func selectHDMI(_ port: Int, context: TvActionContext) -> ActionReport
    func power(on: Bool, context: TvActionContext) -> ActionReport
}

public enum TvBackends {
    public static func make(_ brand: TvBrand) -> any TvBackend {
        switch brand {
        case .sony: return SonyIPBackend()
        case .generic: return GenericTVBackend()
        case .xiaomi: return XiaomiTVBackend()
        }
    }
}

public struct GenericTVBackend: TvBackend {
    public let brand = TvBrand.generic
    public init() {}

    public func sendKey(_ key: AndroidKey, context: TvActionContext) -> ActionReport {
        guard let serial = context.serial, let adb = context.adb else { return context.notConnected() }
        do {
            try adb.keyEvent(key, serial: serial)
            return ActionReport(title: context.scrub(key.spoken), detail: context.scrub(serial), isError: false)
        } catch {
            return ActionReport(
                title: context.scrub("Couldn't send \(key.spoken)"),
                detail: context.scrub(context.failureDetail(error)),
                isError: true
            )
        }
    }

    public func sendText(_ text: String, context: TvActionContext) -> ActionReport {
        guard let serial = context.serial, let adb = context.adb else { return context.notConnected() }
        do {
            try adb.inputText(text, serial: serial)
            return ActionReport(title: "Typed \(text.count) characters", detail: "", isError: false)
        } catch {
            return ActionReport(title: "Couldn't type", detail: context.scrub(context.failureDetail(error)), isError: true)
        }
    }

    public func launch(package: String, name: String, context: TvActionContext) -> ActionReport {
        guard let serial = context.serial, let adb = context.adb else { return context.notConnected() }
        do {
            try adb.launchApp(packageName: package, serial: serial)
            return ActionReport(title: "Opening \(name)", detail: package, isError: false)
        } catch {
            return ActionReport(
                title: "\(name) didn't open",
                detail: "Is \(package) installed on the TV? \(context.failureDetail(error))",
                isError: true
            )
        }
    }

    public func selectHDMI(_ port: Int, context: TvActionContext) -> ActionReport {
        guard (1...4).contains(port) else {
            return ActionReport(title: "Unknown input", detail: "HDMI ports are 1 to 4.", isError: true)
        }
        return sendKey(AndroidKey.hdmiPorts[port - 1], context: context)
    }

    public func power(on: Bool, context: TvActionContext) -> ActionReport {
        sendKey(on ? .wakeup : .sleep, context: context)
    }
}

public struct SonyIPBackend: TvBackend {
    public let brand = TvBrand.sony
    public init() {}

    public func sendKey(_ key: AndroidKey, context: TvActionContext) -> ActionReport {
        if context.allowSony,
           let button = SonyButton.forKey(key, isPlaying: context.isPlaying),
           IrccCode.value(button) != nil {
            let sony = SonyClient(http: context.http)
            if sony.sendIRCC(button, host: context.host, port: context.controlPort, psk: context.psk) {
                context.onSonySuccess()
                return ActionReport(title: context.scrub(key.spoken), detail: context.scrub("Sent over Sony IP"), isError: false)
            }
            context.onSonyFailure()
        }
        return GenericTVBackend().sendKey(key, context: context)
    }

    public func sendText(_ text: String, context: TvActionContext) -> ActionReport {
        let field = context.replacementText.isEmpty ? text : context.replacementText
        let sony = SonyClient(http: context.http)
        if sony.setTextForm(field, host: context.host, port: context.controlPort, psk: context.psk) {
            context.onSonySuccess()
            return ActionReport(title: "Typed \(text.count) characters", detail: "Sony IP", isError: false)
        }
        context.onSonyFailure()
        return ActionReport(title: "Couldn't type", detail: "Open a text field on the TV, then try again.", isError: true)
    }

    public func launch(package: String, name: String, context: TvActionContext) -> ActionReport {
        GenericTVBackend().launch(package: package, name: name, context: context)
    }

    public func selectHDMI(_ port: Int, context: TvActionContext) -> ActionReport {
        guard (1...4).contains(port) else {
            return ActionReport(title: "Unknown input", detail: "HDMI ports are 1 to 4.", isError: true)
        }
        if context.allowSony {
            let sony = SonyClient(http: context.http)
            if sony.play(uri: SonyParse.hdmiURI(port: port), host: context.host, port: context.controlPort, psk: context.psk) {
                context.onSonySuccess()
                return ActionReport(title: "HDMI \(port)", detail: "Sent over Sony IP", isError: false)
            }
            context.onSonyFailure()
        }
        return GenericTVBackend().selectHDMI(port, context: context)
    }

    public func power(on: Bool, context: TvActionContext) -> ActionReport {
        if context.allowSony {
            let sony = SonyClient(http: context.http)
            if sony.setPower(on: on, host: context.host, port: context.controlPort, psk: context.psk) {
                context.onSonySuccess()
                return ActionReport(title: on ? "Sent wake" : "Sent sleep", detail: "Sony IP", isError: false)
            }
            context.onSonyFailure()
        }
        return GenericTVBackend().power(on: on, context: context)
    }
}

/// Experimental. See `XiaomiClient`. No text and no power-on.
public struct XiaomiTVBackend: TvBackend {
    public let brand = TvBrand.xiaomi
    public init() {}

    public func sendKey(_ key: AndroidKey, context: TvActionContext) -> ActionReport {
        guard let code = XiaomiKey.code(for: key) else {
            return ActionReport(title: "Couldn't send \(key.spoken)", detail: "This TV can't do that from the remote.", isError: true)
        }
        let client = XiaomiClient(reader: context.reader)
        let port = context.controlPort == 0 ? 6095 : context.controlPort
        if client.sendKey(code, host: context.host, port: port) {
            return ActionReport(title: key.spoken, detail: "\(context.host):\(port)", isError: false)
        }
        return ActionReport(title: "Couldn't send \(key.spoken)", detail: "The TV didn't accept the key.", isError: true)
    }

    public func sendText(_ text: String, context: TvActionContext) -> ActionReport {
        ActionReport(title: "Couldn't type", detail: "This TV can't type from the remote.", isError: true)
    }

    public func launch(package: String, name: String, context: TvActionContext) -> ActionReport {
        let client = XiaomiClient(reader: context.reader)
        let port = context.controlPort == 0 ? 6095 : context.controlPort
        if client.launch(package: package, host: context.host, port: port) {
            return ActionReport(title: "Opening \(name)", detail: package, isError: false)
        }
        return ActionReport(title: "\(name) didn't open", detail: "The TV didn't accept the launch.", isError: true)
    }

    public func selectHDMI(_ port: Int, context: TvActionContext) -> ActionReport {
        guard (1...4).contains(port) else {
            return ActionReport(title: "Unknown input", detail: "HDMI ports are 1 to 4.", isError: true)
        }
        let client = XiaomiClient(reader: context.reader)
        let control = context.controlPort == 0 ? 6095 : context.controlPort
        if client.selectHDMI(port, host: context.host, port: control) {
            return ActionReport(title: "HDMI \(port)", detail: "\(context.host):\(control)", isError: false)
        }
        return ActionReport(title: "Couldn't change input", detail: "The TV didn't accept the source change.", isError: true)
    }

    public func power(on: Bool, context: TvActionContext) -> ActionReport {
        if on {
            return ActionReport(title: "Couldn't wake the TV", detail: "This TV can't be turned on from the remote.", isError: true)
        }
        return sendKey(.sleep, context: context)
    }
}
