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
    private let reader: any HttpReading
    private let fileExists: (String) -> Bool
    private let pathEnvironment: String
    private let homeDirectory: String
    private let bundledAdbPath: String?
    private let allowUserAdb: Bool
    private let temporaryDirectory: String
    private let adbServerSocket: String
    private let lock = NSLock()
    private var typing = ""
    private var preSharedKey = ""
    private var picture = TvPicture()
    private var sonyBlockedUntil = Date.distantPast
    private var adbLink = false
    private var cancelFlag = false
    private var transferRemote: String?
    var powerSleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var powerNow: () -> Date = Date.init

    public init(
        settings: Settings,
        runner: any CommandRunning,
        wol: any WakeOnLanSending = WakeOnLanSender(),
        http: any HttpSending = URLSessionHttp(),
        reader: (any HttpReading)? = nil,
        hotkey: Hotkey = .default,
        fileExists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        homeDirectory: String = NSHomeDirectory(),
        bundledAdbPath: String? = nil,
        allowUserAdb: Bool = true,
        temporaryDirectory: String? = nil,
        adbServerSocket: String = AdbLaunch.defaultServerSocket
    ) {
        self.settings = settings
        self.status = .idle
        self.keyboardMode = settings.keyboardMode
        self.hotkey = hotkey
        self.runner = runner
        self.wol = wol
        self.http = http
        if let reader {
            self.reader = reader
        } else if let reading = http as? HttpReading {
            self.reader = reading
        } else {
            self.reader = UnavailableReader()
        }
        self.fileExists = fileExists
        self.pathEnvironment = pathEnvironment
        self.homeDirectory = homeDirectory
        self.bundledAdbPath = bundledAdbPath
        self.allowUserAdb = allowUserAdb
        self.temporaryDirectory = temporaryDirectory ?? FileManager.default.temporaryDirectory.path
        self.adbServerSocket = adbServerSocket
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

    public func ingest(_ chord: KeyChord, textFieldFocused: Bool = false) -> IngestResult {
        lock.lock()
        let mode = keyboardMode
        let effect = KeyMapping.effect(
            for: chord,
            keyboardMode: mode,
            hotkey: hotkey,
            textFieldFocused: textFieldFocused
        )
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

    /// `adb pair` then `adb connect`. Used by the setup wizard for wireless debugging.
    public func pairAndConnect(host: String, pairPort: Int, code: String, connectPort: Int) -> ActionReport {
        guard let adb = resolvedAdbPath() else {
            return ActionReport(title: "Couldn't pair", detail: Copy.adbMissing(), isError: true)
        }
        let client = makeClient(path: adb)
        do {
            let paired = try client.pair(host: host, port: pairPort, code: code)
            guard paired else {
                return ActionReport(title: "Couldn't pair", detail: "The TV didn't accept the pairing code.", isError: true)
            }
            let outcome = try client.connect(host: host, port: connectPort)
            if case .failed(let detail) = outcome {
                return ActionReport(title: "Paired, but not connected", detail: scrub(detail), isError: true)
            }
            return ActionReport(title: "Paired", detail: "\(host):\(connectPort)", isError: false)
        } catch {
            return ActionReport(title: "Couldn't pair", detail: errorText(error), isError: true)
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
        let brand = lock.critical { settings.brand }
        if brand == .xiaomi, !(1...65535).contains(port) {
            port = 6095
        } else if !(1...65535).contains(port) {
            port = 5555
        }

        lock.lock()
        settings.host = host
        settings.port = port
        let adbPathSetting = settings.adbPath
        let useDebugging = settings.useDebugging
        adbLink = false
        lock.unlock()

        if host.isEmpty {
            return assign(.idle)
        }
        if brand == .xiaomi {
            return refreshXiaomi(host: host, port: port)
        }
        if brand == .sony && !useDebugging {
            return refreshSonyOnly(host: host)
        }
        if !HostInput.isValidHost(host) {
            return assign(.failed(message: "\(host) isn't a usable address. Use an IP or a hostname."))
        }

        guard let adb = resolvedAdbPath(custom: adbPathSetting) else {
            let trimmed = adbPathSetting.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty ? Copy.adbMissing() : Copy.adbMissing(at: trimmed)
            return assign(.adbMissing(message: message))
        }

        let serial = "\(host):\(port)"
        _ = assign(.connecting(serial: serial))
        let client = makeClient(path: adb)

        do {
            let outcome = try client.connect(host: host, port: port)
            let listed = try client.listDevices()
            return finishConnect(
                AdbOutput.parseDevices(listed.combined, serial: serial),
                serial: serial,
                outcome: outcome,
                listing: listed.combined
            )
        } catch let error as RemoteError {
            if case .notFound = error {
                return assign(.adbMissing(message: Copy.adbMissing()))
            }
            if AdbOutput.isDaemonFailure(String(describing: error)) {
                return assign(.helperDown)
            }
            return assign(.unreachable(serial: serial))
        } catch {
            if AdbOutput.isDaemonFailure(String(describing: error)) {
                return assign(.helperDown)
            }
            return assign(.unreachable(serial: serial))
        }
    }

    /// Allow-wait. A TV that is already `device` is left alone. While it stays
    /// unauthorized, disconnect and connect the same address about every 3 seconds,
    /// stopping at `AllowReconnect.timeout`.
    public func reconnectUntilAuthorized(
        timeout: TimeInterval = AllowReconnect.timeout,
        interval: TimeInterval = AllowReconnect.interval,
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        now: @escaping () -> Date = Date.init
    ) -> LinkStatus {
        let endpoint = lock.critical { (settings.host, settings.port) }
        let host = endpoint.0
        let port = endpoint.1
        let serial = "\(host):\(port)"
        guard let adb = resolvedAdbPath() else {
            let trimmed = lock.critical { settings.adbPath }.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty ? Copy.adbMissing() : Copy.adbMissing(at: trimmed)
            return assign(.adbMissing(message: message))
        }
        let client = makeClient(path: adb)
        var lastOutcome = ConnectOutcome.connected
        var lastListing = ""

        func read() -> DeviceState {
            do {
                let listed = try client.listDevices()
                lastListing = listed.combined
                return AdbOutput.parseDevices(listed.combined, serial: serial)
            } catch {
                lastListing = String(describing: error)
                lastOutcome = .failed(lastListing)
                return .missing
            }
        }

        func reconnect() -> DeviceState {
            _ = try? client.disconnect(host: host, port: port)
            do {
                lastOutcome = try client.connect(host: host, port: port)
                let listed = try client.listDevices()
                lastListing = listed.combined
                return AdbOutput.parseDevices(listed.combined, serial: serial)
            } catch {
                lastListing = String(describing: error)
                lastOutcome = .failed(lastListing)
                return .missing
            }
        }

        let state = AllowReconnect.wait(
            timeout: timeout,
            interval: interval,
            sleep: sleep,
            now: now,
            read: read,
            reconnect: reconnect
        )
        return finishConnect(state, serial: serial, outcome: lastOutcome, listing: lastListing)
    }

    public func press(_ key: AndroidKey) -> ActionReport {
        let brand = lock.critical { settings.brand }
        return TvBackends.make(brand).sendKey(key, context: makeContext(allowSony: brand == .sony))
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
        let brand = lock.critical { settings.brand }
        if brand == .xiaomi || brand == .sony {
            return TvBackends.make(brand).selectHDMI(port, context: makeContext(allowSony: brand == .sony))
        }
        guard (1...4).contains(port) else {
            return ActionReport(title: "Unknown input", detail: "HDMI ports are 1 to 4.", isError: true)
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
        var sonyPower: PowerReading?
        if let target = sonyCredentials() {
            let sony = SonyClient(http: http)
            if let power = sony.powerStatus(host: target.host, port: target.port, psk: target.psk) {
                sonyPower = power
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
        var wakeDump: String?
        if currentAdbLink(), case .connected(let serial) = current {
            next.adbReady = true
            wakeDump = try? client().shell(["dumpsys", "power"], serial: serial)
            if let dump = try? client().shell(["dumpsys", "window"], serial: serial) {
                next.foregroundPackage = ScreenDump.foregroundPackage(dump)
            }
            if let dump = try? client().shell(["dumpsys", "media_session"], serial: serial),
               let playing = ScreenDump.nowPlaying(dump) {
                next.nowPlaying = TvApp.cleanName(playing.line)
                next.isPlaying = playing.isPlaying
            }
        }
        next.power = PowerMerge.choose(adbDump: wakeDump, sony: sonyPower)
        lock.critical { picture = next }
        return next
    }

    /// Text sent with Sony setTextForm since the last adb success (that call replaces the field).
    private var sonyField = ""

    public func type(_ text: String) -> ActionReport {
        guard !text.isEmpty else {
            return ActionReport(title: "", detail: "", isError: false)
        }
        let count = text.count
        let brand = lock.critical { settings.brand }
        let route = TypingRoute.choose(
            text: text,
            brand: brand,
            sonyAvailable: brand == .sony && sonyCredentials() != nil,
            adbAvailable: connectedSerial() != nil
        )
        switch route {
        case .adb:
            if let blocked = blockedByReadiness() { return blocked }
            let report = GenericTVBackend().sendText(text, context: makeContext(allowSony: false))
            if report.isError {
                NSLog("Zapbar: adb typing failed for %d chars", count)
            } else {
                NSLog("Zapbar: typed %d chars via adb", count)
            }
            return report
        case .sony:
            if let blocked = blockedByReadiness() { return blocked }
            let field = lock.critical { () -> String in sonyField += text; return sonyField }
            let report = SonyIPBackend().sendText(text, context: makeContext(allowSony: true, replacementText: field))
            if report.isError {
                lock.critical { sonyField = "" }
                NSLog("Zapbar: setTextForm refused %d chars", count)
            } else {
                NSLog("Zapbar: typed %d chars via Sony setTextForm", count)
            }
            return report
        case .unsupported(let message):
            return ActionReport(title: "Couldn't type", detail: message, isError: true)
        }
    }

    /// adb can see the keyboard. A Sony-only TV cannot; Sony's own refusal uses the same sentence.
    private func blockedByReadiness() -> ActionReport? {
        guard currentAdbLink(), let serial = connectedSerial() else { return nil }
        let dump = (try? client().shell(["dumpsys", "input_method"], serial: serial)) ?? ""
        guard TypingReadiness.reading(dump) == .notReady else { return nil }
        return ActionReport(title: "Couldn't type", detail: TypingReadiness.notReady, isError: true)
    }

    /// Launcher export first, then leanback activities. Nil when adb is not connected or both reads fail.
    public func readApps() -> [TvApp]? {
        if let target = sonyCredentials() {
            let sonyApps = SonyClient(http: http).applications(host: target.host, port: target.port, psk: target.psk)
            if !sonyApps.isEmpty { return sonyApps.map(namedApp) }
        }
        guard let serial = connectedSerial() else { return nil }
        let adb = client()
        if let text = try? adb.shell(["cat", AppIndex.launcherPath], serial: serial),
           let apps = AppIndex.parseLauncher(text), !apps.isEmpty {
            return apps.map(namedApp)
        }
        guard let query = try? adb.shell([
            "cmd", "package", "query-activities",
            "-a", "android.intent.action.MAIN",
            "-c", "android.intent.category.LEANBACK_LAUNCHER"
        ], serial: serial) else { return nil }
        let found = AppIndex.parseLeanback(query)
        guard !found.isEmpty else { return nil }
        return found.map { app in
            var label: String? = app.name
            if app.name == TvPicture.shortName(app.packageName),
               let dump = try? adb.shell(["cmd", "package", "dump", app.packageName], serial: serial),
               let foundLabel = AppIndex.label(in: dump) {
                label = foundLabel
            }
            return namedApp(app, label: label)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Background icon read. Does not hold the session lock across the pull.
    public func loadAppIcon(package: String, cacheDirectory: URL) -> URL? {
        guard PackageName.isValid(package) else { return nil }
        guard let serial = connectedSerial(), let path = resolvedAdbPath() else { return nil }
        var client = makeClient(path: path)
        client.timeout = AppIconFetch.timeout
        return AppIconFetch.fetch(package: package, serial: serial, client: client, cacheDirectory: cacheDirectory)
    }

    private func namedApp(_ app: TvApp) -> TvApp {
        namedApp(app, label: app.name)
    }

    private func namedApp(_ app: TvApp, label: String?) -> TvApp {
        let name = AppNames.displayName(package: app.packageName, label: label)
        if name == app.name { return app }
        return TvApp(
            id: app.id,
            name: name,
            packageName: app.packageName,
            favourite: app.favourite,
            uri: app.uri,
            iconURL: app.iconURL
        )
    }

    public func launch(_ app: TvApp) -> ActionReport {
        let brand = lock.critical { settings.brand }
        if brand == .xiaomi {
            let packageName = app.packageName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard PackageName.isValid(packageName) else {
                return ActionReport(
                    title: "\(app.name) needs a package name",
                    detail: "Edit it in Settings. It looks like com.example.app.",
                    isError: true
                )
            }
            return XiaomiTVBackend().launch(package: packageName, name: app.name, context: makeContext(allowSony: false))
        }
        if brand == .sony, let uri = app.uri, let target = sonyCredentials() {
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
                    detail: "IP control doesn't launch apps. Connect network debugging.",
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

    /// Stops the adb server for this app. Waits at most `AdbLaunch.quitWait`, then returns.
    public func stopAdbServer() {
        guard let path = resolvedAdbPath() else { return }
        makeClient(path: path).killServer()
    }

    /// Terminates the adb process for the current install or push. The job removes a partial remote file.
    public func cancelTransfer() {
        lock.lock()
        cancelFlag = true
        lock.unlock()
        runner.cancel()
    }

    public func installApk(at path: String, clearingCancel: Bool = true) -> JobReport {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ApkPick.isApk(trimmed) else {
            return JobReport(sentence: ApkPick.onlyApk, raw: "", isError: true)
        }
        guard FileManager.default.fileExists(atPath: trimmed) else {
            return JobReport(sentence: "That file can't be read.", raw: "", isError: true)
        }
        guard let serial = debuggingSerial() else {
            return debuggingRequired()
        }
        armTransfer(remote: nil, resetCancel: clearingCancel)
        defer { endTransfer() }
        let client = client()
        if let blocked = prepareTransfer(client: client, serial: serial) { return blocked }
        if wasCancelled() { return cancelledJob() }
        do {
            let result = try client.installPackage(at: trimmed, serial: serial)
            if wasCancelled() { return cancelledJob() }
            let raw = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
            let sentence = InstallExplain.sentence(status: result.status, output: raw)
            let failed = sentence != "Installed."
            return JobReport(sentence: sentence, raw: raw, isError: failed)
        } catch {
            if wasCancelled() { return cancelledJob() }
            return failureJob(error)
        }
    }

    public func captureScreenshot() -> ScreenshotResult {
        guard let serial = debuggingSerial() else {
            return ScreenshotResult(png: nil, sentence: "This needs a network debugging connection.", raw: "", isError: true)
        }
        armTransfer(remote: nil, resetCancel: true)
        defer { endTransfer() }
        let client = client()
        if let blocked = prepareTransfer(client: client, serial: serial) {
            return ScreenshotResult(png: nil, sentence: blocked.sentence, raw: blocked.raw, isError: true)
        }
        if wasCancelled() { return cancelledScreenshot() }
        // adb says Asleep or Dozing: stop here instead of waiting for a capture that never comes.
        if let dump = try? client.shell(["dumpsys", "power"], serial: serial), Wakefulness.reading(dump) == .off {
            return ScreenshotResult(png: nil, sentence: ScreenshotCapture.asleep, raw: "", isError: true)
        }
        let execData: Data
        let execRaw: String
        do {
            let exec = try client.captureScreen(serial: serial)
            if wasCancelled() { return cancelledScreenshot() }
            execData = exec.stdoutData
            execRaw = exec.combined
        } catch {
            if wasCancelled() { return cancelledScreenshot() }
            execData = Data()
            execRaw = safeDetail(error)
        }
        let result = ScreenshotCapture.resolve(execOut: execData, fallbackRaw: execRaw) {
            self.pullScreenshot(client: client, serial: serial)
        }
        if wasCancelled() { return cancelledScreenshot() }
        return result
    }

    /// Turn on: adb wake, then Sony, then a magic packet. One fallback only. The button is usable when this returns.
    public func pressPower() -> ActionReport {
        if lock.critical({ settings.brand }) == .xiaomi {
            return XiaomiTVBackend().power(on: true, context: makeContext(allowSony: false))
        }
        learnMacIfMissing()
        let attempt = PowerActions.turnOn(transport: self, sleep: powerSleep, now: powerNow)
        lock.critical { picture.power = attempt.power }
        return attempt.report
    }

    public func pressSleep() -> ActionReport {
        if lock.critical({ settings.brand }) == .xiaomi {
            return XiaomiTVBackend().power(on: false, context: makeContext(allowSony: false))
        }
        let attempt = PowerActions.turnOff(transport: self, sleep: powerSleep, now: powerNow)
        lock.critical { picture.power = attempt.power }
        return attempt.report
    }

    /// Fills a missing MAC from the neighbour table or the TV, and turns the packet on so Turn on can use it.
    private func learnMacIfMissing() {
        let snapshot = lock.critical { settings }
        if MACAddress.bytes(snapshot.macAddress) != nil { return }
        var found: String?
        if let result = try? runner.run("/usr/sbin/arp", arguments: ["-an"], timeout: 2) {
            found = MacSources.neighbour(result.stdout, host: snapshot.host)
        }
        if found == nil, currentAdbLink(), let serial = connectedSerial() {
            for path in ["/sys/class/net/wlan0/address", "/sys/class/net/eth0/address"] {
                if let text = try? client().shell(["cat", path], serial: serial),
                   let mac = MacSources.addressFile(text) {
                    found = mac
                    break
                }
            }
        }
        guard let found else { return }
        lock.critical {
            settings.macAddress = found
            settings.wolEnabled = true
            if let index = settings.devices.firstIndex(where: { $0.id == settings.activeDeviceID }) {
                settings.devices[index].macAddress = found
            }
        }
    }

    private func sendWakePacket() -> Bool {
        let snapshot = lock.critical { settings }
        let mac = snapshot.macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MACAddress.bytes(mac) != nil else { return false }
        let broadcast = MacSources.subnetBroadcast(host: snapshot.host, configured: snapshot.broadcastAddress)
        var targets = [broadcast]
        if snapshot.host != broadcast && !snapshot.host.isEmpty {
            targets.append(snapshot.host)
        }
        var sent = false
        for port: UInt16 in [9, 7] {
            for host in targets {
                if (try? wol.send(mac: mac, broadcastHost: host, port: port)) != nil {
                    sent = true
                }
            }
        }
        return sent
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
        guard lock.critical({ settings.brand }) == .sony else { return false }
        guard let target = sonyCredentials() else { return false }
        let sony = SonyClient(http: http)
        if sony.setPower(on: on, host: target.host, port: target.port, psk: target.psk) {
            noteSonySuccess()
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

    private func debuggingRequired() -> JobReport {
        JobReport(sentence: "This needs a network debugging connection.", raw: "", isError: true)
    }

    private func debuggingSerial() -> String? {
        guard currentAdbLink(), let serial = connectedSerial(), !serial.isEmpty else { return nil }
        return serial
    }

    private func pullScreenshot(client: AdbClient, serial: String) -> (Data, String) {
        let remote = ScreenshotCapture.remotePath
        let local = URL(fileURLWithPath: temporaryDirectory, isDirectory: true)
            .appendingPathComponent("zapbar-screen-\(UUID().uuidString).png")
            .path
        setTransferRemote(remote)
        defer {
            setTransferRemote(nil)
            try? FileManager.default.removeItem(atPath: local)
            _ = try? client.removeRemote(remote, serial: serial)
        }
        var raw = ""
        do {
            let saved = try client.saveScreenshot(remotePath: remote, serial: serial)
            raw += saved.combined
            let pulled = try client.pullFile(remotePath: remote, localPath: local, serial: serial)
            raw += pulled.combined
            let data = (try? Data(contentsOf: URL(fileURLWithPath: local))) ?? Data()
            return (data, raw.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (Data(), (raw + safeDetail(error)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func prepareTransfer(client: AdbClient, serial: String) -> JobReport? {
        if wasCancelled() { return cancelledJob() }
        do {
            let listed = try client.listDevices()
            if wasCancelled() { return cancelledJob() }
            switch AdbOutput.parseDevices(listed.combined, serial: serial) {
            case .device:
                return nil
            case .unauthorized:
                return JobReport(sentence: Copy.unauthorized(serial: serial), raw: "", isError: true)
            case .offline, .missing:
                return JobReport(sentence: Copy.offline(serial: serial), raw: "", isError: true)
            }
        } catch {
            if wasCancelled() { return cancelledJob() }
            return failureJob(error)
        }
    }

    private func failureJob(_ error: Error) -> JobReport {
        if isTimeout(error) {
            return JobReport(sentence: Copy.stoppedAnswering, raw: "", isError: true)
        }
        if let remote = error as? RemoteError, case .notFound = remote {
            return JobReport(sentence: Copy.adbMissing(), raw: "", isError: true)
        }
        let text = errorText(error)
        return JobReport(sentence: text, raw: text, isError: true)
    }

    private func cancelledJob() -> JobReport {
        JobReport(sentence: "Cancelled.", raw: "", isError: true)
    }

    private func cancelledScreenshot() -> ScreenshotResult {
        ScreenshotResult(png: nil, sentence: "Cancelled.", raw: "", isError: true)
    }

    private func isTimeout(_ error: Error) -> Bool {
        if let remote = error as? RemoteError, case .timedOut = remote { return true }
        return false
    }

    private func safeDetail(_ error: Error) -> String {
        if isTimeout(error) { return "" }
        if let remote = error as? RemoteError, case .notFound = remote { return "" }
        return errorText(error)
    }

    private func armTransfer(remote: String?, resetCancel: Bool) {
        lock.lock()
        if resetCancel { cancelFlag = false }
        transferRemote = remote
        lock.unlock()
    }

    private func endTransfer() {
        lock.lock()
        transferRemote = nil
        lock.unlock()
    }

    private func setTransferRemote(_ remote: String?) {
        lock.lock()
        transferRemote = remote
        lock.unlock()
    }

    private func wasCancelled() -> Bool {
        lock.lock()
        let value = cancelFlag
        if value { cancelFlag = false }
        lock.unlock()
        return value
    }

    private func connectedSerial() -> String? {
        let current = lock.critical { status }
        guard case .connected(let serial) = current else { return nil }
        return serial
    }

    private func refreshXiaomi(host: String, port: Int) -> LinkStatus {
        let serial = "\(host):\(port)"
        if XiaomiClient(reader: reader).alive(host: host, port: port) != nil {
            return assign(.connected(serial: serial))
        }
        return assign(.offline(serial: serial))
    }

    private func refreshSonyOnly(host: String) -> LinkStatus {
        guard let target = sonyCredentials() else {
            return assign(.failed(message: "Save the pre-shared key for this Sony TV."))
        }
        let serial = "\(host):\(target.port)"
        if SonyClient(http: http).powerStatus(host: target.host, port: target.port, psk: target.psk) != nil {
            return assign(.connected(serial: serial))
        }
        return assign(.offline(serial: serial))
    }

    private func makeContext(allowSony: Bool, replacementText: String = "") -> TvActionContext {
        let serial = connectedSerial()
        let adb = serial == nil ? nil : client()
        let snapshot = lock.critical { (settings, preSharedKey, picture.isPlaying) }
        let psk = snapshot.1.trimmingCharacters(in: .whitespacesAndNewlines)
        let sonyAllowed = allowSony && sonyTarget() != nil
        return TvActionContext(
            host: snapshot.0.host,
            adbPort: snapshot.0.port,
            controlPort: snapshot.0.brand == .sony ? snapshot.0.sonyPort : (snapshot.0.brand == .xiaomi ? snapshot.0.port : snapshot.0.port),
            psk: psk,
            serial: serial,
            adb: adb,
            http: http,
            reader: reader,
            isPlaying: snapshot.2,
            allowSony: sonyAllowed,
            replacementText: replacementText,
            onSonySuccess: { [weak self] in self?.noteSonySuccess() },
            onSonyFailure: { [weak self] in self?.noteSonyFailure() },
            scrub: { [weak self] text in self?.scrub(text) ?? text },
            notConnected: { [weak self] in self?.notConnectedReport() ?? ActionReport(title: "Couldn't connect", detail: "", isError: true) },
            failureDetail: { [weak self] error in self?.errorText(error) ?? "The command failed." }
        )
    }

    private func resolvedAdbPath(custom: String? = nil) -> String? {
        let path = custom ?? lock.critical { settings.adbPath }
        let locator = AdbLocator(
            candidatePaths: AdbLocator.defaultCandidates(homeDirectory: homeDirectory),
            pathEnvironment: pathEnvironment,
            fileExists: fileExists,
            bundledHelperPath: bundledAdbPath,
            allowUserInstall: allowUserAdb
        )
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return locator.resolve(customPath: trimmed.isEmpty ? nil : trimmed)
    }

    private func makeClient(path: String) -> AdbClient {
        AdbClient(
            runner: runner,
            adbPath: path,
            temporaryDirectory: temporaryDirectory,
            serverSocket: adbServerSocket
        )
    }

    private func client() -> AdbClient {
        let resolved = resolvedAdbPath() ?? ""
        return makeClient(path: resolved)
    }

    private func currentAdbLink() -> Bool {
        lock.critical { adbLink }
    }

    private func finishConnect(_ state: DeviceState, serial: String, outcome: ConnectOutcome, listing: String) -> LinkStatus {
        switch state {
        case .device:
            lock.critical { adbLink = true }
            return assign(.connected(serial: serial))
        case .unauthorized:
            return assign(.unauthorized(serial: serial))
        case .offline:
            return assign(.offline(serial: serial))
        case .missing:
            if AdbOutput.isDaemonFailure(outcome.failureDetail) || AdbOutput.isDaemonFailure(listing) {
                return assign(.helperDown)
            }
            if AdbOutput.isRefusal(outcome.failureDetail) {
                return assign(.refused(serial: serial, detail: Copy.refused(serial: serial)))
            }
            return assign(.unreachable(serial: serial))
        }
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

extension RemoteSession: PowerTransport {
    public var adbCanPressPower: Bool {
        currentAdbLink() && connectedSerial() != nil
    }

    public var sonyCanPressPower: Bool {
        sonyCredentials() != nil
    }

    public var canWakeOnLan: Bool {
        let snapshot = lock.critical { settings }
        return snapshot.wolEnabled && MACAddress.bytes(snapshot.macAddress) != nil
    }

    public func readPower() -> PowerReading {
        var sony: PowerReading?
        if let target = sonyCredentials() {
            sony = SonyClient(http: http).powerStatus(host: target.host, port: target.port, psk: target.psk)
        }
        var dump: String?
        if currentAdbLink(), let serial = connectedSerial() {
            dump = try? client().shell(["dumpsys", "power"], serial: serial)
        }
        let merged = PowerMerge.choose(adbDump: dump, sony: sony)
        lock.critical { picture.power = merged }
        return merged
    }

    public func run(_ step: PowerStep) -> Bool {
        switch step {
        case .adbWake:
            guard let serial = connectedSerial(), currentAdbLink() else { return false }
            return (try? client().keyEvent(.wakeup, serial: serial)) != nil
        case .adbSleep:
            guard let serial = connectedSerial(), currentAdbLink() else { return false }
            return (try? client().keyEvent(.sleep, serial: serial)) != nil
        case .sonyOn:
            return setSonyPower(on: true)
        case .sonyOff:
            return setSonyPower(on: false)
        case .wakeOnLan:
            return sendWakePacket()
        }
    }
}

#if ZAPBAR_ADVANCED
extension RemoteSession {
    /// Debugging connection for clean-up. Nil when this TV is not on a debugging link.
    public func cleanupConnection() -> (client: AdbClient, serial: String)? {
        guard let serial = debuggingSerial(), !serial.isEmpty else { return nil }
        guard resolvedAdbPath() != nil else { return nil }
        return (client(), serial)
    }
}
#endif

private extension NSLock {
    func critical<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
