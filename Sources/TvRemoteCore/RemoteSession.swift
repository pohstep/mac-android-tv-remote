import Foundation

public enum IngestResult: Equatable {
    case ignored
    case passthrough
    case toggled(Bool)
    case buffered
    case flushAndSend(text: String, action: RemoteAction)
    case send(RemoteAction)
}

public final class RemoteSession {
    public private(set) var settings: Settings
    public private(set) var status: LinkStatus
    public private(set) var keyboardMode: Bool
    public let hotkey: Hotkey

    private let runner: any CommandRunning
    private let wol: any WakeOnLanSending
    private let http: any HttpSending
    private let fileExists: (String) -> Bool
    private let pathEnvironment: String
    private let homeDirectory: String
    private let lock = NSLock()
    private var typing = ""
    private var preSharedKey = ""
    private var picture = TvPicture()
    private var sonyBlockedUntil = Date.distantPast

    public init(
        settings: Settings,
        runner: any CommandRunning,
        wol: any WakeOnLanSending = WakeOnLanSender(),
        http: any HttpSending = URLSessionHttp(),
        hotkey: Hotkey = .default,
        fileExists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.settings = settings
        self.status = .idle
        self.keyboardMode = settings.keyboardMode
        self.hotkey = hotkey
        self.runner = runner
        self.wol = wol
        self.http = http
        self.fileExists = fileExists
        self.pathEnvironment = pathEnvironment
        self.homeDirectory = homeDirectory
    }

    /// The key stays in memory for this process. It is not written into settings.
    public func setPreSharedKey(_ key: String) {
        lock.critical { preSharedKey = key }
    }

    public func currentPicture() -> TvPicture {
        lock.critical { picture }
    }

    public func replaceSettings(_ newValue: Settings) {
        lock.lock()
        settings = newValue
        keyboardMode = newValue.keyboardMode
        lock.unlock()
    }

    public func setKeyboardMode(_ on: Bool) {
        lock.lock()
        keyboardMode = on
        settings.keyboardMode = on
        lock.unlock()
    }

    public func flushTyping() -> String {
        lock.lock()
        let pending = typing
        typing = ""
        lock.unlock()
        return pending
    }

    public func ingest(_ chord: KeyChord) -> IngestResult {
        lock.lock()
        let mode = keyboardMode
        let effect = KeyMapping.effect(for: chord, keyboardMode: mode, hotkey: hotkey)
        switch effect {
        case .ignore:
            lock.unlock()
            return .ignored
        case .passthrough:
            lock.unlock()
            return .passthrough
        case .toggleKeyboardMode:
            keyboardMode.toggle()
            settings.keyboardMode = keyboardMode
            let now = keyboardMode
            lock.unlock()
            return .toggled(now)
        case .send(let action):
            if case .text(let text) = action {
                typing += text
                lock.unlock()
                return .buffered
            }
            let pending = typing
            typing = ""
            lock.unlock()
            if pending.isEmpty {
                return .send(action)
            }
            return .flushAndSend(text: pending, action: action)
        }
    }

    @discardableResult
    public func refresh() -> LinkStatus {
        var host = settings.host
        var port = settings.port
        let normalized = HostInput.normalize(host)
        host = normalized.host
        if let parsedPort = normalized.port {
            port = parsedPort
        }
        if !(1...65535).contains(port) {
            port = 5555
        }

        lock.lock()
        settings.host = host
        settings.port = port
        let adbPathSetting = settings.adbPath
        lock.unlock()

        if host.isEmpty {
            return assign(.idle)
        }
        if !HostInput.isValidHost(host) {
            return assign(.failed(message: "\(host) isn't a usable address. Use an IP or a hostname."))
        }

        let locator = AdbLocator(
            candidatePaths: AdbLocator.defaultCandidates(homeDirectory: homeDirectory),
            pathEnvironment: pathEnvironment,
            fileExists: fileExists
        )
        let custom = adbPathSetting.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let adb = locator.resolve(customPath: custom.isEmpty ? nil : custom) else {
            let message = custom.isEmpty ? Copy.adbMissing() : Copy.adbMissing(at: custom)
            return assign(.adbMissing(message: message))
        }

        let serial = "\(host):\(port)"
        _ = assign(.connecting(serial: serial))
        let client = AdbClient(runner: runner, adbPath: adb)

        do {
            let outcome = try client.connect(host: host, port: port)
            let listed = try client.listDevices()
            switch AdbOutput.parseDevices(listed.combined, serial: serial) {
            case .device:
                return assign(.connected(serial: serial))
            case .unauthorized:
                return assign(.unauthorized(serial: serial))
            case .offline:
                return assign(.offline(serial: serial))
            case .missing:
                let detail = outcome.failureDetail
                if AdbOutput.isRefusal(detail) {
                    return assign(.refused(serial: serial, detail: Copy.refused(serial: serial)))
                }
                let message = detail.isEmpty ? "Couldn't reach \(serial)." : detail
                return assign(.failed(message: message))
            }
        } catch let error as RemoteError {
            if case .notFound = error {
                return assign(.adbMissing(message: Copy.adbMissing()))
            }
            if case .timedOut = error {
                return assign(.failed(message: "Timed out contacting \(serial)."))
            }
            return assign(.failed(message: error.description))
        } catch {
            return assign(.failed(message: "Couldn't reach \(serial)."))
        }
    }

    public func press(_ key: AndroidKey) -> ActionReport {
        if let sony = sendSony(key) {
            return sony
        }
        guard let serial = connectedSerial() else {
            return notConnectedReport()
        }
        do {
            try client().keyEvent(key, serial: serial)
            return ActionReport(title: key.spoken, detail: serial, isError: false)
        } catch {
            return ActionReport(title: "Couldn't send \(key.spoken)", detail: errorText(error), isError: true)
        }
    }

    public func selectInput(uri: String) -> ActionReport {
        if let port = hdmiPort(in: uri) {
            return selectHdmi(port)
        }
        if sendSonyPlay(uri: uri) {
            return report("Input", "Sent over Sony IP", error: false)
        }
        return ActionReport(
            title: "That input needs Sony IP",
            detail: "Save the pre-shared key, or pick an HDMI port.",
            isError: true
        )
    }

    public func selectHdmi(_ port: Int) -> ActionReport {
        guard (1...4).contains(port) else {
            return ActionReport(title: "Unknown input", detail: "HDMI ports are 1 to 4.", isError: true)
        }
        if sendSonyPlay(uri: SonyParse.hdmiURI(port: port)) {
            return report("HDMI \(port)", "Sent over Sony IP", error: false)
        }
        return press(AndroidKey.hdmiPorts[port - 1])
    }

    public func setVolume(_ level: Int) -> ActionReport {
        guard let target = sonyCredentials() else {
            return ActionReport(
                title: "Exact volume needs Sony IP",
                detail: "Save the pre-shared key in Settings, or use volume up and down over adb.",
                isError: true
            )
        }
        let sony = SonyClient(http: http)
        if sony.setVolume(level, host: target.host, port: target.port, psk: target.psk) {
            noteSonySuccess()
            lock.critical {
                picture.volume = level
                picture.sonyReady = true
            }
            return report("Volume \(level)", "Sent over Sony IP", error: false)
        }
        noteSonyFailure()
        return ActionReport(
            title: "Exact volume needs Sony IP",
            detail: "Sony IP didn't accept the volume. Volume up and down still work over adb.",
            isError: true
        )
    }

    public func refreshPicture() -> TvPicture {
        let current = lock.critical { status }
        var next = TvPicture()
        if let target = sonyCredentials() {
            let sony = SonyClient(http: http)
            if let power = sony.powerStatus(host: target.host, port: target.port, psk: target.psk) {
                next.power = power
                next.sonyReady = true
            }
            if let volume = sony.volume(host: target.host, port: target.port, psk: target.psk) {
                next.volume = volume.volume
                next.maxVolume = volume.maxVolume
                next.muted = volume.muted
                next.sonyReady = true
            }
            let inputs = sony.inputs(host: target.host, port: target.port, psk: target.psk)
            next.inputs = inputs
            if let shown = inputs.first(where: \.connected) ?? inputs.first {
                next.inputTitle = shown.menuTitle
                next.inputURI = shown.uri
                next.sonyReady = true
            }
            if let title = sony.playingTitle(host: target.host, port: target.port, psk: target.psk), next.inputTitle == nil {
                next.inputTitle = title
                next.sonyReady = true
            }
            if next.sonyReady {
                noteSonySuccess()
            }
        }
        if case .connected(let serial) = current {
            next.adbReady = true
            if next.power == .unknown {
                next.power = .reachableOnly
            }
            if let dump = try? client().shell(["dumpsys", "window"], serial: serial) {
                next.foregroundPackage = ScreenDump.foregroundPackage(dump)
            }
            if let dump = try? client().shell(["dumpsys", "media_session"], serial: serial),
               let playing = ScreenDump.nowPlaying(dump) {
                next.nowPlaying = TvApp.cleanName(playing.line)
                next.isPlaying = playing.isPlaying
            }
        }
        lock.critical { picture = next }
        return next
    }

    /// Text sent with Sony setTextForm since the last adb success (that call replaces the field).
    private var sonyField = ""

    public func type(_ text: String) -> ActionReport {
        guard !text.isEmpty else {
            return ActionReport(title: "", detail: "", isError: false)
        }
        // Never log or show the characters (passwords): counts only.
        let count = text.count
        // adb `input text` appends at the cursor, so it is first. Sony setTextForm replaces the
        // whole field, so it is only the fallback when adb is down and a text field is open.
        if let serial = connectedSerial() {
            do {
                try client().inputText(text, serial: serial)
                NSLog("Pohstep Remote: typed %d chars via adb", count)
                return ActionReport(title: "Typed \(count) characters", detail: "", isError: false)
            } catch {
                NSLog("Pohstep Remote: adb typing failed for %d chars", count)
            }
        }
        if let target = sonyCredentials() {
            let field = lock.critical { () -> String in sonyField += text; return sonyField }
            if SonyClient(http: http).setTextForm(field, host: target.host, port: target.port, psk: target.psk) {
                NSLog("Pohstep Remote: typed %d chars via Sony setTextForm", count)
                return ActionReport(title: "Typed \(count) characters", detail: "Sony IP", isError: false)
            }
            lock.critical { sonyField = "" }
            NSLog("Pohstep Remote: setTextForm refused %d chars (no text field open?)", count)
            return ActionReport(title: "Couldn't type", detail: "Open a search or text field on the TV, or connect adb.", isError: true)
        }
        return notConnectedReport()
    }

    /// Launcher export first, then leanback activities. Nil when adb is not connected or both reads fail.
    public func readApps() -> [TvApp]? {
        if let target = sonyCredentials() {
            let sonyApps = SonyClient(http: http).applications(host: target.host, port: target.port, psk: target.psk)
            if !sonyApps.isEmpty { return sonyApps }
        }
        guard let serial = connectedSerial() else { return nil }
        let adb = client()
        if let text = try? adb.shell(["cat", AppIndex.launcherPath], serial: serial),
           let apps = AppIndex.parseLauncher(text), !apps.isEmpty {
            return apps
        }
        guard let query = try? adb.shell([
            "cmd", "package", "query-activities",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.LEANBACK_LAUNCHER"
        ], serial: serial) else { return nil }
        let found = AppIndex.parseLeanback(query)
        guard !found.isEmpty else { return nil }
        return found.map { app in
            if app.name != TvPicture.shortName(app.packageName) { return app }
            guard let dump = try? adb.shell(["cmd", "package", "dump", app.packageName], serial: serial),
                  let label = AppIndex.label(in: dump) else { return app }
            return TvApp(id: app.id, name: label, packageName: app.packageName, favourite: false)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func launch(_ app: TvApp) -> ActionReport {
        if let uri = app.uri, let target = sonyCredentials() {
            if SonyClient(http: http).setActiveApp(uri: uri, host: target.host, port: target.port, psk: target.psk) {
                return ActionReport(title: "Opening \(app.name)", detail: "Sony IP", isError: false)
            }
        }
        let packageName = app.packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PackageName.isValid(packageName) else {
            return ActionReport(
                title: "\(app.name) needs a package name",
                detail: "Edit it in Settings. It looks like com.example.app.",
                isError: true
            )
        }
        guard let serial = connectedSerial() else {
            if sonyCredentials() != nil {
                return ActionReport(
                    title: "Apps need adb",
                    detail: "Sony IP control doesn't launch Android apps. Connect network debugging.",
                    isError: true
                )
            }
            return notConnectedReport()
        }
        do {
            try client().launchApp(packageName: packageName, serial: serial)
            return ActionReport(title: "Opening \(app.name)", detail: packageName, isError: false)
        } catch {
            return ActionReport(
                title: "\(app.name) didn't open",
                detail: "Is \(packageName) installed on the TV? \(errorText(error))",
                isError: true
            )
        }
    }

    /// Prefer Sony's power status when a pre-shared key is saved. Otherwise wake over adb, then Wake-on-LAN.
    /// Power on: Sony setPowerStatus, then Wake-on-LAN, then adb KEYCODE_WAKEUP, then re-check.
    public func pressPower() -> ActionReport {
        var tried: [String] = []
        if setSonyPower(on: true) {
            tried.append("Sony IP")
        } else {
            let wol = sendWakeOnLan()
            if !wol.isError { tried.append("Wake-on-LAN") }
            if let serial = connectedSerial(), (try? client().keyEvent(.wakeup, serial: serial)) != nil {
                tried.append("adb wake")
            }
        }
        if let target = sonyCredentials() {
            let sony = SonyClient(http: http)
            for _ in 0..<4 {
                Thread.sleep(forTimeInterval: 1.5)
                if sony.powerStatus(host: target.host, port: target.port, psk: target.psk) == .on {
                    lock.critical { picture.power = .on }
                    return report("TV is on", tried.joined(separator: " → "), error: false)
                }
            }
        }
        if tried.isEmpty {
            return report("Couldn't wake the TV", "Sony IP refused, no adb, no Wake-on-LAN. Turn on Remote Start on the TV.", error: true)
        }
        return report("Sent wake", tried.joined(separator: " → "), error: false)
    }

    public func pressSleep() -> ActionReport {
        if setSonyPower(on: false) {
            return report("Sent sleep", "Sony IP set the power off", error: false)
        }
        guard let serial = connectedSerial() else {
            return ActionReport(
                title: "The TV isn't reachable",
                detail: "Sleep needs a live adb connection. Wake-on-LAN can only turn the TV on.",
                isError: true
            )
        }
        do {
            try client().keyEvent(.sleep, serial: serial)
            return ActionReport(title: "Sent sleep", detail: "KEYCODE_SLEEP to \(serial)", isError: false)
        } catch {
            return ActionReport(title: "Couldn't sleep the TV", detail: errorText(error), isError: true)
        }
    }

    private func sendWakeOnLan() -> ActionReport {
        let snapshot = lock.critical { settings }
        if snapshot.wolEnabled {
            let mac = snapshot.macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard MACAddress.bytes(mac) != nil else {
                return ActionReport(
                    title: "Wake-on-LAN needs a MAC address",
                    detail: "The TV isn't reachable over adb. Add its MAC in Settings.",
                    isError: true
                )
            }
            let broadcast = snapshot.broadcastAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = broadcast.isEmpty ? "255.255.255.255" : broadcast
            do {
                try wol.send(mac: mac, broadcastHost: host, port: 9)
                // Unicast too: some routers drop broadcast to sleeping ports.
                try? wol.send(mac: mac, broadcastHost: snapshot.host, port: 9)
                let pretty = MACAddress.display(mac) ?? mac
                return ActionReport(title: "Sent Wake-on-LAN", detail: "Magic packet to \(pretty)", isError: false)
            } catch {
                return ActionReport(title: "Wake-on-LAN failed", detail: errorText(error), isError: true)
            }
        }
        if case .adbMissing(let message) = status {
            return ActionReport(title: "adb isn't installed", detail: message, isError: true)
        }
        return ActionReport(
            title: "The TV isn't reachable",
            detail: "Add its MAC address and turn on Wake-on-LAN to wake it from standby.",
            isError: true
        )
    }

    private func sendSony(_ key: AndroidKey) -> ActionReport? {
        guard let target = sonyTarget(),
              let button = SonyButton.forKey(key, isPlaying: lock.critical { picture.isPlaying }) else {
            return nil
        }
        let sony = SonyClient(http: http)
        if sony.sendIRCC(button, host: target.host, port: target.port, psk: target.psk) {
            noteSonySuccess()
            return report(key.spoken, "Sent over Sony IP", error: false)
        }
        noteSonyFailure()
        return nil
    }

    private func hdmiPort(in uri: String) -> Int? {
        guard let range = uri.range(of: "port=") else { return nil }
        let digits = uri[range.upperBound...].prefix(while: \.isNumber)
        return Int(digits)
    }

    private func sendSonyPlay(uri: String) -> Bool {
        guard let target = sonyCredentials() else { return false }
        let sony = SonyClient(http: http)
        if sony.play(uri: uri, host: target.host, port: target.port, psk: target.psk) {
            noteSonySuccess()
            return true
        }
        noteSonyFailure()
        return false
    }

    private func setSonyPower(on: Bool) -> Bool {
        guard let target = sonyCredentials() else { return false }
        let sony = SonyClient(http: http)
        if sony.setPower(on: on, host: target.host, port: target.port, psk: target.psk) {
            noteSonySuccess()
            lock.critical { picture.power = on ? .on : .off }
            return true
        }
        noteSonyFailure()
        return false
    }

    private func sonyCredentials() -> (host: String, port: Int, psk: String)? {
        let snapshot = lock.critical { (settings.host, settings.sonyPort, preSharedKey) }
        let psk = snapshot.2.trimmingCharacters(in: .whitespacesAndNewlines)
        if psk.isEmpty || snapshot.0.isEmpty { return nil }
        return (snapshot.0, snapshot.1, psk)
    }

    /// Skips Sony for a few seconds after a failed button so a dead IP path doesn't stall every arrow.
    private func sonyTarget() -> (host: String, port: Int, psk: String)? {
        guard let credentials = sonyCredentials() else { return nil }
        let blocked = lock.critical { sonyBlockedUntil }
        if Date() < blocked { return nil }
        return credentials
    }

    private func noteSonySuccess() {
        lock.critical {
            sonyBlockedUntil = .distantPast
            picture.sonyReady = true
        }
    }

    private func noteSonyFailure() {
        lock.critical { sonyBlockedUntil = Date().addingTimeInterval(RefreshCadence.whileOpen) }
    }

    private func report(_ title: String, _ detail: String, error: Bool) -> ActionReport {
        ActionReport(title: scrub(title), detail: scrub(detail), isError: error)
    }

    private func scrub(_ text: String) -> String {
        let secret = lock.critical { preSharedKey }
        return SecretRedaction.scrub(text, secret: secret)
    }

    private func notConnectedReport() -> ActionReport {
        let current = lock.critical { status }
        return ActionReport(title: current.title, detail: current.detail, isError: true)
    }

    private func connectedSerial() -> String? {
        let current = lock.critical { status }
        guard case .connected(let serial) = current else { return nil }
        return serial
    }

    private func client() -> AdbClient {
        let path = lock.critical { settings.adbPath }
        let locator = AdbLocator(
            candidatePaths: AdbLocator.defaultCandidates(homeDirectory: homeDirectory),
            pathEnvironment: pathEnvironment,
            fileExists: fileExists
        )
        let custom = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = locator.resolve(customPath: custom.isEmpty ? nil : custom) ?? custom
        return AdbClient(runner: runner, adbPath: resolved)
    }

    private func assign(_ newStatus: LinkStatus) -> LinkStatus {
        lock.lock()
        status = newStatus
        lock.unlock()
        return newStatus
    }

    private func errorText(_ error: Error) -> String {
        if let remote = error as? RemoteError {
            return scrub(remote.description)
        }
        return "The command failed."
    }
}

private extension NSLock {
    func critical<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
