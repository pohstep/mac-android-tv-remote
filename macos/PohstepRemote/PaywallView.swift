import SwiftUI

struct PaywallView: View {
    @ObservedObject var model: AppModel
    var feature: ProFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ProProduct.displayName)
                .font(.system(size: 18, weight: .semibold))
            Text("$\(ProProduct.displayPrice)")
                .font(.system(size: 15))
            Text(sentence)
                .font(.system(size: 12))
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Unlock") { model.buyPro() }
                .buttonStyle(FolioPrimaryStyle())
            Button("Restore Purchase") { model.restorePro() }
            Button("Not now") { model.paywall = nil }
        }
        .padding(20)
        .frame(width: 320)
        .background(GlassPlate(corner: 0, castsShadow: false))
        .preferredColorScheme(.dark)
    }

    private var sentence: String {
        switch feature {
        case .panelKeyboard:
            return "Use the keyboard while this panel is open."
        case .globalHotkeys:
            return "Choose shortcuts that work from anywhere."
        case .sendClipboard:
            return "Send copied text to the TV when you ask."
        case .severalTVs:
            return "Save more than one TV."
        case .screenshot:
            return "Take a picture of the TV."
        case .apkInstall:
            return "Install an app file on the TV."
        case .appManagement:
            return "Open, stop, or remove an app on the TV."
        }
    }
}
