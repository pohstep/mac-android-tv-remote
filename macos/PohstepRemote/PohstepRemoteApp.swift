import AppKit
import SwiftUI

enum MenuBarIcon {
    /// Approved template glyph (zapbarTemplate.png, @2x, @3x). Pure black on transparent, 18 pt.
    /// macOS tints it for light, dark, and highlighted. No drawn fallback and no colour.
    static func image() -> NSImage {
        let side: CGFloat = 18
        let loaded = Bundle.main.image(forResource: "zapbarTemplate")
        let image = (loaded?.copy() as? NSImage) ?? NSImage(size: NSSize(width: side, height: side))
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        return image
    }
}

/// Covers the menu bar button so a dropped app file lands on the icon.
/// Clicks are forwarded to the button.
final class StatusDrop: NSView {
    weak var button: NSStatusBarButton?
    var onApks: ([URL], Int) -> Void = { _, _ in }
    var onRefused: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        urls(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dropped = urls(from: sender)
        let apks = dropped.filter { ApkPick.isApk($0.path) }
        let skipped = dropped.count - apks.count
        if apks.isEmpty {
            if !dropped.isEmpty { onRefused() }
            return false
        }
        onApks(apks, skipped)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        button?.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        button?.rightMouseDown(with: event)
    }

    private func urls(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []
    }
}

final class RemotePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        AppearanceLock.applyGlobally()
        let delegate = AppDelegate.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private let model = AppModel()
    private var monitor: KeyboardMonitor?
    private var statusItem: NSStatusItem!
    private var panel: RemotePanelWindow!
    private var hosting: NSHostingView<RemotePanel>!
    private var suppressCloseUntil = Date.distantPast
    private var didPromptForAccessibility = false
    private var globalClick: Any?
    private var localClick: Any?
    private var menuPowerItem: NSMenuItem?

    func applicationWillTerminate(_ notification: Notification) {
        // The normal build uses the user's adb server on 5037. Quitting must not stop it.
        // The sandboxed build started its own server on the private port, so it stops that one.
        #if SANDBOX_BUILD
        model.stopAdbServer()
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        AppearanceLock.applyGlobally()
        monitor = KeyboardMonitor(model: model)
        monitor?.start()
        model.onKeyboardModeChanged = { [weak self] on in
            guard let self else { return }
            self.applyIcon()
            if self.panel.isVisible {
                self.sizePanelToFit()
                self.positionPanel()
            }
            guard self.model.allowsKeyboardCapture, on, self.monitor?.canCaptureKeys == false, !self.didPromptForAccessibility else { return }
            self.didPromptForAccessibility = true
            self.monitor?.promptForAccessibility()
            self.model.banner = "Allow Zapbar in System Settings → Privacy & Security → Accessibility. \(Hotkey.default.display) already toggles this."
            self.model.bannerIsError = true
        }
        model.onChromeChanged = { [weak self] in
            guard let self else { return }
            self.applyIcon()
            self.applyMenuPowerItem()
            if self.panel.isVisible {
                self.sizePanelToFit()
                self.positionPanel()
            }
        }
        buildStatusItem()
        buildPanel()
        observeSettingsWindow()
        model.onOpenPanel = { [weak self] in
            self?.openPanel()
        }
        model.start()
        applyIcon()
        if model.shouldOfferSetup {
            model.showWizard()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.monitor?.refreshCapture()
        }
        if model.allowsKeyboardCapture && model.keyboardMode && monitor?.canCaptureKeys == false {
            model.banner = "Keyboard mode is on, but Accessibility isn't allowed yet. Turn the toggle on again to open the prompt."
            model.bannerIsError = true
        }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let overlay = StatusDrop(frame: button.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.button = button
        overlay.onApks = { [weak self] urls, skipped in
            self?.model.receiveApks(urls, skipped: skipped)
        }
        overlay.onRefused = { [weak self] in
            self?.model.refuseNonApk()
        }
        button.addSubview(overlay)
    }

    private func buildPanel() {
        let root = RemotePanel(model: model)
        hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: GlassMetrics.panelWidth + 56, height: 640)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        panel = RemotePanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: GlassMetrics.panelWidth + 56, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Zapbar"
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.masksToBounds = false
        AppearanceLock.apply(to: hosting)
        AppearanceLock.apply(to: panel)
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        sizePanelToFit()

        globalClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeIfOutside()
        }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.window !== self.panel && event.window !== self.model.settingsWindow {
                self.closeIfOutside()
            }
            return event
        }
    }

    private func sizePanelToFit() {
        // Measure the non-scrolling stack, then use that height until it would
        // pass the visible screen. A shorter screen scrolls inside the popover.
        let width = CGFloat(PanelLayout.width)
        let probe = NSHostingView(rootView: RemotePanel(model: model, measuring: true))
        probe.frame = NSRect(x: 0, y: 0, width: width, height: 4000)
        probe.layoutSubtreeIfNeeded()
        let size = probe.fittingSize
        let fittedWidth = max(size.width, width)
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let visible = Double(screen?.visibleFrame.height ?? 800)
        let height = CGFloat(PanelLayout.height(content: Double(size.height), visibleScreen: visible))
        let old = panel.frame
        let contentRect = panel.frameRect(forContentRect: NSRect(x: 0, y: 0, width: fittedWidth, height: height))
        if panel.isVisible && old.height != contentRect.height {
            // Keep the top edge under the menu bar, animate the grow/shrink.
            let frame = NSRect(x: old.minX, y: old.maxY - contentRect.height, width: contentRect.width, height: contentRect.height)
            panel.setFrame(frame, display: true, animate: true)
        } else {
            panel.setContentSize(NSSize(width: fittedWidth, height: height))
        }
        hosting.frame = NSRect(x: 0, y: 0, width: fittedWidth, height: height)
        let line = "\(Date()) content=\(size.height) visible=\(visible) panel=\(height) expanded=\(model.appsExpanded)\n"
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Zapbar/panel-size.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    private func applyIcon() {
        let image = MenuBarIcon.image()
        image.accessibilityDescription = accessibilityLabel()
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = nil
        statusItem.button?.toolTip = accessibilityLabel()
        statusItem.button?.setAccessibilityLabel(accessibilityLabel())
    }

    private func accessibilityLabel() -> String {
        let keys = model.allowsKeyboardCapture
            ? (model.keyboardMode ? "keyboard mode on" : "keyboard mode off")
            : "keyboard capture off"
        let app = TvPicture.shortName(model.picture.foregroundPackage)
        return "Zapbar, \(model.picture.statusLine(appName: app)), \(model.status.title), \(keys)"
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        if panel.isVisible {
            hidePanel()
        } else {
            openPanel()
        }
    }

    private func installEditMenu() {
        if NSApp.mainMenu == nil {
            NSApp.mainMenu = NSMenu()
        }
        guard let main = NSApp.mainMenu else { return }
        if main.items.contains(where: { $0.submenu?.title == "Edit" }) { return }
        let menu = NSMenu(title: "Edit")
        for item in StandardEditMenu.items {
            let entry = NSMenuItem(
                title: item.title,
                action: NSSelectorFromString(item.action),
                keyEquivalent: item.keyEquivalent
            )
            entry.keyEquivalentModifierMask = .command
            entry.target = nil
            menu.addItem(entry)
        }
        let top = NSMenuItem()
        top.submenu = menu
        main.addItem(top)
    }

    private func openPanel() {
        sizePanelToFit()
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        model.focusTypeField()
        suppressCloseUntil = Date().addingTimeInterval(0.25)
        model.setPanelVisible(true)
    }

    private func hidePanel() {
        panel.orderOut(nil)
        model.setPanelVisible(false)
    }

    private func positionPanel() {
        guard let button = statusItem.button, let window = button.window else {
            panel.center()
            return
        }
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var originX = buttonRect.midX - size.width / 2
        var originY = buttonRect.minY - size.height - 6
        originX = min(max(originX, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        if originY < screenFrame.minY {
            originY = buttonRect.maxY + 6
        }
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func closeIfOutside() {
        guard panel.isVisible, Date() > suppressCloseUntil else { return }
        hidePanel()
    }

    private func showMenu() {
        let menu = NSMenu()
        AppearanceLock.apply(to: menu)
        let show = NSMenuItem(title: "Show Remote", action: #selector(openFromMenu), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        if model.allowsKeyboardCapture {
            let toggle = NSMenuItem(title: "Keyboard Mode    \(Hotkey.default.display)", action: #selector(toggleFromMenu), keyEquivalent: "")
            toggle.target = self
            toggle.state = model.keyboardMode ? .on : .off
            menu.addItem(toggle)
        }

        let power = NSMenuItem(title: model.powerButton.label, action: #selector(powerFromMenu), keyEquivalent: "")
        power.target = self
        power.isEnabled = model.powerButton.enabled
        menuPowerItem = power
        menu.addItem(power)

        if model.settings.devices.count > 1 {
            let tvs = NSMenuItem(title: "TVs", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for device in model.settings.devices {
                let item = NSMenuItem(title: device.name, action: #selector(selectTV(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device.id
                item.state = device.id == model.settings.activeDeviceID ? .on : .off
                submenu.addItem(item)
            }
            tvs.submenu = submenu
            menu.addItem(tvs)
        }

        let add = NSMenuItem(title: "Add a TV…", action: #selector(wizardFromMenu), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsFromMenu), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Zapbar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        model.refreshNow()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.model.refreshNow()
        }
        RunLoop.current.add(timer, forMode: .eventTracking)
        statusItem.button?.performClick(nil)
        timer.invalidate()
        menuPowerItem = nil
        statusItem.menu = nil
    }

    private func applyMenuPowerItem() {
        guard let item = menuPowerItem else { return }
        let button = model.powerButton
        item.title = button.label
        item.isEnabled = button.enabled
    }

    @objc private func openFromMenu() { openPanel() }

    @objc private func toggleFromMenu() {
        guard model.allowsKeyboardCapture else { return }
        model.toggleKeyboardMode()
        if model.keyboardMode && monitor?.canCaptureKeys == false {
            monitor?.promptForAccessibility()
            model.banner = "Allow Zapbar in System Settings → Privacy & Security → Accessibility. \(Hotkey.default.display) already toggles this."
            model.bannerIsError = true
        }
    }

    @objc private func powerFromMenu() { model.pressPowerButton() }

    @objc private func wizardFromMenu() { model.showWizard() }

    @objc private func selectTV(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        model.selectDevice(id)
    }

    @objc private func settingsFromMenu() { model.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func observeSettingsWindow() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let window = note.object as? NSWindow else { return }
            self.model.setSettingsKey(window.identifier?.rawValue == "pohstep.settings")
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            if window.identifier?.rawValue == "pohstep.settings" {
                self?.model.settingsWindowClosed()
            }
        }
    }
}
