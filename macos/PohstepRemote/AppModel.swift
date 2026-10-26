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
    @Published var linkFocusID = 0
    @Published var jobLine = ""
    @Published var jobRaw = ""
    @Published var jobIsError = false
    @Published var jobBusy = false
    @Published var jobCancellable = false
    @Published var screenshotPNG: Data?
    @Published var demoOn = false
    @Published var demoNote = ""
    #if ZAPBAR_ADVANCED
    @Published var advancedExpanded = false
    @Published var cleanupEnabled = false
    @Published var cleanupRows: [CleanupRow] = []
    @Published var cleanupWarnings: [CleanupRow] = []
    @Published var cleanupUndo: [String] = []
    @Published var cleanupLine = ""
    @Published var cleanupBusy = false
    var cleanupExtras: [String] = []
    #endif

    let session: RemoteSession
    private let demo = DemoSession()
    let store: SettingsStore
    let hotkey = Hotkey.default
    let typeHotkey = Hotkey.typeDefault
    let linkHotkey = Hotkey.linkDefault

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
    private let transfers = TransferGate()
    private let stageLock = NSLock()
    private var pendingStage: [String] = []

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
        #if ZAPBAR_ADVANCED
        advancedExpanded = UserDefaults.standard.bool(forKey: "zapbar.advanced.expanded")
        cleanupEnabled = UserDefaults.standard.bool(forKey: "zapbar.cleanup.enabled")
        #endif
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
        let id = settings.activeDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        #if ZAPBAR_MIGRATE_V1 && !SANDBOX_BUILD
        secrets.clear(account: secrets.account(for: id))
        if id == "legacy" || id.isEmpty || settings.devices.count <= 1 {
            secrets.clear()
        }
        #else
        if !id.isEmpty, id != "legacy" {
            secrets.clear(account: "psk.\(id)")
        }
        #endif
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
        guard !demoOn else { return }
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
                if self.demoOn {
                    self.refreshInFlight = false
                    return
                }
                self.status = status
                var shown = picture
                // Sony reports mute with the volume. Otherwise keep the button's last mute.
                if shown.volume == nil {
                    shown.muted = self.picture.muted
                }
                self.picture = shown
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
        if demoOn {
            demoAct { $0.selectInput(uri: input.uri) }
            return
        }
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
        if key == .volumeMute {
            picture.muted.toggle()
        }
        if demoOn {
            demoAct { $0.press(key) }
            return
        }
        run { $0.press(key) }
    }

    func launch(_ app: TvApp) {
        if demoOn {
            demoAct { $0.launch(app) }
            return
        }
        run { $0.launch(app) }
    }

    func wake() {
        if demoOn {
            demoAct { $0.pressPower() }
            return
        }
        run { $0.pressPower() }
    }

    func sleep() {
        if demoOn {
            demoAct { $0.pressSleep() }
            return
        }
        run { $0.pressSleep() }
    }

    func selectHdmi(_ port: Int) {
        if demoOn {
            demoAct { $0.selectHdmi(port) }
            return
        }
        run { $0.selectHdmi(port) }
    }

    func setVolume(_ level: Int) {
        if demoOn {
            demoAct { $0.setVolume(level) }
            return
        }
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
            window.isOpaque = false
            window.backgroundColor = .clear
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
        if demoOn {
            demoAct { $0.type(text) }
            return
        }
        run { $0.type(text) }
    }

    func openLinkField() {
        onOpenPanel?()
        linkFocusID += 1
    }

    func sendLink(_ raw: String) {
        runJob("Sending the link…", cancellable: false) { [weak self] _ in
            guard let self else { return JobReport(sentence: "Cancelled.", raw: "", isError: true) }
            if self.demoOn { return self.demo.sendLink(raw) }
            return self.session.sendLink(raw)
        }
    }

    func stageDroppedFile(_ url: URL) -> String? {
        stageReadableCopy(of: url)
    }

    func receiveStaged(_ paths: [String]) {
        if demoOn {
            discard(takePendingStages())
            let apks = paths.filter { $0.lowercased().hasSuffix(".apk") }
            guard !apks.isEmpty else {
                noteJob(JobReport(sentence: "Drop an app file ending in .apk.", raw: "", isError: true))
                return
            }
            runJob("Installing…", cancellable: false) { [weak self] _ in
                self?.demo.installApk(at: apks[0]) ?? JobReport(sentence: "Cancelled.", raw: "", isError: true)
            }
            return
        }
        let directories = takePendingStages()
        let apks = paths.filter { $0.lowercased().hasSuffix(".apk") }
        guard !apks.isEmpty else {
            discard(directories)
            noteJob(JobReport(sentence: "Drop an app file ending in .apk.", raw: "", isError: true))
            return
        }
        runInstalls(apks, directories: directories)
    }

    func receiveApks(_ urls: [URL]) {
        if demoOn {
            let apks = urls.filter { $0.path.lowercased().hasSuffix(".apk") }
            guard !apks.isEmpty else {
                noteJob(JobReport(sentence: "Drop an app file ending in .apk.", raw: "", isError: true))
                return
            }
            runJob("Installing…", cancellable: false) { [weak self] _ in
                self?.demo.installApk(at: apks[0].path) ?? JobReport(sentence: "Cancelled.", raw: "", isError: true)
            }
            return
        }
        let apks = urls.filter { $0.path.lowercased().hasSuffix(".apk") }
        guard !apks.isEmpty else {
            noteJob(JobReport(sentence: "Drop an app file ending in .apk.", raw: "", isError: true))
            return
        }
        var paths: [String] = []
        for url in apks {
            let scoped = url.startAccessingSecurityScopedResource()
            if let staged = stageReadableCopy(of: url) {
                paths.append(staged)
            }
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let directories = takePendingStages()
        guard !paths.isEmpty else {
            discard(directories)
            noteJob(JobReport(sentence: "That file can't be read.", raw: "", isError: true))
            return
        }
        runInstalls(paths, directories: directories)
    }

    func installApk(at path: String) {
        if demoOn {
            runJob("Installing…", cancellable: false) { [weak self] _ in
                self?.demo.installApk(at: path) ?? JobReport(sentence: "Cancelled.", raw: "", isError: true)
            }
            return
        }
        runInstalls([path], directories: [])
    }

    func takeScreenshot() {
        runJob("Taking a screenshot…", cancellable: false) { [weak self] _ in
            guard let self else { return JobReport(sentence: "Cancelled.", raw: "", isError: true) }
            let shot = self.demoOn ? self.demo.captureScreenshot() : self.session.captureScreenshot()
            DispatchQueue.main.async { self.screenshotPNG = shot.png }
            return JobReport(sentence: shot.sentence, raw: shot.raw, isError: shot.isError)
        }
    }

    func stopAdbServer() {
        if demoOn { return }
        session.stopAdbServer()
    }

    func startDemo() {
        timer?.invalidate()
        timer = nil
        demoOn = true
        demoNote = ""
        status = demo.refresh()
        picture = DemoSession.connectedPicture
        jobLine = ""
        jobRaw = ""
        jobIsError = false
        jobBusy = false
        banner = ""
        bannerIsError = false
        screenshotPNG = nil
        closeWizard()
        onOpenPanel?()
        onChromeChanged?()
    }

    func leaveDemo() {
        guard demoOn else { return }
        demoOn = false
        demoNote = ""
        jobLine = ""
        jobRaw = ""
        jobIsError = false
        screenshotPNG = nil
        picture = TvPicture()
        onChromeChanged?()
        refreshNow()
    }

    func cancelJob() {
        guard jobBusy, jobCancellable else { return }
        if demoOn { return }
        session.cancelTransfer()
    }

    func copyScreenshot() {
        guard let png = screenshotPNG else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(png, forType: .png)
        jobLine = "Copied."
        jobRaw = ""
        jobIsError = false
    }

    func saveScreenshot() {
        guard let png = screenshotPNG else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Save"
        panel.message = "Save the screenshot."
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let folder {
            panel.directoryURL = folder
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            panel.nameFieldStringValue = ScreenshotSave.availableName(existing: Set(names))
        } else {
            panel.nameFieldStringValue = ScreenshotSave.defaultName
        }
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let scoped = chosen.startAccessingSecurityScopedResource()
        defer { if scoped { chosen.stopAccessingSecurityScopedResource() } }
        let parent = chosen.deletingLastPathComponent()
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? [])
        let dest = parent.appendingPathComponent(
            ScreenshotSave.availableName(existing: names, preferred: chosen.lastPathComponent)
        )
        do {
            try png.write(to: dest)
            jobLine = "Saved."
            jobRaw = dest.path
            jobIsError = false
        } catch {
            jobLine = "The screenshot couldn't be saved."
            jobRaw = error.localizedDescription
            jobIsError = true
        }
    }

    func chooseFileToSend() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Send"
        panel.message = "The TV needs a player to open the file."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        let staged = stageReadableCopy(of: url)
        if scoped { url.stopAccessingSecurityScopedResource() }
        let directories = takePendingStages()
        guard let staged else {
            discard(directories)
            noteJob(JobReport(sentence: "That file can't be read.", raw: url.lastPathComponent, isError: true))
            return
        }
        let name = URL(fileURLWithPath: staged).lastPathComponent
        runJob("Sending \(name)…", directories: directories, cancellable: !demoOn) { [weak self] _ in
            guard let self else { return JobReport(sentence: "Cancelled.", raw: "", isError: true) }
            if self.demoOn { return self.demo.sendFile(at: staged) }
            return self.session.sendFile(at: staged)
        }
    }

    private func runInstalls(_ paths: [String], directories: [String]) {
        guard let first = paths.first else { return }
        let name = URL(fileURLWithPath: first).lastPathComponent
        runJob("Installing \(name)…", directories: directories, cancellable: true) { [weak self] token in
            guard let self else { return JobReport(sentence: "Cancelled.", raw: "", isError: true) }
            var index = 0
            return SerialTransfers.run(paths) { path in
                let file = URL(fileURLWithPath: path).lastPathComponent
                let clear = index == 0
                index += 1
                DispatchQueue.main.async {
                    if self.transfers.update(token: token, line: "Installing \(file)…") {
                        self.jobLine = "Installing \(file)…"
                    }
                }
                if self.demoOn { return self.demo.installApk(at: path, clearingCancel: clear) }
                return self.session.installApk(at: path, clearingCancel: clear)
            }
        }
    }

    private func runJob(_ line: String, directories: [String] = [], cancellable: Bool, work: @escaping (UInt) -> JobReport) {
        guard let token = transfers.begin(line: line, directories: directories) else {
            discard(directories)
            jobLine = TransferGate.busySentence
            jobIsError = true
            return
        }
        jobBusy = true
        jobCancellable = cancellable
        jobLine = line
        jobRaw = ""
        jobIsError = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = work(token)
            DispatchQueue.main.async { self?.complete(token: token, report: report) }
        }
    }

    private func complete(token: UInt, report: JobReport) {
        guard let directories = transfers.finish(token: token) else { return }
        discard(directories)
        jobBusy = false
        jobCancellable = false
        jobLine = report.sentence
        jobRaw = report.raw
        jobIsError = report.isError
    }

    /// Shows a sentence without clearing a job this call did not start.
    private func noteJob(_ report: JobReport) {
        if transfers.busy {
            jobLine = TransferGate.busySentence
            jobIsError = true
            return
        }
        jobLine = report.sentence
        jobRaw = report.raw
        jobIsError = report.isError
    }

    private func stageReadableCopy(of url: URL) -> String? {
        let directory = ReadableStage.directory(in: NSTemporaryDirectory(), jobID: UUID().uuidString)
        do {
            let path = try ReadableStage.copy(url: url, into: directory)
            if path == url.path {
                ReadableStage.remove(directory)
                return path
            }
            stageLock.lock()
            pendingStage.append(directory)
            stageLock.unlock()
            return path
        } catch {
            ReadableStage.remove(directory)
            return nil
        }
    }

    private func takePendingStages() -> [String] {
        stageLock.lock()
        defer { stageLock.unlock() }
        let directories = pendingStage
        pendingStage = []
        return directories
    }

    private func discard(_ directories: [String]) {
        for directory in directories {
            ReadableStage.remove(directory)
        }
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
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Zapbar"
            window.contentView = hosting
            window.isOpaque = false
            window.backgroundColor = .clear
            AppearanceLock.apply(to: hosting)
            AppearanceLock.apply(to: window)
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
            if case .unauthorized = status {
                DispatchQueue.main.async {
                    self.status = status
                    _ = self.wizard.handle(.allowWaiting)
                }
                let settled = self.session.reconnectUntilAuthorized()
                DispatchQueue.main.async {
                    self.applyAllow(settled)
                }
                return
            }
            DispatchQueue.main.async {
                self.applyAllow(status)
            }
        }
    }

    private func applyAllow(_ status: LinkStatus) {
        self.status = status
        switch status {
        case .connected:
            _ = wizard.handle(.allowAccepted)
        case .unauthorized:
            _ = wizard.handle(.allowWaiting)
        case .idle, .connecting, .adbMissing, .helperDown, .refused, .unreachable, .offline, .failed:
            _ = wizard.handle(.connectFailed(status.detail))
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
        let trimmed = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        #if ZAPBAR_MIGRATE_V1 && !SANDBOX_BUILD
        let specific = secrets.load(account: secrets.account(for: trimmed))
        if !specific.isEmpty { return specific }
        if trimmed.isEmpty || trimmed == "legacy" || deviceCount <= 1 {
            return secrets.load()
        }
        return ""
        #else
        guard !trimmed.isEmpty, trimmed != "legacy" else { return "" }
        return secrets.load(account: "psk.\(trimmed)")
        #endif
    }

    private func saveKey(_ value: String, deviceID: String) throws {
        let trimmed = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        #if ZAPBAR_MIGRATE_V1 && !SANDBOX_BUILD
        try secrets.save(value, account: secrets.account(for: trimmed))
        if trimmed == "legacy" || trimmed.isEmpty || settings.devices.count <= 1 {
            try secrets.save(value)
        }
        #else
        guard !trimmed.isEmpty, trimmed != "legacy" else { return }
        try secrets.save(value, account: "psk.\(trimmed)")
        #endif
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
        if demoOn {
            demoAct { $0.type(text) }
            return
        }
        run { $0.type(text) }
    }

    private func demoAct(_ work: (DemoSession) -> ActionReport) {
        demoNote = work(demo).title
        onChromeChanged?()
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
