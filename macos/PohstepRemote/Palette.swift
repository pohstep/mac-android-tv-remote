import AppKit
import SwiftUI

/// Dark tokens from the approved panel spec. Light values in that spec are not used.
enum Palette {
    static let text = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let secondary = text.opacity(0.86)
    static let tertiary = text.opacity(0.76)
    /// Settings copy uses the raised secondary grey.
    static let muted = secondary
    static let accent = Color(red: 31 / 255, green: 106 / 255, blue: 224 / 255)
    static let toggleOn = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
    static let dotOn = toggleOn
    static let dotOff = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let hairline = Color.white.opacity(0.14)
    static let track = Color.white.opacity(0.18)
    static let knob = Color.white
    static let knobPressed = Color(red: 230 / 255, green: 230 / 255, blue: 234 / 255)
    static let chip = Color.white.opacity(0.10)
    static let chipHover = Color.white.opacity(0.16)
    static let chipPressed = Color.white.opacity(0.04)
    static let keyCap = Color.white.opacity(0.16)
    static let tint = Color(red: 28 / 255, green: 28 / 255, blue: 34 / 255)
    static let ring = Color.white.opacity(0.08)
    static let nsAccent = NSColor(srgbRed: 31 / 255, green: 106 / 255, blue: 224 / 255, alpha: 1)

    static func ink(_ color: Color, increasedContrast: Bool) -> Color {
        increasedContrast ? text : color
    }
}

enum AppearanceLock {
    static let dark = NSAppearance(named: .darkAqua)

    static func applyGlobally() {
        NSApp.appearance = dark
    }

    static func apply(to window: NSWindow?) {
        window?.appearance = dark
    }

    static func apply(to menu: NSMenu) {
        menu.appearance = dark
    }

    static func apply(to view: NSView) {
        view.appearance = dark
    }
}

enum GlassMetrics {
    static let panelWidth: CGFloat = 320
    static let panelCorner: CGFloat = 12
    static let padX: CGFloat = 16
    static let padTop: CGFloat = 12
    static let padBottom: CGFloat = 8
    static let hairlineGap: CGFloat = 10
    static let ring: CGFloat = 176
    static let ok: CGFloat = 72
    static let side: CGFloat = 44
    static let power: CGFloat = 32
    static let small: CGFloat = 28
    static let smallHit: CGFloat = 32
    static let play: CGFloat = 34
    static let sliderRow: CGFloat = 22
    static let knob: CGFloat = 18
    static let track: CGFloat = 4
    static let inputHeight: CGFloat = 30
    static let tile: CGFloat = 36
    static let tileRadius: CGFloat = 10
    static let tileHitWidth: CGFloat = 47
    static let tileHitHeight: CGFloat = 64
    static let toggleWidth: CGFloat = 32
    static let toggleHeight: CGFloat = 18
    static let menuWidth: CGFloat = 248
    static let menuRow: CGFloat = 26
    static let keyCapHeight: CGFloat = 20
    static let specular: CGFloat = 1.5
    static let panelTint: Double = 0.72
    static let menuTint: Double = 0.93
    static let solidTint: Double = 0.96
    static let panelMaxHeight: CGFloat = 600
    static let pinnedApps = 12
}

struct GlassBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        AppearanceLock.apply(to: view)
    }
}

struct GlassPlate: View {
    var material: NSVisualEffectView.Material = .popover
    var corner: CGFloat = GlassMetrics.panelCorner
    var tintOpacity: Double = GlassMetrics.panelTint
    var prominentShadow: Bool = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let tint = reduceTransparency ? GlassMetrics.solidTint : tintOpacity
        let stroke = contrast == .increased ? 1.0 : 0.5
        ZStack(alignment: .top) {
            GlassBackdrop(material: material)
            Palette.tint.opacity(tint)
            if !reduceTransparency {
                LinearGradient(
                    colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: GlassMetrics.specular)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: stroke)
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.black.opacity(0.50), lineWidth: stroke)
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.30), radius: prominentShadow ? 6 : 4, y: 2)
        .shadow(color: Color.black.opacity(prominentShadow ? 0.55 : 0.35), radius: prominentShadow ? 50 : 16, y: prominentShadow ? 18 : 8)
    }
}

struct Chip<Label: View>: View {
    var width: CGFloat
    var height: CGFloat
    var corner: CGFloat
    var hitOutset: CGFloat = 0
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hover = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            label()
                .foregroundColor(Palette.text)
                .frame(width: width, height: height)
        }
        .buttonStyle(
            ChipStyle(
                corner: corner,
                hover: hover,
                focused: focused,
                reduceTransparency: reduceTransparency,
                strongStroke: contrast == .increased
            )
        )
        .padding(hitOutset)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .focused($focused)
        .focusable()
    }
}

private struct ChipStyle: ButtonStyle {
    var corner: CGFloat
    var hover: Bool
    var focused: Bool
    var reduceTransparency: Bool
    var strongStroke: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = pressed ? Palette.chipPressed : (hover ? Palette.chipHover : Palette.chip)
        let stroke = strongStroke ? 1.0 : 0.5
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(fill)
            )
            .overlay(alignment: .top) {
                if !reduceTransparency && !pressed {
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(pressed ? 0.08 : 0.18), lineWidth: stroke)
            )
            .overlay {
                if pressed {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.black.opacity(0.18), lineWidth: 2)
                        .blur(radius: 1)
                        .mask(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if focused && !pressed {
                    RoundedRectangle(cornerRadius: corner + 1, style: .continuous)
                        .stroke(Palette.accent.opacity(0.5), lineWidth: 3)
                        .padding(-1)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: Color.black.opacity(pressed ? 0 : 0.08), radius: pressed ? 0 : 2, y: pressed ? 0 : 1)
    }
}

struct RemoteToggle: View {
    @Binding var isOn: Bool
    var action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hover = false
    @State private var pressed = false
    @FocusState private var focused: Bool

    var body: some View {
        let stroke: CGFloat = contrast == .increased ? 1 : 0.5
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Palette.toggleOn : Palette.track)
                    .frame(width: GlassMetrics.toggleWidth, height: GlassMetrics.toggleHeight)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: stroke))
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 2)
                    .shadow(color: Color.black.opacity(0.18), radius: 1, y: 1)
            }
            .frame(width: 40, height: 24)
            .brightness(pressed ? -0.18 : (hover ? 0.08 : 0))
            .overlay {
                if focused && !pressed {
                    Capsule()
                        .stroke(Palette.accent.opacity(0.5), lineWidth: 3)
                        .padding(-2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .focused($focused)
        .focusable()
        .accessibilityLabel("Keyboard as remote")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
