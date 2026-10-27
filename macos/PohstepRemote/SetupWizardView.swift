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
            if showsPicture {
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

    /// Five slices of one gradient: brand, find, connect, save, done. No skip control on the bar.
    private var progressIndex: Int {
        switch model.wizard.phase {
        case .pickBrand:
            return 0
        case .find, .manual:
            return 1
        case .sonyTyping, .debugging, .pair, .allow, .sonyKey:
            return 2
        case .remember:
            return 3
        case .done:
            return 4
        }
    }

    private var showsPicture: Bool {
        switch model.wizard.phase {
        case .debugging, .pair, .allow:
            return true
        case .pickBrand, .find, .manual, .sonyTyping, .sonyKey, .remember, .done:
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
        case .remember: return "Save this TV"
        case .done: return "Saved"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.wizard.phase {
        case .pickBrand:
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
                Button("\(tv.name) · \(tv.host)") { model.sendWizard(.pick(tv)) }
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
            Button("Skip typing") { model.sendWizard(.typing(false)) }
            Button("I want to type") { model.sendWizard(.typing(true)) }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
        case .debugging:
            Button("Pair with a code") { model.sendWizard(.chooseWireless) }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
            Button("Connect without a code") { model.sendWizard(.chooseLegacy) }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
        case .pair:
            TextField("Number shown on the TV", text: $pairPort)
                .folioFieldChrome(focused: false)
            TextField("Pairing code", text: $pairCode)
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
                Button("Save key and continue") {
                    model.stagePreSharedKey(psk)
                    model.sendWizard(.continueAhead)
                }
                .buttonStyle(FolioPrimaryStyle(wizard: true))
                Button("Skip") { model.sendWizard(.continueAhead) }
            }
        case .remember:
            TextField("Name", text: $deviceName)
                .folioFieldChrome(focused: false)
            Button("Save") {
                model.stagePreSharedKey(psk)
                model.sendWizard(.remember(name: deviceName))
            }
            .buttonStyle(FolioPrimaryStyle(wizard: true))
        case .done:
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
