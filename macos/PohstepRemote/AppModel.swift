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

    let session: RemoteSession
    let store: SettingsStore
    let hotkey = Hotkey.default

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
    var onKeyboardModeChanged: ((Bool) -> Void)?
    var onChromeChanged: (() -> Void)?
    private var hudItem: DispatchWorkItem?

    init() {
        let store = SettingsStore(url: Settings.applicationSupportURL())
        let loaded = store.load()
        self.store = store
        self.settings = loaded.settings
        self.keyboardMode = loaded.settings.keyboardMode
        self.status = .idle
        self.picture = TvPicture()
        self.pskSaved = false
        if let saved = AppCatalogStore(url: AppCatalogStore.fileURL()).load() {
            self.shownApps = saved
            self.appsFromSavedCatalog = true
        } else {
            self.shownApps = loaded.settings.apps
            self.appsFromSavedCatalog = false
        }
        self.appsLoading = false
        self.volumeHUD = nil
        self.banner = loaded.warning ?? ""
        self.bannerIsError = loaded.warning != nil
        self.session = RemoteSession(settings: loaded.settings, runner: ShellRunner(), hotkey: .default)
        let savedKey = secrets.load()
        pskSaved = !savedKey.isEmpty
        session.setPreSharedKey(savedKey)
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
            try secrets.save(trimmed)
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
        secrets.clear()
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
            window.title = "Pohstep Remote Settings"
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
