import AppKit
import SwiftUI

enum MenuBarIcon {
    /// Template image, 18×18pt, 1.5pt stroke. Off is the slashed set at 55% alpha. Keyboard mode adds a 13pt keyboard.
    static func image(powerOn: Bool, keyboard: Bool) -> NSImage {
        let symbol: CGFloat = 18
        let extra: CGFloat = keyboard ? 16 : 0
        let size = NSSize(width: symbol + extra, height: symbol)
        // Icon B template from the bundle (menubar-template.png + @2x), 18pt.
        let art = Bundle.main.image(forResource: "menubar-template")
        let image = NSImage(size: size, flipped: false) { _ in
            let alpha: CGFloat = powerOn ? 1 : 0.55
            let color = NSColor.black.withAlphaComponent(alpha)
            color.setStroke()
            color.setFill()
            if let art {
                art.draw(in: NSRect(x: 0, y: 0, width: symbol, height: symbol), from: .zero, operation: .sourceOver, fraction: alpha)
            } else {
            let screen = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 5, width: 15.5, height: 10.5), xRadius: 2, yRadius: 2)
            screen.lineWidth = 1.5
            screen.stroke()
            let stand = NSBezierPath()
            stand.lineWidth = 1.5
            stand.lineCapStyle = .round
            stand.lineJoinStyle = .round
            stand.move(to: NSPoint(x: 6, y: 5))
            stand.line(to: NSPoint(x: 6, y: 2.75))
            stand.line(to: NSPoint(x: 12, y: 2.75))
            stand.line(to: NSPoint(x: 12, y: 5))
            stand.stroke()
            if powerOn {
                NSBezierPath(ovalIn: NSRect(x: 7, y: 8, width: 4, height: 4)).fill()
            } else {
                let slash = NSBezierPath()
                slash.lineWidth = 1.5
                slash.lineCapStyle = .round
                slash.move(to: NSPoint(x: 3.2, y: 4.2))
                slash.line(to: NSPoint(x: 14.8, y: 16.2))
                slash.stroke()
            }
            }
            if keyboard {
                let body = NSBezierPath(roundedRect: NSRect(x: 21, y: 4.5, width: 12, height: 8.5), xRadius: 1.5, yRadius: 1.5)
                body.lineWidth = 1.2
                body.stroke()
                for row in 0..<2 {
                    for column in 0..<3 {
                        let key = NSRect(x: 22.4 + CGFloat(column) * 3.4, y: 5.6 + CGFloat(row) * 3.4, width: 2.2, height: 2.2)
                        NSBezierPath(roundedRect: key, xRadius: 0.4, yRadius: 0.4).fill()
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        return image
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

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        // Measure the non-scrolling stack in a throwaway view, so the panel gets its full height.
        let probe = NSHostingView(rootView: RemotePanel(model: model, measuring: true))
        probe.frame = NSRect(x: 0, y: 0, width: GlassMetrics.panelWidth + 56, height: 2000)
        probe.layoutSubtreeIfNeeded()
        let size = probe.fittingSize
        let width = max(size.width, GlassMetrics.panelWidth)
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let maxHeight = (screen?.visibleFrame.height ?? 800) - 12
        // 600 pt cap when collapsed; expanded (More apps) is capped only by the screen.
        let cap = model.appsExpanded ? maxHeight : min(maxHeight, GlassMetrics.panelMaxHeight)
        let height = min(max(size.height, 200), cap)
        let old = panel.frame
        let contentRect = panel.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height))
        if panel.isVisible && old.height != contentRect.height {
            // Keep the top edge under the menu bar, animate the grow/shrink.
            let frame = NSRect(x: old.minX, y: old.maxY - contentRect.height, width: contentRect.width, height: contentRect.height)
            panel.setFrame(frame, display: true, animate: true)
        } else {
            panel.setContentSize(NSSize(width: width, height: height))
        }
        let line = "\(Date()) fitting=\(size.height) cap=\(cap) panel=\(height) expanded=\(model.appsExpanded)\n"
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Zapbar/panel-size.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    private func applyIcon() {
        let on: Bool
        switch model.picture.power {
        case .on, .reachableOnly:
            on = true
        case .off:
            on = false
        case .unknown:
            on = model.status.isConnected
        }
        let image = MenuBarIcon.image(powerOn: on, keyboard: model.allowsKeyboardCapture && model.keyboardMode)
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

    private func openPanel() {
        sizePanelToFit()
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
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

        let wake = NSMenuItem(title: "Wake", action: #selector(wakeFromMenu), keyEquivalent: "")
        wake.target = self
        menu.addItem(wake)

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
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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

    @objc private func wakeFromMenu() { model.wake() }

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
