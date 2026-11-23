import AppKit
import SwiftUI

/// Plain setup screens. The state machine in `SetupWizard` decides the step.
struct SetupWizardView: View {
    @ObservedObject var model: AppModel
    @State private var manualHost = ""
    @State private var manualPort = ""
    @State private var pairPort = ""
    @State private var pairCode = ""
    @State private var deviceName = ""
    @State private var psk = ""
    @State private var suggestedKey = TvSetupGuide.suggestedKey()
    @State private var keyCopied = false

    var body: some View {
        ScrollView {
            wizardStack
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GlassPlate(corner: 0, castsShadow: false))
        .preferredColorScheme(.dark)
    }

    private var wizardStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step \(progressIndex + 1) of 5")
                .font(.system(size: 11.5))
                .foregroundColor(Palette.text)
            WizardProgress(index: progressIndex)
            if showsPicture && guideCards.isEmpty {
                WizardPicture(symbol: pictureSymbol)
            }
            if model.wizard.phase == .pickBrand {
                ZapbarWordmark(wordSize: 22)
            }
            Text(title)
                .foregroundColor(Palette.text)
                .font(.system(size: 16, weight: .semibold))
            if let message = model.wizard.message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.text)
            }
            ForEach(model.wizard.lines(), id: \.key) { line in
                Text(line.text)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(line.key)
            }
            if model.wizard.phase == .sonyKey {
                keySuggestion
            }
            ForEach(guideCards, id: \.key) { card in
                GuideCardView(card: card, number: guideCards.count > 1 ? (guideCards.firstIndex(of: card) ?? 0) + 1 : nil)
            }
            content
            Rectangle()
                .fill(Color.white.opacity(0.20))
                .frame(height: 1)
            HStack {
                if model.wizard.phase == .pickBrand {
                    Button("Cancel") { model.closeWizard() }
                        .foregroundColor(Palette.text)
                } else if model.wizard.phase != .done {
                    Button("Back") { model.sendWizard(.back) }
                        .foregroundColor(Palette.text)
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: model.wizard.phase) { phase in
            if phase == .pair, pairPort.isEmpty, let hint = model.wizard.pairingPortHint {
                pairPort = String(hint)
            }
            if phase == .remember {
                deviceName = model.wizard.name
            }
        }
    }

    private var guideCards: [GuideCard] {
        TvSetupGuide.cards(phase: model.wizard.phase, brand: model.wizard.brand, keyboardCapture: model.allowsKeyboardCapture)
    }

    private var keySuggestion: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Need a key? Use this one on the TV and here:")
                .font(.system(size: 12))
                .foregroundColor(Palette.text)
            HStack(spacing: 8) {
                Text(suggestedKey)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(Palette.text)
                    .textSelection(.enabled)
                    .accessibilityLabel("Suggested key \(suggestedKey.map(String.init).joined(separator: " "))")
                Spacer(minLength: 8)
                Button(keyCopied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(suggestedKey, forType: .string)
                    keyCopied = true
                }
                Button("Use this key") {
                    psk = suggestedKey
                }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
                Button(action: {
                    suggestedKey = TvSetupGuide.suggestedKey()
                    keyCopied = false
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Suggest another key")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var foundOnNetwork: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(model.discovering ? "Looking for TVs on this network…" : (model.discovered.isEmpty ? "No TV found yet. Pick the brand below." : "Found on this network. Click your TV:"))
                    .font(.system(size: 12))
                    .foregroundColor(Palette.text)
                if model.discovering {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }
            }
            ForEach(Array(model.discovered.enumerated()), id: \.offset) { _, tv in
                Button(action: { model.quickPick(tv) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "tv")
                        Text(tv.listTitle)
                        Spacer(minLength: 4)
                        Text(tv.host)
                            .foregroundColor(Palette.muted)
                    }
                }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
            }
            if !model.discovered.isEmpty {
                Text("Or pick the brand:")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.muted)
            }
        }
    }

    /// Five slices of one gradient: brand, find, connect, save, done. No skip control on the bar.
    private var progressIndex: Int {
        switch model.wizard.phase {
        case .pickBrand:
            return 0
        case .find, .manual:
            return 1
        case .sonyTyping, .debugging, .pair, .allow, .sonyKey, .xiaomiCheck:
            return 2
        case .remember:
            return 3
        case .done:
            return 4
        }
    }

    private var showsPicture: Bool {
        switch model.wizard.phase {
        case .debugging, .pair, .allow, .sonyKey, .xiaomiCheck:
            return true
        case .pickBrand, .find, .manual, .sonyTyping, .remember, .done:
            return false
        }
    }

    private var pictureSymbol: String {
        switch model.wizard.phase {
        case .pickBrand:
            return "tv"
        case .find, .manual:
            return "dot.radiowaves.left.and.right"
        case .sonyTyping, .debugging, .pair, .allow:
            return "checkmark.shield"
        case .sonyKey:
            return "lock"
        case .xiaomiCheck:
            return "tv"
        case .remember, .done:
            return "square.and.arrow.down"
        }
    }

    private var title: String {
        switch model.wizard.phase {
        case .pickBrand: return "Which TV is this?"
        case .find: return "Find the TV"
        case .manual: return "Enter an address"
        case .sonyTyping: return "Typing"
        case .debugging: return "Connect this Mac"
        case .pair: return "Pair"
        case .allow: return "Allow this Mac"
        case .sonyKey: return "Control key"
        case .xiaomiCheck: return "Check this TV"
        case .remember: return "Save this TV"
        case .done: return "Saved"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.wizard.phase {
        case .pickBrand:
            foundOnNetwork
            Button("Sony") { model.sendWizard(.choose(.sony)) }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
            Button("Xiaomi") { model.sendWizard(.choose(.xiaomi)) }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
            Button("Other TV") { model.sendWizard(.choose(.generic)) }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
        case .find:
            if model.discovering {
                Text("Looking on the local network…")
                    .font(.system(size: 12))
            }
            ForEach(Array(model.discovered.enumerated()), id: \.offset) { _, tv in
                Button(tv.listTitle) { model.sendWizard(.pick(tv)) }
                    .buttonStyle(FolioPrimaryStyle(wizard: true))
            }
            if DemoOffer.showWhenNoneFound(searching: model.discovering, matchCount: model.discovered.count) {
                Text(DemoCopy.noneFound)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.muted)
                Button(DemoCopy.tryIt) { model.startDemo() }
                    .buttonStyle(FolioPrimaryStyle(wizard: true))
            }
            Button("Enter an address") { model.sendWizard(.wantManual) }
        case .manual:
            TextField("Address", text: $manualHost)
                .folioFieldChrome(focused: false)
            TextField("Number (optional)", text: $manualPort)
                .folioFieldChrome(focused: false)
            Button("Continue") {
                let port = Int(manualPort.trimmingCharacters(in: .whitespacesAndNewlines))
                model.sendWizard(.submitManual(host: manualHost, port: port))
            }
            .buttonStyle(FolioPrimaryStyle(wizard: true))
        case .sonyTyping:
            Button("Use remote keys only") { model.sendWizard(.typing(false)) }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
            Button("Also set up typing") { model.sendWizard(.typing(true)) }
        case .debugging:
            if model.wizard.showsDebugChoices {
                Button("Pair with a code") { model.sendWizard(.chooseWireless) }
                    .buttonStyle(FolioPrimaryStyle(wizard: true))
                Button("Connect without a code") { model.sendWizard(.chooseLegacy) }
                    .buttonStyle(FolioPrimaryStyle(wizard: true))
                Button("Try again") { model.sendWizard(.watchRetry) }
                    .buttonStyle(FolioPrimaryStyle(wizard: true))
            }
        case .pair:
            TextField("Number shown on the TV", text: $pairPort)
                .folioFieldChrome(focused: false)
            TextField("Code", text: $pairCode)
                .folioFieldChrome(focused: false)
            Button("Pair") { model.sendWizard(.submitPair(port: pairPort, code: pairCode)) }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
                .disabled(pairCode.trimmingCharacters(in: .whitespacesAndNewlines).count != 6)
        case .allow:
            Button("Check again") { model.retryAllow() }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
        case .sonyKey:
            SecureField("Control key", text: $psk)
                .folioFieldChrome(focused: false)
            HStack {
                Button("Test connection") { model.sendWizard(.testKey(psk)) }
                    .buttonStyle(FolioPrimaryStyle(wizard: true))
                Button("Skip") { model.sendWizard(.continueAhead) }
            }
            if model.wizard.switchWatch?.phase == .timedOut {
                Button("Try again") { model.sendWizard(.watchRetry) }
                    .buttonStyle(FolioPrimaryStyle(wizard: true))
            }
        case .xiaomiCheck:
            Button("Continue") { model.sendWizard(.continueAhead) }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
        case .remember:
            TextField("Name", text: $deviceName)
                .folioFieldChrome(focused: false)
            Button("Save") {
                model.stagePreSharedKey(psk)
                model.sendWizard(.remember(name: deviceName))
            }
            .buttonStyle(FolioPrimaryStyle(wizard: true))
        case .done:
            if !guideCards.isEmpty {
                Button("Open Accessibility settings") { model.openAccessibilitySettings() }
            }
            Button("Close") { model.closeWizard() }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
        }
    }
}

/// Five segments cut from one diagonal gradient. Empty segments stay white at 22%.
private struct WizardProgress: View {
    var index: Int

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let count: CGFloat = 5
            let segment = max((proxy.size.width - gap * (count - 1)) / count, 1)
            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(height: 3)
                    }
                }
                Folio.diagonal
                    .frame(width: proxy.size.width, height: 3)
                    .mask(
                        HStack(spacing: gap) {
                            ForEach(0..<5, id: \.self) { slot in
                                Capsule()
                                    .frame(width: segment, height: 3)
                                    .opacity(slot <= index ? 1 : 0)
                            }
                        }
                        .frame(width: proxy.size.width, alignment: .leading)
                    )
            }
        }
        .frame(height: 3)
        .accessibilityLabel("Setup step \(index + 1) of 5")
    }
}

/// Flat frame for steps that show a picture. The TV-settings drawings are not in this tree,
/// so the frame stays empty of a fake settings screen.
private struct WizardPicture: View {
    var symbol: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundColor(Palette.secondary)
        }
        .frame(width: 288, height: 162)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

private struct GuideCardView: View {
    var card: GuideCard
    var number: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let number {
                    Text("\(number).")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.text)
                }
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.text)
            }
            Text(card.why)
                .font(.system(size: 12))
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            TvScreenPicture(steps: card.steps)
            if !card.note.isEmpty {
                Text(card.note)
                    .font(.system(size: 11.5))
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(card.key)
    }
}

private struct TvScreenPicture: View {
    var steps: [GuideStep]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    row(index: index, step: step, last: index == steps.count - 1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
            )
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 44, height: 4)
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 96, height: 4)
        }
    }

    private func row(index: Int, step: GuideStep, last: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Palette.text)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.16)))
            Image(systemName: step.symbol)
                .font(.system(size: 12))
                .foregroundColor(Palette.text)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Palette.text)
                if !step.english.isEmpty {
                    Text(step.english)
                        .font(.system(size: 10.5))
                        .foregroundColor(Palette.muted)
                }
                if !step.value.isEmpty {
                    Text("= \(step.value)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !last {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Palette.muted)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(last ? AnyShapeStyle(Folio.diagonal.opacity(0.55)) : AnyShapeStyle(Color.white.opacity(0.06)))
        )
    }
}
