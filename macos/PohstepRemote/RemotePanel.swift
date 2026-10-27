import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RemotePanel: View {
    @ObservedObject var model: AppModel
    /// true = plain stack only, used to measure the panel's real height.
    var measuring: Bool = false
    @State private var volumeDraft: Double = 0
    @State private var volumeIsLive = false
    @State private var inputOpen = false
    @State private var typeDraft = ""
    @State private var dropTargeted = false
    @FocusState private var typeFocused: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // The window is the measured height, capped at the visible screen.
        // The scroll view takes that height, so a short screen scrolls instead of clipping.
        Group {
            if measuring {
                stack
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    stack
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: GlassMetrics.panelWidth + 56, alignment: .top)
        .preferredColorScheme(.dark)
        .tint(Palette.accent)
        .onChange(of: model.picture.volume) { value in
            if !volumeIsLive, let value {
                volumeDraft = Double(value)
            }
        }
        .onAppear {
            if !measuring { model.prefetchVisibleAppIcons() }
            if let value = model.picture.volume {
                volumeDraft = Double(value)
            }
            if model.typeFocusID > 0 {
                typeFocused = true
            }
        }
        .onChange(of: model.typeFocusID) { _ in
            typeFocused = true
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadDroppedFiles(providers)
        }
        .onChange(of: dropTargeted) { targeted in
            if targeted { model.noteFileDrag() }
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

    private enum Chrome {
        case connected
        case searching
        case offline
    }

    /// Connected while the TV answers, demo is on, or a saved TV is still being reached.
    /// No saved TV uses the searching screen. A saved TV that is not answering uses offline.
    private var chrome: Chrome {
        if model.demoOn || tvIsOn || model.status.isConnected { return .connected }
        if case .connecting = model.status, !model.settings.devices.isEmpty { return .connected }
        if model.settings.devices.isEmpty { return .searching }
        return .offline
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            switch chrome {
            case .connected:
                connectedChrome
            case .searching:
                searchingChrome
            case .offline:
                offlineChrome
            }
            footer
        }
        .padding(.horizontal, GlassMetrics.padX)
        .padding(.top, GlassMetrics.padTop)
        .padding(.bottom, GlassMetrics.padBottom)
        .frame(width: GlassMetrics.panelWidth, alignment: .top)
        .background(GlassPlate())
    }

    private var connectedChrome: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            if model.demoOn {
                demoBanner
            }
            header(status: liveStatusLine, dot: liveStatusDot, showsPower: true)
            failureLine
            remoteBody
        }
    }

    private var searchingChrome: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 2) {
                panelTitle("TV Remote")
                HStack(spacing: 6) {
                    Circle()
                        .fill(searchingDot)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(searchingLine)
                        .font(.system(size: 11.5))
                        .foregroundColor(secondaryInk)
                        .folioTextShadow()
                    if model.discovering || isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.85)
                            .accessibilityLabel("Searching")
                    }
                }
            }
            if !model.discovered.isEmpty {
                discoveredList
            }
            Button(action: { model.showWizard() }) {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle")
                    Text("Set up a new TV")
                }
            }
            .buttonStyle(FolioPrimaryStyle(expands: true))
            Text("Remote available once connected")
                .font(.system(size: 11.5))
                .foregroundColor(secondaryInk)
                .frame(maxWidth: .infinity)
        }
    }

    private var offlineChrome: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            header(status: offlineStatus, dot: Palette.dotOffline, showsPower: true)
            failureLine
            VStack(spacing: 8) {
                Button(action: { model.refreshNow() }) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                }
                .buttonStyle(FolioPrimaryStyle(expands: true))
            }
            remoteBody
                .opacity(0.45)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(DemoCopy.mode)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.text)
                Spacer(minLength: 8)
                Button(DemoCopy.leave) { model.leaveDemo() }
                    .font(.system(size: 11))
            }
            if !model.demoNote.isEmpty {
                Text(model.demoNote)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.muted)
            }
        }
    }

    private func header(status: String, dot: Color, showsPower: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: showDeviceMenu) {
                    HStack(spacing: 5) {
                        panelTitle(headerTitle)
                        if !model.settings.devices.isEmpty {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 13))
                                .foregroundColor(secondaryInk)
                        }
                    }
                }
                .buttonStyle(PanelTitleButtonStyle())
                .environment(\.controlActiveState, .key)
                .disabled(model.settings.devices.isEmpty)
                .accessibilityLabel("TV")
                .accessibilityValue(headerTitle)
                HStack(spacing: 6) {
                    Circle()
                        .fill(dot)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundColor(secondaryInk)
                        .folioTextShadow()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showsPower {
                powerControl
            }
        }
        .frame(minHeight: 36)
    }

    private var discoveredList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.discovered.enumerated()), id: \.offset) { index, tv in
                Button(action: { model.sendWizard(.pick(tv)) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "tv")
                            .font(.system(size: 15))
                            .foregroundColor(secondaryInk)
                        Text(tv.name)
                            .font(.system(size: 13))
                            .foregroundColor(Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(secondaryInk)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                }
                .buttonStyle(.plain)
                if index < model.discovered.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(contrast == .increased ? 0.55 : 0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var failureLine: some View {
        if let detail = failureDetail {
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundColor(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.bannerIsError && !model.banner.isEmpty {
            Text(model.banner)
                .font(.system(size: 11))
                .foregroundColor(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var remoteBody: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            dpad
            transport
            volume
            if showsNowPlaying {
                nowPlaying
            }
            apps
            typeRow
            macTools
            #if ZAPBAR_ADVANCED
            AdvancedCleanupSection(model: model)
            #endif
            if model.allowsKeyboardCapture {
                keyboard
            }
            if model.allowsKeyboardCapture && model.keyboardMode {
                legend
            }
        }
    }

    private var typeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            typeField
                .onDrop(of: [.plainText, .utf8PlainText, .text, .url], isTargeted: nil) { providers in
                    loadDroppedText(providers)
                }
            if !model.typeNotice.isEmpty {
                Text(model.typeNotice)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.typeCanRetry {
                HStack(spacing: 8) {
                    Button("Retry") { model.sendTypedText(typeDraft) }
                        .disabled(model.typeBusy)
                    if model.typeNeedsSetup {
                        Button("Open Settings") { model.showSettings() }
                        Button("Set up a new TV") { model.showWizard() }
                    }
                }
                .font(.system(size: 12))
            }
        }
        .onChange(of: model.typeClearToken) { _ in
            typeDraft = ""
        }
    }

    private var typeField: some View {
        let focused = typeFocused
        let strong = contrast == .increased
        let border: CGFloat = focused ? 1.5 : (strong ? 1.5 : 1)
        let borderOpacity = focused ? 1.0 : (strong ? 0.55 : 0.28)
        return HStack(spacing: 7) {
            Image(systemName: "keyboard")
                .font(.system(size: 15))
                .foregroundColor(secondaryInk)
            TextField(
                "",
                text: $typeDraft,
                prompt: Text("Type, Return sends").foregroundColor(secondaryInk)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(Palette.text)
            .focused($typeFocused)
            .onSubmit { model.sendTypedText(typeDraft) }
            if focused {
                Text("Return to send")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.text)
                    .folioTextShadow()
                    .lineLimit(1)
            } else {
                Text(model.typeHotkey.display)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Palette.keyCap)
                    )
                    .accessibilityLabel("Hotkey \(model.typeHotkey.display)")
            }
        }
        .padding(.horizontal, focused ? 8.5 : 9)
        .frame(height: GlassMetrics.inputHeight)
        .background(
            RoundedRectangle(cornerRadius: GlassMetrics.fieldRadius, style: .continuous)
                .fill(Palette.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.fieldRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: border)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.fieldRadius + 3, style: .continuous)
                .stroke(Color.white.opacity(focused ? 0.25 : 0), lineWidth: 3)
                .padding(-2)
        )
    }

    private var macTools: some View {
        VStack(alignment: .leading, spacing: 6) {
            input
            HStack(spacing: 8) {
                Button("Screenshot") { model.takeScreenshot() }
                    .disabled(model.jobBusy)
                Button("Copy") { model.copyScreenshot() }
                    .disabled(model.screenshotPNG == nil)
                Button("Save…") { model.saveScreenshot() }
                    .disabled(model.screenshotPNG == nil)
                Button("Choose .apk…") { model.chooseApk() }
                    .disabled(model.jobBusy)
                if model.jobBusy && model.jobCancellable {
                    Button("Cancel") { model.cancelJob() }
                }
            }
            .font(.system(size: 12))
            if let png = model.screenshotPNG, let image = NSImage(data: png) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 96)
                    .accessibilityLabel("Screenshot")
            }
            Text(dropTargeted ? "Drop the app file to install it." : "Drop an app file here or on the menu bar icon, or choose an .apk.")
                .font(.system(size: 11))
                .foregroundColor(tertiaryInk)
            if !model.jobLine.isEmpty {
                HStack(spacing: 6) {
                    if model.jobBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Installing")
                    }
                    Text(model.jobLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(model.jobIsError ? Palette.text : Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let step = InstallExplain.recovery(for: model.jobLine, kind: model.jobKind), model.jobIsError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step)
                        .font(.system(size: 11))
                        .foregroundColor(tertiaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.jobKind == .screenshot {
                        Button("Retry") { model.takeScreenshot() }
                            .font(.system(size: 12))
                            .disabled(model.jobBusy)
                    }
                }
            }
            if !model.installLog.isEmpty {
                HStack(spacing: 8) {
                    Button(model.showInstallLog ? "Hide log" : "Show log") {
                        model.showInstallLog.toggle()
                    }
                    if model.showInstallLog {
                        Button("Copy") { model.copyInstallLog() }
                    }
                }
                .font(.system(size: 12))
                if model.showInstallLog {
                    Text(model.installLog)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(tertiaryInk)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.jobRaw.isEmpty {
                Text(model.jobRaw)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(tertiaryInk)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let found = DropBox()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let foundURL = item as? URL {
                    url = foundURL
                } else {
                    url = nil
                }
                guard let url else { return }
                guard ApkPick.isApk(url.path) else {
                    found.refuse()
                    return
                }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let staged = model.stageDroppedFile(url) {
                    found.add(staged)
                }
            }
        }
        group.notify(queue: .main) {
            if found.paths.isEmpty {
                model.refuseNonApk()
            } else {
                model.receiveStaged(found.paths, skipped: found.refusedCount)
            }
        }
        return !providers.isEmpty
    }

    private func loadDroppedText(_ providers: [NSItemProvider]) -> Bool {
        let textProviders = providers.filter {
            !DroppedText.isFileDrop($0.registeredTypeIdentifiers)
                && !$0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !textProviders.isEmpty else { return false }
        for provider in textProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    let raw: String
                    if let url = item as? URL {
                        raw = url.absoluteString
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        raw = url.absoluteString
                    } else {
                        return
                    }
                    applyDroppedText(raw)
                }
                return true
            }
            let identifier = UTType.plainText.identifier
            guard provider.hasItemConformingToTypeIdentifier(identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
                    || provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) else { continue }
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                let raw: String
                if let text = item as? String {
                    raw = text
                } else if let data = item as? Data {
                    raw = String(data: data, encoding: .utf8) ?? ""
                } else {
                    return
                }
                applyDroppedText(raw)
            }
            return true
        }
        return false
    }

    private func applyDroppedText(_ raw: String) {
        DispatchQueue.main.async {
            typeDraft = DroppedText.append(typeDraft, raw)
        }
    }

    @ViewBuilder
    private var powerControl: some View {
        let button = model.powerButton
        VStack(alignment: .trailing, spacing: 4) {
            if button.label == PowerButtonModel.unsupportedLabel {
                Text(button.label)
                    .font(.system(size: 11))
                    .foregroundColor(tertiaryInk)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(button.label)
            } else {
                Chip(width: 96, height: GlassMetrics.power, corner: 12, prominent: button.action == .turnOn, action: {
                    model.pressPowerButton()
                }) {
                    Text(button.label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .disabled(!button.enabled)
                .accessibilityLabel(button.label)
            }
            if !model.powerLine.isEmpty {
                Text(model.powerLine)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.text)
            }
        }
    }

    private var dpad: some View {
        ring
            .frame(maxWidth: .infinity)
    }

    private var transport: some View {
        HStack(spacing: GlassMetrics.transportGap) {
            circleControl("arrow.uturn.backward", "Back") { model.press(.back) }
            circleControl("house", "Home") { model.press(.home) }
            circleControl("playpause.fill", "Play") { model.press(.mediaPlayPause) }
        }
        .frame(maxWidth: .infinity)
    }

    private func circleControl(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Chip(width: GlassMetrics.side, height: GlassMetrics.side, corner: GlassMetrics.side / 2, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
        }
        .accessibilityLabel(title)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .fill(Palette.ring)
                .overlay {
                    if contrast == .increased {
                        Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    }
                }
            ringZone("chevron.up", "Up", from: -135, to: -45, glyph: .top) { model.press(.dpadUp) }
            ringZone("chevron.right", "Right", from: -45, to: 45, glyph: .trailing) { model.press(.dpadRight) }
            ringZone("chevron.down", "Down", from: 45, to: 135, glyph: .bottom) { model.press(.dpadDown) }
            ringZone("chevron.left", "Left", from: 135, to: 225, glyph: .leading) { model.press(.dpadLeft) }
            Chip(width: GlassMetrics.ok, height: GlassMetrics.ok, corner: GlassMetrics.ok / 2, prominent: true, action: { model.press(.dpadCenter) }) {
                Text("OK")
                    .font(.system(size: 17, weight: .bold))
                    .folioTextShadow()
            }
            .accessibilityLabel("OK")
        }
        .frame(width: GlassMetrics.ring, height: GlassMetrics.ring)
        .clipShape(Circle())
    }

    /// One quarter of the ring: the whole wedge (not just the arrow glyph) is the click target.
    private func ringZone(
        _ symbol: String,
        _ label: String,
        from: Double,
        to: Double,
        glyph: Alignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: glyph) {
                RingWedge(from: from, to: to)
                    .fill(Color.white.opacity(0.001))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(Palette.text)
                    .padding(12)
            }
            .frame(width: GlassMetrics.ring, height: GlassMetrics.ring)
            .contentShape(RingWedge(from: from, to: to))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var volume: some View {
        HStack(spacing: 10) {
            smallIcon(
                model.picture.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                "Mute",
                symbolSize: 14
            ) {
                model.press(.volumeMute)
            }
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
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundColor(secondaryInk)
                .frame(width: GlassMetrics.small, height: GlassMetrics.small)
                .accessibilityHidden(true)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(inputOpen ? Palette.chipHover : Palette.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(contrast == .increased ? 0.55 : 0), lineWidth: contrast == .increased ? 1 : 0)
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
                                .foregroundColor(Palette.text)
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
        .background(GlassPlate(corner: 12, castsShadow: false))
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
            if model.appsCaption != AppListCaption.liveTitle {
                HStack(spacing: 6) {
                    Text(model.appsCaption)
                        .font(.system(size: 11.5))
                        .foregroundColor(secondaryInk)
                    if model.appsLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading apps")
                    }
                }
            }
            if model.shownApps.isEmpty && model.appsLoading {
                loadingTiles
            } else if model.shownApps.isEmpty {
                Text("No apps from the TV yet.")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            } else {
                appGrid
            }
        }
    }

    private var loadingTiles: some View {
        HStack(spacing: GlassMetrics.tileGap) {
            ForEach(0..<GlassMetrics.pinnedApps, id: \.self) { _ in
                RoundedRectangle(cornerRadius: GlassMetrics.tileRadius, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: GlassMetrics.tile, height: GlassMetrics.tile)
            }
        }
        .accessibilityLabel("Loading apps")
    }

    private var appGrid: some View {
        let all = model.shownApps
        let pinned = Array(all.prefix(GlassMetrics.pinnedApps))
        let rest = Array(all.dropFirst(GlassMetrics.pinnedApps))
        let columns = Array(repeating: GridItem(.fixed(GlassMetrics.tileColumn), spacing: GlassMetrics.tileGap), count: 4)
        return VStack(alignment: .leading, spacing: GlassMetrics.tileGap) {
            HStack(alignment: .top, spacing: GlassMetrics.tileGap) {
                ForEach(Array(pinned.enumerated()), id: \.element.id) { _, app in
                    appTile(app)
                }
                Spacer(minLength: 0)
                if !rest.isEmpty {
                    Button(action: {
                        model.appsExpanded.toggle()
                        model.prefetchVisibleAppIcons()
                        DispatchQueue.main.async { model.onChromeChanged?() }
                    }) {
                        HStack(spacing: 2) {
                            Text(model.appsExpanded ? "Fewer" : "More")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 13))
                        .foregroundColor(secondaryInk)
                        .frame(height: 28)
                        .padding(.top, (GlassMetrics.tile - 28) / 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.appsExpanded && !rest.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: GlassMetrics.tileGap) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { _, app in
                        appTile(app)
                    }
                }
            }
        }
    }

    private func appTile(_ app: TvApp) -> some View {
        AppTile(
            app: app,
            icon: model.appIcons[app.packageName],
            selected: app.matches(package: model.picture.foregroundPackage)
        ) {
            model.launch(app)
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
        .accessibilityLabel("Keyboard shortcuts. Arrows move. Return is OK. Esc is Back. Delete deletes. Control-H is Home. Control-Option-Command-K stops.")
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
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(contrast == .increased ? 0.55 : 0.20))
                .frame(height: 1)
                .padding(.horizontal, -GlassMetrics.padX)
            HStack(spacing: 4) {
                Button(action: { model.showSettings() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                        Text("Settings")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(Palette.text)
                    .frame(height: GlassMetrics.footerHeight)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                Spacer(minLength: 0)
                Button(action: { model.showWizard() }) {
                    Text("Setup")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.text)
                        .frame(height: GlassMetrics.footerHeight)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                Button(action: { NSApp.terminate(nil) }) {
                    HStack(spacing: 4) {
                        Text("Quit")
                            .foregroundColor(Palette.text)
                        Text("⌘Q")
                            .foregroundColor(secondaryInk)
                    }
                    .font(.system(size: 13))
                    .frame(height: GlassMetrics.footerHeight)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, -8)
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
        .background(GlassPlate(corner: 16))
        .frame(maxWidth: .infinity)
        .accessibilityLabel(text)
    }

    private func smallIcon(_ symbol: String, _ label: String, symbolSize: CGFloat = 11, action: @escaping () -> Void) -> some View {
        Chip(
            width: GlassMetrics.small,
            height: GlassMetrics.small,
            corner: GlassMetrics.small / 2,
            hitOutset: (GlassMetrics.smallHit - GlassMetrics.small) / 2,
            action: action
        ) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .regular))
        }
        .accessibilityLabel(label)
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { volumeDraft },
            set: { volumeDraft = $0 }
        )
    }

    private static let lastSeenFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private var activeDevice: StoredTV? {
        if let match = model.settings.devices.first(where: { $0.id == model.settings.activeDeviceID }) {
            return match
        }
        return model.settings.devices.first
    }

    private var headerTitle: String {
        if model.demoOn { return DemoCopy.name }
        if let name = activeDevice?.name, !name.isEmpty { return name }
        return "TV Remote"
    }

    private var offlineStatus: String {
        guard let seen = activeDevice?.lastSeen else { return "Offline" }
        return "Offline · last seen \(Self.lastSeenFormatter.string(from: seen))"
    }

    private var liveStatusLine: String {
        if case .connecting = model.status, !tvIsOn, !model.demoOn { return "Connecting" }
        return "Connected"
    }

    private var liveStatusDot: Color {
        if case .connecting = model.status, !tvIsOn, !model.demoOn { return Palette.dotSearching }
        return Palette.dotConnected
    }

    private var isConnecting: Bool {
        if case .connecting = model.status { return true }
        return false
    }

    private var searchingDot: Color {
        if model.discovering || isConnecting { return Palette.dotSearching }
        return Palette.dotOffline
    }

    private var searchingLine: String {
        if model.discovering || isConnecting { return "Searching for your TV…" }
        if model.status.detail.isEmpty { return model.status.title }
        return model.status.detail
    }

    private var failureDetail: String? {
        switch model.status {
        case .idle, .connecting, .connected:
            return nil
        case .adbMissing, .helperDown, .unauthorized, .refused, .unreachable, .offline, .failed:
            let detail = model.status.detail
            return detail.isEmpty ? nil : detail
        }
    }

    private func showDeviceMenu() {
        let devices = model.settings.devices
        guard !devices.isEmpty else { return }
        let menu = NSMenu()
        let target = DeviceMenuTarget { model.selectDevice($0) }
        for device in devices {
            let entry = NSMenuItem(title: device.name.isEmpty ? device.host : device.name,
                                   action: #selector(DeviceMenuTarget.pick(_:)),
                                   keyEquivalent: "")
            entry.target = target
            entry.representedObject = device.id as NSString
            entry.state = device.id == model.settings.activeDeviceID ? .on : .off
            menu.addItem(entry)
        }
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        withExtendedLifetime(target) {
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    private var tvIsOn: Bool {
        PowerChrome.showsOn(model.picture.power)
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

    /// TV name, "TV Remote", and "Demo TV". Absolute white, including when the
    /// panel is not key and when the device switcher is disabled.
    private func panelTitle(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Palette.text)
            .opacity(1)
            .lineLimit(1)
            .folioTextShadow()
            .environment(\.controlActiveState, .key)
    }

    private var secondaryInk: Color {
        Palette.ink(Palette.secondary, increasedContrast: contrast == .increased)
    }

    private var tertiaryInk: Color {
        Palette.ink(Palette.tertiary, increasedContrast: contrast == .increased)
    }
}

/// Plain buttons on a non-key panel swap in the inactive label color (~60% white)
/// and fade when disabled. This style keeps the title on Palette.text.
private struct PanelTitleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(1)
            .environment(\.isEnabled, true)
            .environment(\.controlActiveState, .key)
    }
}

private struct AppTile: View {
    var app: TvApp
    var icon: NSImage?
    var selected: Bool
    var action: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var displayName: String {
        AppNames.displayName(package: app.packageName, label: app.name)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                face
                Text(displayName)
                    .font(.system(size: 11))
                    .foregroundColor(contrast == .increased ? Palette.text : Color.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(width: GlassMetrics.tileColumn)
            }
            .frame(width: GlassMetrics.tileColumn)
        }
        .buttonStyle(PanelTitleButtonStyle())
        .environment(\.controlActiveState, .key)
        .focused($focused)
        .focusable()
        .help(displayName)
        .accessibilityLabel(app.favourite ? "Open \(displayName), favourite" : "Open \(displayName)")
    }

    private var face: some View {
        let swatch = AppSwatch.pair(for: app.packageName)
        let stops = [Folio.cyan, Folio.blue, Folio.magenta, Folio.amber]
        return ZStack {
            RoundedRectangle(cornerRadius: GlassMetrics.tileRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [stops[swatch.start], stops[swatch.end]],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: GlassMetrics.tileRadius, style: .continuous)
                .fill(Folio.ink.opacity(0.18))
            tileMark
        }
        .frame(width: GlassMetrics.tile, height: GlassMetrics.tile)
        .clipShape(RoundedRectangle(cornerRadius: GlassMetrics.tileRadius, style: .continuous))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: GlassMetrics.tileRadius, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 1.5)
            }
        }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 3)
                    .padding(-1)
            }
        }
    }

    @ViewBuilder
    private var tileMark: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: GlassMetrics.tile, height: GlassMetrics.tile)
        } else if let remote = app.iconURL, let url = URL(string: remote) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                } else {
                    nameMark
                }
            }
            .frame(width: GlassMetrics.tile, height: GlassMetrics.tile)
        } else {
            nameMark
        }
    }

    private var nameMark: some View {
        Text(AppNames.faceText(package: app.packageName, label: app.name))
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Palette.text)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.9)
            .folioTextShadow()
            .padding(2)
            .frame(width: GlassMetrics.tile, height: GlassMetrics.tile)
    }
}

struct VolumeSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var enabled: Bool
    var onLive: (Double) -> Void
    var onCommit: (Double) -> Void

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
                    .fill(Palette.sliderFill)
                    .frame(width: max(knobX + GlassMetrics.knob / 2, GlassMetrics.track), height: GlassMetrics.track)
                Circle()
                    .fill(pressed ? Palette.knobPressed : Palette.knob)
                    .frame(width: GlassMetrics.knob, height: GlassMetrics.knob)
                    .scaleEffect(pressed ? 0.96 : 1)
                    .offset(x: knobX)
                    .overlay {
                        if focused && !pressed {
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 3)
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

private final class DeviceMenuTarget: NSObject {
    let onPick: (String) -> Void
    init(_ onPick: @escaping (String) -> Void) { self.onPick = onPick }
    @objc func pick(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { onPick(id) }
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


/// A pie wedge covering the full ring, between two angles in degrees (0 = right, clockwise).
private struct RingWedge: Shape {
    var from: Double
    var to: Double
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: c)
        p.addArc(center: c, radius: min(rect.width, rect.height) / 2,
                 startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        p.closeSubpath()
        return p
    }
}

private final class DropBox {
    private let lock = NSLock()
    private(set) var paths: [String] = []
    private(set) var refused = false
    private(set) var refusedCount = 0
    func add(_ path: String) {
        lock.lock()
        paths.append(path)
        lock.unlock()
    }

    func refuse() {
        lock.lock()
        refused = true
        refusedCount += 1
        lock.unlock()
    }
}
