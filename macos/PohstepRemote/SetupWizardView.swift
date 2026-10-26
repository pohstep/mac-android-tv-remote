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
            WizardProgress(index: progressIndex)
            WizardPicture(symbol: pictureSymbol)
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
            HStack {
                if model.wizard.phase != .pickBrand && model.wizard.phase != .done {
                    Button("Back") { model.sendWizard(.back) }
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
        case .debugging: return "Turn on debugging"
        case .pair: return "Pair"
        case .allow: return "Allow this Mac"
        case .sonyKey: return "Sony key"
        case .remember: return "Save this TV"
        case .done: return "Saved"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.wizard.phase {
        case .pickBrand:
            Button("Sony") { model.sendWizard(.choose(.sony)) }
                .buttonStyle(FolioPrimaryStyle())
            Button("Xiaomi") { model.sendWizard(.choose(.xiaomi)) }
                .buttonStyle(FolioPrimaryStyle())
            Button("Other TV") { model.sendWizard(.choose(.generic)) }
                .buttonStyle(FolioPrimaryStyle())
        case .find:
            if model.discovering {
                Text("Looking on the local network…")
                    .font(.system(size: 12))
            }
            ForEach(Array(model.discovered.enumerated()), id: \.offset) { _, tv in
                Button("\(tv.name) · \(tv.host)") { model.sendWizard(.pick(tv)) }
                    .buttonStyle(FolioPrimaryStyle())
            }
            if DemoOffer.showWhenNoneFound(searching: model.discovering, matchCount: model.discovered.count) {
                Text(DemoCopy.noneFound)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.muted)
                Button(DemoCopy.tryIt) { model.startDemo() }
                    .buttonStyle(FolioPrimaryStyle())
            }
            Button("Enter an address") { model.sendWizard(.wantManual) }
        case .manual:
            TextField("IP address or hostname", text: $manualHost)
                .folioFieldChrome(focused: false)
            TextField("Port (optional)", text: $manualPort)
                .folioFieldChrome(focused: false)
            Button("Continue") {
                let port = Int(manualPort.trimmingCharacters(in: .whitespacesAndNewlines))
                model.sendWizard(.submitManual(host: manualHost, port: port))
            }
            .buttonStyle(FolioPrimaryStyle())
        case .sonyTyping:
            Button("Skip typing") { model.sendWizard(.typing(false)) }
            Button("I want to type") { model.sendWizard(.typing(true)) }
                .buttonStyle(FolioPrimaryStyle())
        case .debugging:
            Button("Pair with a code") { model.sendWizard(.chooseWireless) }
                .buttonStyle(FolioPrimaryStyle())
            Button("Use port 5555") { model.sendWizard(.chooseLegacy) }
                .buttonStyle(FolioPrimaryStyle())
        case .pair:
            TextField("Pairing port", text: $pairPort)
                .folioFieldChrome(focused: false)
            TextField("Pairing code", text: $pairCode)
                .folioFieldChrome(focused: false)
            Button("Pair") { model.sendWizard(.submitPair(port: pairPort, code: pairCode)) }
                .buttonStyle(FolioPrimaryStyle())
        case .allow:
            Button("Check again") { model.retryAllow() }
                .buttonStyle(FolioPrimaryStyle())
        case .sonyKey:
            SecureField("Pre-shared key", text: $psk)
                .folioFieldChrome(focused: false)
            HStack {
                Button("Save key and continue") {
                    model.stagePreSharedKey(psk)
                    model.sendWizard(.continueAhead)
                }
                .buttonStyle(FolioPrimaryStyle())
                Button("Skip") { model.sendWizard(.continueAhead) }
            }
        case .remember:
            TextField("Name", text: $deviceName)
                .folioFieldChrome(focused: false)
            Button("Save") {
                model.stagePreSharedKey(psk)
                model.sendWizard(.remember(name: deviceName))
            }
            .buttonStyle(FolioPrimaryStyle())
        case .done:
            Button("Close") { model.closeWizard() }
                .buttonStyle(FolioPrimaryStyle())
        }
    }
}

/// Five segments cut from one diagonal gradient. Empty segments stay a flat white fill.
private struct WizardProgress: View {
    var index: Int

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 4
            let count: CGFloat = 5
            let segment = max((proxy.size.width - gap * (count - 1)) / count, 1)
            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    ForEach(0..<5, id: \.self) { _ in
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 4)
                    }
                }
                Folio.diagonal
                    .frame(width: proxy.size.width, height: 4)
                    .mask(
                        HStack(spacing: gap) {
                            ForEach(0..<5, id: \.self) { slot in
                                Capsule()
                                    .frame(width: segment, height: 4)
                                    .opacity(slot <= index ? 1 : 0)
                            }
                        }
                        .frame(width: proxy.size.width, alignment: .leading)
                    )
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Setup step \(index + 1) of 5")
    }
}

/// Flat framed stand-in. The approved pictures were not in this tree.
private struct WizardPicture: View {
    var symbol: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.10))
            Folio.diagonal.opacity(0.40)
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(Palette.text)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}
