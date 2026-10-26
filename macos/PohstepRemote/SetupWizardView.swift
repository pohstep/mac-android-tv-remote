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
    }

    private var wizardStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.wizard.phase == .pickBrand {
                ZapbarWordmark(wordSize: 22)
            }
            Text(title)
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
            Button("Xiaomi") { model.sendWizard(.choose(.xiaomi)) }
            Button("Other TV") { model.sendWizard(.choose(.generic)) }
        case .find:
            if model.discovering {
                Text("Looking on the local network…")
                    .font(.system(size: 12))
            }
            ForEach(Array(model.discovered.enumerated()), id: \.offset) { _, tv in
                Button("\(tv.name) · \(tv.host)") { model.sendWizard(.pick(tv)) }
            }
            if DemoOffer.showWhenNoneFound(searching: model.discovering, matchCount: model.discovered.count) {
                Text(DemoCopy.noneFound)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.muted)
                Button(DemoCopy.tryIt) { model.startDemo() }
                    .font(.system(size: 12))
            }
            Button("Enter an address") { model.sendWizard(.wantManual) }
        case .manual:
            TextField("IP address or hostname", text: $manualHost)
                .textFieldStyle(.roundedBorder)
            TextField("Port (optional)", text: $manualPort)
                .textFieldStyle(.roundedBorder)
            Button("Continue") {
                let port = Int(manualPort.trimmingCharacters(in: .whitespacesAndNewlines))
                model.sendWizard(.submitManual(host: manualHost, port: port))
            }
        case .sonyTyping:
            Button("Skip typing") { model.sendWizard(.typing(false)) }
            Button("I want to type") { model.sendWizard(.typing(true)) }
        case .debugging:
            Button("Pair with a code") { model.sendWizard(.chooseWireless) }
            Button("Use port 5555") { model.sendWizard(.chooseLegacy) }
        case .pair:
            TextField("Pairing port", text: $pairPort)
                .textFieldStyle(.roundedBorder)
            TextField("Pairing code", text: $pairCode)
                .textFieldStyle(.roundedBorder)
            Button("Pair") { model.sendWizard(.submitPair(port: pairPort, code: pairCode)) }
        case .allow:
            Button("Check again") { model.retryAllow() }
        case .sonyKey:
            SecureField("Pre-shared key", text: $psk)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save key and continue") {
                    model.stagePreSharedKey(psk)
                    model.sendWizard(.continueAhead)
                }
                Button("Skip") { model.sendWizard(.continueAhead) }
            }
        case .remember:
            TextField("Name", text: $deviceName)
                .textFieldStyle(.roundedBorder)
            Button("Save") {
                model.stagePreSharedKey(psk)
                model.sendWizard(.remember(name: deviceName))
            }
        case .done:
            Button("Close") { model.closeWizard() }
        }
    }
}
