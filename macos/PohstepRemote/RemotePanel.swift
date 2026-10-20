import AppKit
import SwiftUI

struct RemotePanel: View {
    @ObservedObject var model: AppModel
    /// true = plain stack only, used to measure the panel's real height.
    var measuring: Bool = false
    @State private var volumeDraft: Double = 0
    @State private var volumeIsLive = false
    @State private var inputOpen = false
    @State private var powerArmed = false

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Fits when the screen is tall enough; otherwise scrolls instead of clipping.
        Group {
            if measuring {
                stack
            } else {
                ScrollView(.vertical, showsIndicators: false) { stack }
            }
        }
        .frame(width: GlassMetrics.panelWidth + 56)
        .preferredColorScheme(.dark)
        .tint(Palette.accent)
        .onChange(of: model.picture.volume) { value in
            if !volumeIsLive, let value {
                volumeDraft = Double(value)
            }
        }
        .onAppear {
            if let value = model.picture.volume {
                volumeDraft = Double(value)
            }
        }
    }

    private var stack: some View {
        VStack(spacing: 8) {
            panel
            if let hud = model.volumeHUD, !inputOpen {
                volumeHUD(hud)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 36)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                status
                gap(10)
                dpad
                gap(10)
                volume
                gap(8)
                input
                if showsNowPlaying {
                    gap(10)
                    nowPlaying
                }
            }
            Group {
                hairline
                apps
                hairline
                keyboard
            }
            if model.keyboardMode {
                gap(8)
                legend
            }
            hairline
            footer
        }
        .padding(.horizontal, GlassMetrics.padX)
        .padding(.top, GlassMetrics.padTop)
        .padding(.bottom, GlassMetrics.padBottom)
        .frame(width: GlassMetrics.panelWidth, alignment: .top)
        .background(GlassPlate(material: .popover, corner: GlassMetrics.panelCorner))
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(tvIsOn ? Palette.dotOn : Palette.dotOff)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.text)
                Spacer(minLength: 8)
                powerControl
            }
            Text(statusSubtitle)
                .font(.system(size: 13))
                .foregroundColor(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if model.bannerIsError && !model.banner.isEmpty {
                Text(model.banner)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var powerControl: some View {
        if showsWake {
            Chip(width: 64, height: GlassMetrics.power, corner: 16, action: { model.wake() }) {
                Text("Wake")
                    .font(.system(size: 13, weight: .semibold))
            }
            .accessibilityLabel("Wake")
        } else {
            // Two clicks within 2 s: the first arms (red), the second turns the TV off.
            HStack(spacing: 6) {
                if powerArmed {
                    Text("Click again to turn off")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.text)
                }
                Chip(width: GlassMetrics.power, height: GlassMetrics.power, corner: 16, action: {
                    if powerArmed {
                        powerArmed = false
                        model.sleep()
                    } else {
                        powerArmed = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { powerArmed = false }
                    }
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(powerArmed ? .red : Palette.text)
                }
                .background(Circle().fill(powerArmed ? Color.red.opacity(0.35) : Color.clear))
                .accessibilityLabel(powerArmed ? "Click again to turn off" : "Sleep")
            }
        }
    }

    private var dpad: some View {
        HStack(alignment: .center, spacing: 0) {
            sideControl("chevron.backward", "Back") { model.press(.back) }
            Spacer(minLength: 0)
            ring
            Spacer(minLength: 0)
            sideControl("house", "Home") { model.press(.home) }
        }
        .frame(height: GlassMetrics.ring)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .fill(Palette.ring)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: contrast == .increased ? 1 : 0.5))
            ringZone("chevron.up", "Up", width: GlassMetrics.ring, height: 52, alignment: .top) { model.press(.dpadUp) }
            ringZone("chevron.down", "Down", width: GlassMetrics.ring, height: 52, alignment: .bottom) { model.press(.dpadDown) }
            ringZone("chevron.left", "Left", width: 52, height: 72, alignment: .leading) { model.press(.dpadLeft) }
            ringZone("chevron.right", "Right", width: 52, height: 72, alignment: .trailing) { model.press(.dpadRight) }
            Chip(width: GlassMetrics.ok, height: GlassMetrics.ok, corner: GlassMetrics.ok / 2, action: { model.press(.dpadCenter) }) {
                Text("OK")
                    .font(.system(size: 15, weight: .semibold))
            }
            .accessibilityLabel("OK")
        }
        .frame(width: GlassMetrics.ring, height: GlassMetrics.ring)
        .clipShape(Circle())
    }

    private func ringZone(
        _ symbol: String,
        _ label: String,
        width: CGFloat,
        height: CGFloat,
        alignment: Alignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Palette.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .accessibilityLabel(label)
    }

    private func sideControl(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            Chip(width: GlassMetrics.side, height: GlassMetrics.side, corner: GlassMetrics.side / 2, action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
            }
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var volume: some View {
        HStack(spacing: 6) {
            smallIcon(model.picture.muted ? "speaker.slash.fill" : "speaker.wave.2", "Mute") {
                model.press(.volumeMute)
            }
            smallIcon("minus", "Volume down") { nudgeVolume(-1) }
            VolumeSlider(
                value: volumeBinding,
                range: 0...Double(max(model.picture.maxVolume, 1)),
                enabled: model.picture.volume != nil || model.picture.sonyReady,
                onLive: { next in
                    model.showVolumeHUD("Volume \(Int(next.rounded()))")
                },
                onCommit: { next in
                    let level = Int(next.rounded())
                    model.showVolumeHUD("Volume \(level)")
                    model.setVolume(level)
                }
            )
            smallIcon("plus", "Volume up") { nudgeVolume(1) }
            Text(volumeLabel)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Palette.text)
                .frame(width: 28, alignment: .trailing)
        }
        .frame(minHeight: GlassMetrics.smallHit)
    }

    private var input: some View {
        Button(action: { showInputMenu() }) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.connected.to.line.below")
                    .font(.system(size: 12, weight: .medium))
                Text(inputLabel)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Palette.text)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: GlassMetrics.inputHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(inputOpen ? Palette.chipHover : Palette.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: contrast == .increased ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Input")
        .accessibilityValue(inputLabel)
        .frame(maxWidth: .infinity)
    }

    /// Native menu at the click point: one click anywhere on the bar opens it.
    private func showInputMenu() {
        let items = menuInputs
        guard !items.isEmpty else { return }
        let menu = NSMenu()
        let target = InputMenuTarget { model.selectInput($0) }
        for item in items {
            let entry = NSMenuItem(title: item.menuTitle.isEmpty ? item.uri : item.menuTitle,
                                   action: #selector(InputMenuTarget.pick(_:)), keyEquivalent: "")
            entry.target = target
            entry.representedObject = InputBox(item)
            entry.state = item.uri == selectedInputURI ? .on : .off
            menu.addItem(entry)
        }
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        withExtendedLifetime(target) {
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    private var inputMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(menuInputs, id: \.uri) { item in
                Button(action: {
                    inputOpen = false
                    model.selectInput(item)
                }) {
                    HStack(spacing: 8) {
                        Text(item.menuTitle.isEmpty ? item.uri : item.menuTitle)
                            .font(.system(size: 13))
                            .foregroundColor(Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if item.uri == selectedInputURI {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Palette.accent)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(width: GlassMetrics.menuWidth - 8, height: GlassMetrics.menuRow, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(item.uri == selectedInputURI ? Color.white.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(GlassPlate(material: .menu, corner: 10, tintOpacity: GlassMetrics.menuTint, prominentShadow: false))
        .accessibilityLabel("Inputs")
    }

    private var nowPlaying: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playingTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                Text(playingSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            smallIcon("backward.end.fill", "Previous") { model.press(.mediaPrevious) }
            Chip(width: GlassMetrics.play, height: GlassMetrics.play, corner: GlassMetrics.play / 2, action: { model.press(.mediaPlayPause) }) {
                Image(systemName: model.picture.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .accessibilityLabel(model.picture.isPlaying ? "Pause" : "Play")
            smallIcon("forward.end.fill", "Next") { model.press(.mediaNext) }
        }
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(model.appsCaption)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(secondaryInk)
                if model.appsLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading apps")
                }
            }
            if model.shownApps.isEmpty && model.appsLoading {
                loadingTiles
            } else if model.shownApps.isEmpty {
                Text("No apps from the TV yet.")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                appGrid
            }
        }
    }

    private var loadingTiles: some View {
        HStack(spacing: 1) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: GlassMetrics.tileRadius, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: GlassMetrics.tile, height: GlassMetrics.tile)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 32, height: 6)
                }
                .frame(width: GlassMetrics.tileHitWidth, height: GlassMetrics.tileHitHeight)
            }
        }
        .accessibilityLabel("Loading apps")
    }

    private var appGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(GlassMetrics.tileHitWidth), spacing: 1), count: 6)
        let all = model.shownApps
        let pinned = Array(all.prefix(GlassMetrics.pinnedApps))
        let grid = { (list: [TvApp]) in
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(list) { app in
                    AppTile(app: app, selected: app.matches(package: model.picture.foregroundPackage)) {
                        model.launch(app)
                    }
                }
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            grid(model.appsExpanded ? all : pinned)
            if all.count > pinned.count {
                Button(model.appsExpanded ? "Fewer apps" : "More apps… (\(all.count - pinned.count))") {
                    model.appsExpanded.toggle()
                    DispatchQueue.main.async { model.onChromeChanged?() }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    private var keyboard: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Palette.text)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("Keyboard as remote")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.text)
                Text(model.keyboardMode ? (AXIsProcessTrusted() ? "⌨︎ Typing to TV · \(model.hotkey.display) or ⌃⌥⌘K to stop" : "Needs Accessibility: System Settings → Privacy & Security → Accessibility") : "Off · \(model.hotkey.display) to toggle")
                    .font(.system(size: 11))
                    .foregroundColor(secondaryInk)
            }
            Spacer(minLength: 8)
            RemoteToggle(isOn: .constant(model.keyboardMode)) {
                model.toggleKeyboardMode()
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                keyCap("↑")
                keyCap("↓")
                keyCap("←")
                keyCap("→")
            }
            HStack(spacing: 4) {
                keyCap("return")
                keyCap("esc")
                keyCap("delete")
                keyCap("H")
            }
            Text("Arrows move · return is OK · esc and delete are Back · H is Home")
                .font(.system(size: 11))
                .foregroundColor(tertiaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard shortcuts. Arrows move. Return is OK. Escape is Back. Delete deletes. Control-H is Home. Control-Option-Command-K stops.")
    }

    private func keyCap(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Palette.text)
            .frame(minWidth: 44, minHeight: GlassMetrics.keyCapHeight)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Palette.keyCap)
            )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footerLine)
                .font(.system(size: 11))
                .foregroundColor(tertiaryInk)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Settings…") { model.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .font(.system(size: 11))
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
                .font(.system(size: 11))
        }
    }

    private func volumeHUD(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundColor(Palette.text)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(GlassPlate(material: .hudWindow, corner: 12, tintOpacity: GlassMetrics.panelTint))
        .frame(maxWidth: .infinity)
        .accessibilityLabel(text)
    }

    private func smallIcon(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Chip(
            width: GlassMetrics.small,
            height: GlassMetrics.small,
            corner: 8,
            hitOutset: (GlassMetrics.smallHit - GlassMetrics.small) / 2,
            action: action
        ) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
        }
        .accessibilityLabel(label)
    }

    private func hairlineRow() -> some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: contrast == .increased ? 1 : 0.5)
            .padding(.vertical, GlassMetrics.hairlineGap)
    }

    private var hairline: some View { hairlineRow() }

    private func gap(_ value: CGFloat) -> some View {
        Color.clear.frame(height: value)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { volumeDraft },
            set: { volumeDraft = $0 }
        )
    }

    private func nudgeVolume(_ delta: Int) {
        let ceiling = max(model.picture.maxVolume, 1)
        let base = model.picture.volume ?? Int(volumeDraft.rounded())
        let next = min(max(base + delta, 0), ceiling)
        volumeDraft = Double(next)
        model.showVolumeHUD("Volume \(next)")
        model.press(delta > 0 ? .volumeUp : .volumeDown)
    }

    private var volumeLabel: String {
        if model.picture.volume == nil && !volumeIsLive { return "—" }
        return "\(Int(volumeDraft.rounded()))"
    }

    private var tvIsOn: Bool {
        switch model.picture.power {
        case .on, .reachableOnly:
            return true
        case .off:
            return false
        case .unknown:
            return model.status.isConnected
        }
    }

    private var showsWake: Bool { !tvIsOn }

    private var statusTitle: String {
        switch model.picture.power {
        case .on, .reachableOnly:
            return "TV on"
        case .off:
            return "TV off"
        case .unknown:
            if model.status.isConnected { return "TV on" }
            if case .connecting = model.status { return "Connecting" }
            if case .offline = model.status { return "TV off" }
            return model.status.title
        }
    }

    private var statusSubtitle: String {
        if !tvIsOn {
            if case .connecting = model.status { return model.status.detail }
            if case .idle = model.status { return model.status.detail }
            if case .adbMissing = model.status { return model.status.detail }
            if case .unauthorized = model.status { return model.status.detail }
            if case .refused = model.status { return model.status.detail }
            if case .failed = model.status { return model.status.detail }
            return "Sleeping · tap power to wake"
        }
        let parts = [appName, model.picture.inputTitle].compactMap { $0 }.filter { !$0.isEmpty }
        if parts.isEmpty { return model.status.detail }
        return parts.joined(separator: " · ")
    }

    private var appName: String? {
        guard let package = model.picture.foregroundPackage else { return nil }
        if let match = model.shownApps.first(where: { $0.matches(package: package) }) {
            return match.name
        }
        return nil
    }

    private var showsNowPlaying: Bool {
        guard tvIsOn else { return false }
        if model.picture.nowPlaying != nil { return true }
        return model.picture.foregroundPackage != nil
    }

    private var playingTitle: String {
        if let line = TvApp.cleanName(model.picture.nowPlaying) { return line }
        return appName ?? model.picture.inputTitle ?? "Now playing"
    }

    private var playingSubtitle: String {
        if let name = appName, TvApp.cleanName(model.picture.nowPlaying) != nil {
            return "Now playing · \(name)"
        }
        if let input = model.picture.inputTitle, !input.isEmpty, input != playingTitle {
            return input
        }
        return "Now playing"
    }

    private var menuInputs: [BraviaInput] {
        if !model.picture.inputs.isEmpty { return model.picture.inputs }
        return (1...4).map { port in
            BraviaInput(
                uri: "extInput:hdmi?port=\(port)",
                title: "HDMI \(port)",
                label: "",
                connected: false
            )
        }
    }

    private var selectedInputURI: String {
        if let uri = model.picture.inputURI { return uri }
        return menuInputs.first(where: { $0.menuTitle == model.picture.inputTitle })?.uri ?? ""
    }

    private var inputLabel: String {
        if let title = model.picture.inputTitle, !title.isEmpty { return title }
        return "Input"
    }

    private var footerLine: String {
        if model.picture.sonyReady { return "Sony Bravia · IP control" }
        if model.picture.adbReady || model.status.isConnected { return "Sony Bravia · network adb" }
        return "Sony Bravia · not connected"
    }

    private var secondaryInk: Color {
        Palette.ink(Palette.secondary, increasedContrast: contrast == .increased)
    }

    private var tertiaryInk: Color {
        Palette.ink(Palette.tertiary, increasedContrast: contrast == .increased)
    }
}

private struct AppTile: View {
    var app: TvApp
    var selected: Bool
    var action: () -> Void

    @State private var hover = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: GlassMetrics.tileRadius, style: .continuous)
                        .fill(selected ? Palette.accent : (hover ? Palette.chipHover : Palette.chip))
                    tileMark
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Palette.text)
                }
                .frame(width: GlassMetrics.tile, height: GlassMetrics.tile)
                .overlay(alignment: .top) {
                    if selected {
                        RoundedRectangle(cornerRadius: GlassMetrics.tileRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.50), lineWidth: 0.5)
                            .frame(height: 1)
                            .offset(y: 0.5)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(color: selected ? Palette.accent.opacity(0.33) : Color.clear, radius: 2, y: 1)
                Text(app.name)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: GlassMetrics.tileHitWidth)
            }
            .frame(width: GlassMetrics.tileHitWidth, height: GlassMetrics.tileHitHeight)
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Palette.accent.opacity(0.5), lineWidth: 3)
                        .padding(-1)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .focused($focused)
        .focusable()
        .help(app.name)
        .accessibilityLabel(app.favourite ? "Open \(app.name), favourite" : "Open \(app.name)")
    }

    @ViewBuilder
    private var tileMark: some View {
        if let icon = app.iconURL, let url = URL(string: icon) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                        .frame(width: GlassMetrics.tile, height: GlassMetrics.tile)
                        .clipShape(RoundedRectangle(cornerRadius: GlassMetrics.tileRadius, style: .continuous))
                } else {
                    letterMark
                }
            }
        } else {
            letterMark
        }
    }

    @ViewBuilder
    private var letterMark: some View {
        if app.name.lowercased().contains("spotify") || app.name.lowercased().contains("music") {
            Image(systemName: "music.note")
        } else {
            Text(String(app.name.filter { $0.isLetter || $0.isNumber }.prefix(2)).uppercased())
                .font(.system(size: 13, weight: .bold))
        }
    }
}

struct VolumeSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var enabled: Bool
    var onLive: (Double) -> Void
    var onCommit: (Double) -> Void

    @State private var hover = false
    @State private var pressed = false
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let span = max(range.upperBound - range.lowerBound, 1)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let knobX = fraction * max(width - GlassMetrics.knob, 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.track)
                    .frame(height: GlassMetrics.track)
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: max(knobX + GlassMetrics.knob / 2, GlassMetrics.track), height: GlassMetrics.track)
                Circle()
                    .fill(pressed ? Palette.knobPressed : Palette.knob)
                    .frame(width: GlassMetrics.knob, height: GlassMetrics.knob)
                    .scaleEffect(pressed ? 0.92 : (hover ? 1.1 : 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 1, y: 1)
                    .offset(x: knobX)
                    .overlay {
                        if focused && !pressed {
                            Circle()
                                .stroke(Palette.accent.opacity(0.5), lineWidth: 3)
                                .frame(width: GlassMetrics.knob + 6, height: GlassMetrics.knob + 6)
                        }
                    }
            }
            .frame(height: GlassMetrics.sliderRow)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        pressed = true
                        let next = value(at: gesture.location.x, width: width)
                        value = next
                        onLive(next)
                    }
                    .onEnded { gesture in
                        pressed = false
                        guard enabled else { return }
                        let next = value(at: gesture.location.x, width: width)
                        value = next
                        onCommit(next)
                    }
            )
            .onHover { hover = $0 }
        }
        .frame(height: GlassMetrics.sliderRow)
        .focused($focused)
        .focusable()
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value.rounded()))")
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let span = max(range.upperBound - range.lowerBound, 1)
        let usable = max(width - GlassMetrics.knob, 1)
        let fraction = min(max((x - GlassMetrics.knob / 2) / usable, 0), 1)
        return range.lowerBound + fraction * span
    }
}

private final class InputBox: NSObject {
    let input: BraviaInput
    init(_ input: BraviaInput) { self.input = input }
}

private final class InputMenuTarget: NSObject {
    let onPick: (BraviaInput) -> Void
    init(_ onPick: @escaping (BraviaInput) -> Void) { self.onPick = onPick }
    @objc func pick(_ sender: NSMenuItem) {
        if let box = sender.representedObject as? InputBox { onPick(box.input) }
    }
}
