import AppKit
import SwiftUI

/// Approved 128 px app icon, copied into the bundle as-is. Already squircle-masked.
enum ZapbarMark {
    static let image: NSImage? = {
        guard let loaded = Bundle.main.image(forResource: "ZapbarMark") else { return nil }
        return (loaded.copy() as? NSImage) ?? loaded
    }()
}

/// Lockup for the panel header and the first setup step. One ink: white.
struct ZapbarWordmark: View {
    var wordSize: CGFloat = 18

    /// SF Pro Rounded cap height is about 0.71 em. The mark is that height times 1.4.
    private var markSide: CGFloat { wordSize * 0.71 * 1.4 }
    private var lineSize: CGFloat { wordSize * 0.62 }

    private var ink: Color { Color.white }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                mark
                Text("Zapbar")
                    .font(.system(size: wordSize, weight: .heavy, design: .rounded))
                    .foregroundColor(ink)
            }
            Text("Type on your TV. From your Mac.")
                .font(.system(size: lineSize, weight: .regular, design: .rounded))
                .foregroundColor(ink)
                .padding(.leading, markSide + 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zapbar. Type on your TV. From your Mac.")
    }

    @ViewBuilder
    private var mark: some View {
        if let image = ZapbarMark.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: markSide, height: markSide)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: markSide, height: markSide)
        }
    }
}
