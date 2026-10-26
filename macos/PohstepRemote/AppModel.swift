import AppKit
import SwiftUI

final class AppModel: ObservableObject {
    @Published var settings: Settings
    @Published var status: LinkStatus
    @Published var keyboardMode: Bool
    @Published var banner: String
    @Published var bannerIsError: Bool
    @Published var picture: TvPicture
    @Published var pskSaved: Bool
    @Published var shownApps: [TvApp]
    @Published var appsLoading: Bool
    @Published var appsFromSavedCatalog: Bool
    @Published var volumeHUD: String?
    /// More apps: the panel grows to show every app.
    @Published var appsExpanded = false
    @Published var wizard = SetupWizard()
    @Published var discovered: [DiscoveredTV] = []
    @Published var discovering = false
    @Published var typeFocusID = 0

    let session: RemoteSession
    let store: SettingsStore
    let hotkey = Hotkey.default
    let typeHotkey = Hotkey.typeDefault

    private var failures = 0
    private var refreshInFlight = false
    private var panelVisible = false
    private var timer: Timer?
    private var flushItem: DispatchWorkItem?
    private let policy = ReconnectPolicy()
    private let settingsKey = Flag()
    private let secrets = KeychainStore()
    private let catalogStore = AppCatalogStore(url: AppCatalogStore.fileURL())
    private var appsFresh = false

    var settingsWindow: NSWindow?
    var wizardWindow: NSWindow?
    var onKeyboardModeChanged: ((Bool) -> Void)?
    var onChromeChanged: (() -> Void)?
    var onOpenPanel: (() -> Void)?
    private var hudItem: DispatchWorkItem?
    private var pendingKey = ""
    private var lastSeenWrite = Date.distantPast

    var allowsKeyboardCapture: Bool {
        if BuildMode.sandbox { return false }
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil { return false }
        return true
    }

    var shouldOfferSetup: Bool {
        settings.devices.isEmpty && settings.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        let store = SettingsStore(url: Settings.resolvedSettingsURL())
        let loaded = store.load()
        var initial = loaded.settings
        let switcher = DeviceSwitcher(devices: initial.devices, activeID: initial.activeDeviceID)
        if let target = switcher.reconnectTarget() {
            initial = initial.applying(target)
        }
        self.store = store
        self.settings = initial
        self.keyboardMode = initial.keyboardMode
        self.status = .idle
        self.picture = TvPicture()
        self.pskSaved = false
        if let saved = AppCatalogStore(url: AppCatalogStore.fileURL()).load() {
            self.shownApps = saved
            self.appsFromSavedCatalog = true
        } else {
            self.shownApps = initial.apps
            self.appsFromSavedCatalog = false
        }
        self.appsLoading = false
        self.volumeHUD = nil
        self.banner = loaded.warning ?? ""
        self.bannerIsError = loaded.warning != nil
        let bundled = (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Helpers/adb")
        self.session = RemoteSession(
            settings: initial,
            runner: ShellRunner(),
            hotkey: .default,
            bundledAdbPath: bundled,
            allowUserAdb: !BuildMode.sandbox,
            temporaryDirectory: NSTemporaryDirectory()
        )
        let savedKey = keyFromChain(deviceID: initial.activeDeviceID, deviceCount: initial.devices.count)
        pskSaved = !savedKey.isEmpty
        session.setPreSharedKey(savedKey)
        if !initial.devices.isEmpty {
            try? store.save(initial)
        }
        normalizeStoredAddress()
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible {
            refreshNow()
        } else {
            schedule()
        }
    }

    func savePreSharedKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            banner = "Enter the pre-shared key from the TV, or leave it blank to use adb only."
            bannerIsError = true
            return
        }
        do {
            try saveKey(trimmed, deviceID: settings.activeDeviceID)
            pskSaved = true
            session.setPreSharedKey(trimmed)
            banner = "Pre-shared key saved in the Keychain."
            bannerIsError = false
            refreshNow()
        } catch {
            banner = "The Keychain didn't save the key."
            bannerIsError = true
        }
    }

    func clearPreSharedKey() {
        secrets.clear(account: secrets.account(for: settings.activeDeviceID))
        if settings.activeDeviceID == "legacy" || settings.devices.count <= 1 {
            secrets.clear()
        }
        pskSaved = false
        session.setPreSharedKey("")
        banner = "Pre-shared key removed from the Keychain."
        bannerIsError = false
        refreshNow()
    }

    func start() {
        refreshNow()
    }

    var settingsFieldsAreActive: Bool {
        settingsKey.value
    }

    func setSettingsKey(_ isKey: Bool) {
        settingsKey.value = isKey
    }

    func commitAddress() {
        let parsed = HostInput.normalize(settings.host)
        settings.host = parsed.host
        if let port = parsed.port {
            settings.port = port
        }
        if !(1...65535).contains(settings.port) {
            settings.port = 5555
        }
        pushSettings()
    }

    /// Updates the fields on screen without reconnecting. Address edits commit on submit.
    func editDraft(_ body: (inout Settings) -> Void) {
        body(&settings)
    }

    func update(_ body: (inout Settings) -> Void) {
        body(&settings)
        pushSettings()
    }

    func pushSettings() {
        if let index = settings.devices.firstIndex(where: { $0.id == settings.activeDeviceID }) {
            settings.devices[index].host = settings.host
            settings.devices[index].port = settings.port
            settings.devices[index].macAddress = settings.macAddress
            settings.devices[index].brand = settings.brand
            settings.devices[index].useDebugging = settings.useDebugging
            if settings.brand == .sony {
                settings.devices[index].controlPort = settings.sonyPort
            }
        }
        session.replaceSettings(settings)
        keyboardMode = settings.keyboardMode
        try? store.save(settings)
        onKeyboardModeChanged?(keyboardMode)
    }

    var appsCaption: String {
        let connecting: Bool
        if case .connecting = status { connecting = true } else { connecting = false }
        return AppListCaption.text(
            loading: appsLoading,
            appsEmpty: shownApps.isEmpty,
            savedCatalog: appsFromSavedCatalog,
            connected: status.isConnected,
            connecting: connecting
        )
    }

    func refreshNow() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let shouldReadApps = !appsFresh
        if shouldReadApps {
            appsLoading = true
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let status = self.session.refresh()
            let picture = self.session.refreshPicture()
            let apps = (status.isConnected && shouldReadApps) ? self.session.readApps() : nil
            DispatchQueue.main.async {
                self.status = status
                self.picture = picture
                if !self.settingsFieldsAreActive {
                    self.settings.host = self.session.settings.host
                    self.settings.port = self.session.settings.port
                }
                if status.isConnected {
                    if shouldReadApps {
                        self.appsFresh = true
                        if let apps, !apps.isEmpty {
                            self.applyLiveApps(apps)
                        }
                    }
                } else {
                    self.appsFresh = false
                }
                self.appsLoading = false
                self.failures = status.isConnected ? 0 : self.failures + 1
                if status.isConnected { self.noteSeen() }
                self.refreshInFlight = false
                self.schedule()
                self.onChromeChanged?()
            }
        }
    }

    func showVolumeHUD(_ text: String) {
        let reveal = volumeHUD == nil
        volumeHUD = text
        hudItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.volumeHUD = nil
            self?.onChromeChanged?()
        }
        hudItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
        if reveal { onChromeChanged?() }
    }

    func selectInput(_ input: BraviaInput) {
        run { $0.selectInput(uri: input.uri) }
    }

    private func applyLiveApps(_ apps: [TvApp]) {
        shownApps = apps
        appsFromSavedCatalog = false
        settings.apps = apps
        try? catalogStore.save(apps)
        if !settingsFieldsAreActive {
            session.replaceSettings(settings)
            try? store.save(settings)
        }
    }

    func toggleKeyboardMode() {
        let turningOn = !keyboardMode
        session.setKeyboardMode(turningOn)
        settings.keyboardMode = turningOn
        keyboardMode = turningOn
        try? store.save(settings)
        banner = ""
        bannerIsError = false
        onKeyboardModeChanged?(turningOn)
        onChromeChanged?()
    }

    func deliver(_ result: IngestResult) {
        switch result {
        case .ignored, .passthrough:
            break
        case .toggled(let on):
            settings.keyboardMode = on
            keyboardMode = on
            try? store.save(settings)
            banner = ""
            bannerIsError = false
            onKeyboardModeChanged?(on)
            onChromeChanged?()
        case .buffered:
            scheduleFlush()
        case .flushAndSend(let text, let action):
            flushItem?.cancel()
            if !text.isEmpty {
                performText(text)
            }
            perform(action)
        case .send(let action):
            perform(action)
        }
    }

    func press(_ key: AndroidKey) {
        run { $0.press(key) }
    }

    func launch(_ app: TvApp) {
        run { $0.launch(app) }
    }

    func wake() {
        run { $0.pressPower() }
    }

    func sleep() {
        run { $0.pressSleep() }
    }

    func selectHdmi(_ port: Int) {
        run { $0.selectHdmi(port) }
    }

    func setVolume(_ level: Int) {
        run { $0.setVolume(level) }
    }

    func openTvSettings() {
        launch(TvApp(id: "settings", name: "Settings", packageName: "com.android.tv.settings"))
    }

    func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingView(rootView: SettingsView(model: self))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Zapbar Settings"
            window.contentView = hosting
            AppearanceLock.apply(to: hosting)
            AppearanceLock.apply(to: window)
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier("pohstep.settings")
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setSettingsKey(true)
    }

    func settingsWindowClosed() {
        commitAddress()
        setSettingsKey(false)
    }

    func openTypeField() {
        onOpenPanel?()
        typeFocusID += 1
    }

    func sendTypedText(_ text: String) {
        guard !text.isEmpty else { return }
        run { $0.type(text) }
    }

    func selectDevice(_ id: String) {
        var switcher = DeviceSwitcher(devices: settings.devices, activeID: settings.activeDeviceID)
        switcher.select(id, seenAt: Date())
        settings.devices = switcher.devices
        settings.activeDeviceID = switcher.activeID
        if let active = switcher.active() {
            settings = settings.applying(active)
        }
        let key = keyFromChain(deviceID: settings.activeDeviceID, deviceCount: settings.devices.count)
        session.setPreSharedKey(key)
        pskSaved = !key.isEmpty
        pushSettings()
        refreshNow()
    }

    func preferDevice(_ id: String) {
        var switcher = DeviceSwitcher(devices: settings.devices, activeID: settings.activeDeviceID)
        switcher.setPreferred(id)
        settings.devices = switcher.devices
        pushSettings()
    }

    func showWizard() {
        wizard = SetupWizard()
        discovered = []
        pendingKey = ""
        if wizardWindow == nil {
            let hosting = NSHostingView(rootView: SetupWizardView(model: self))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Zapbar"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier("zapbar.setup")
            window.center()
            wizardWindow = window
        }
        wizardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWizard() {
        wizardWindow?.orderOut(nil)
    }

    func stagePreSharedKey(_ value: String) {
        pendingKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sendWizard(_ event: WizardEvent) {
        let effect = wizard.handle(event)
        if case .choose = event {
            discoverTVs()
        }
        switch effect {
        case .none:
            break
        case .pairAndConnect(let host, let pairPort, let code, let connectPort):
            runPair(host: host, pairPort: pairPort, code: code, connectPort: connectPort)
        case .connectLegacy(let host, let port):
            beginLegacyConnect(host: host, port: port)
        case .save(let device):
            remember(device)
        }
    }

    func retryAllow() {
        beginLegacyConnect(host: wizard.host, port: wizard.port)
    }

    private func discoverTVs() {
        discovering = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = self?.runDiscovery() ?? []
            DispatchQueue.main.async {
                self?.discovered = found
                self?.discovering = false
            }
        }
    }

    private func runDiscovery() -> [DiscoveredTV] {
        let http = URLSessionHttp()
        let coordinator = DiscoveryCoordinator(
            listing: BonjourListing(),
            prober: LiveSubnetProbe(http: http, reader: http),
            localAddresses: IPv4Interfaces.addresses()
        )
        return coordinator.find().found
    }

    private func runPair(host: String, pairPort: Int, code: String, connectPort: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = self.session.pairAndConnect(host: host, pairPort: pairPort, code: code, connectPort: connectPort)
            DispatchQueue.main.async {
                if report.isError {
                    _ = self.wizard.handle(.pairFailed(report.detail.isEmpty ? report.title : report.detail))
                } else {
                    self.update { settings in
                        settings.host = host
                        settings.port = connectPort
                        settings.useDebugging = true
                        settings.brand = self.wizard.brand ?? .generic
                    }
                    _ = self.wizard.handle(.pairSucceeded)
                }
            }
        }
    }

    private func beginLegacyConnect(host: String, port: Int) {
        update { settings in
            settings.host = host
            settings.port = port
            settings.useDebugging = true
            settings.brand = self.wizard.brand ?? .generic
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let status = self.session.refresh()
            DispatchQueue.main.async {
                self.status = status
                switch status {
                case .connected:
                    _ = self.wizard.handle(.allowAccepted)
                case .unauthorized:
                    _ = self.wizard.handle(.allowWaiting)
                default:
                    _ = self.wizard.handle(.connectFailed(status.detail))
                }
            }
        }
    }

    private func remember(_ device: StoredTV) {
        var switcher = DeviceSwitcher(devices: settings.devices, activeID: settings.activeDeviceID)
        switcher.remember(device, seenAt: Date())
        settings.devices = switcher.devices
        settings.activeDeviceID = switcher.activeID
        if let active = switcher.active() {
            settings = settings.applying(active)
        }
        if !pendingKey.isEmpty {
            try? saveKey(pendingKey, deviceID: settings.activeDeviceID)
            session.setPreSharedKey(pendingKey)
            pskSaved = true
            pendingKey = ""
        } else {
            let key = keyFromChain(deviceID: settings.activeDeviceID, deviceCount: settings.devices.count)
            session.setPreSharedKey(key)
            pskSaved = !key.isEmpty
        }
        pushSettings()
        refreshNow()
    }

    private func noteSeen() {
        let id = settings.activeDeviceID
        guard !id.isEmpty else { return }
        if Date().timeIntervalSince(lastSeenWrite) < 60 { return }
        lastSeenWrite = Date()
        var switcher = DeviceSwitcher(devices: settings.devices, activeID: id)
        switcher.touch(id, date: Date())
        settings.devices = switcher.devices
        try? store.save(settings)
    }

    private func keyFromChain(deviceID: String, deviceCount: Int) -> String {
        let specific = secrets.load(account: secrets.account(for: deviceID))
        if !specific.isEmpty { return specific }
        if deviceID.isEmpty || deviceID == "legacy" || deviceCount <= 1 {
            return secrets.load()
        }
        return ""
    }

    private func saveKey(_ value: String, deviceID: String) throws {
        try secrets.save(value, account: secrets.account(for: deviceID))
        if deviceID == "legacy" || deviceID.isEmpty || settings.devices.count <= 1 {
            try secrets.save(value)
        }
    }

    private func normalizeStoredAddress() {
        let parsed = HostInput.normalize(settings.host)
        if parsed.host != settings.host || parsed.port != nil {
            settings.host = parsed.host
            if let port = parsed.port {
                settings.port = port
            }
            pushSettings()
        }
    }

    private func scheduleFlush() {
        flushItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.session.flushTyping()
            if !text.isEmpty {
                self.performText(text)
            }
        }
        flushItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func perform(_ action: RemoteAction) {
        switch action {
        case .key(let key):
            press(key)
        case .text(let text):
            performText(text)
        case .launch(let packageName, let displayName):
            launch(TvApp(id: packageName, name: displayName, packageName: packageName))
        }
    }

    private func performText(_ text: String) {
        run { $0.type(text) }
    }

    private func run(_ work: @escaping (RemoteSession) -> ActionReport) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = work(self.session)
            DispatchQueue.main.async {
                if report.isError && !report.title.isEmpty {
                    self.banner = report.detail.isEmpty ? report.title : "\(report.title). \(report.detail)"
                    self.bannerIsError = true
                } else if !report.isError {
                    self.banner = ""
                    self.bannerIsError = false
                }
            }
        }
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        let delay: TimeInterval
        if panelVisible {
            delay = RefreshCadence.whileOpen
        } else if keyboardMode {
            delay = policy.delay(for: status, failures: failures)
        } else {
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refreshNow()
        }
    }
}

final class Flag {
    private let lock = NSLock()
    private var stored = false

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}
