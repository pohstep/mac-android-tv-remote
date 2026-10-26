import AppKit
import SwiftUI

/// One look. White and white at 88%, on the flat glass. No light pair.
enum Palette {
    static let text = Color.white
    static let secondary = Color.white.opacity(0.88)
    static let tertiary = Color.white.opacity(0.88)
    static let muted = secondary
    static let accent = Color.white
    static let dotConnected = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    static let dotSearching = Color(red: 0xFF / 255, green: 0xB8 / 255, blue: 0x6B / 255)
    static let dotOffline = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255)
    static let dotOn = dotConnected
    static let dotOff = dotOffline
    static let toggleOn = dotConnected
    static let hairline = Color.white.opacity(0.18)
    static let track = Color.white.opacity(0.28)
    static let sliderFill = Color.white
    static let knob = Color.white
    static let knobPressed = Color.white.opacity(0.88)
    static let chip = Color.white.opacity(0.14)
    static let chipHover = Color.white.opacity(0.18)
    static let chipPressed = Color.white.opacity(0.08)
    static let fieldFill = Color.white.opacity(0.10)
    static let keyCap = Color(red: 0x06 / 255, green: 0x06 / 255, blue: 0x3A / 255).opacity(0.30)
    static let ring = Color.white.opacity(0.12)
    static let nsAccent = NSColor.white

    static func ink(_ color: Color, increasedContrast: Bool) -> Color {
        increasedContrast ? text : color
    }
}

/// Flat-glass colours from the approved panel. 135° runs top-left to bottom-right.
enum Folio {
    static let cyan = Color(red: 0x36 / 255, green: 0xD1 / 255, blue: 0xDC / 255)
    static let blue = Color(red: 0x5B / 255, green: 0x5B / 255, blue: 0xF0 / 255)
    static let magenta = Color(red: 0xD9 / 255, green: 0x46 / 255, blue: 0xEF / 255)
    static let amber = Color(red: 0xFF / 255, green: 0xB8 / 255, blue: 0x6B / 255)
    static let ink = Color(red: 0x0A / 255, green: 0x06 / 255, blue: 0x3C / 255)
    static let scrim = Color(red: 0x06 / 255, green: 0x08 / 255, blue: 0x3A / 255)
    static let textShadow = Color(red: 0, green: 0, blue: 40.0 / 255).opacity(0.25)
    static let shadow = Color(red: 0, green: 0, blue: 30.0 / 255).opacity(0.25)
    /// Approved mock panel tint. The layers table's .38 is the older note.
    static let tintAlpha = 0.42

    static let stops: [Gradient.Stop] = [
        .init(color: cyan, location: 0),
        .init(color: blue, location: 0.35),
        .init(color: magenta, location: 0.70),
        .init(color: amber, location: 1)
    ]

    static var diagonal: LinearGradient {
        LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// OK shifts the same stops so the circle does not repeat the panel wash.
    static var okGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: cyan, location: 0.10),
                .init(color: blue, location: 0.42),
                .init(color: magenta, location: 0.74),
                .init(color: amber, location: 1.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var scrimWash: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: scrim.opacity(0.42), location: 0),
                .init(color: scrim.opacity(0.30), location: 0.38),
                .init(color: scrim.opacity(0.42), location: 0.72),
                .init(color: scrim.opacity(0.52), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var edge: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.65), location: 0),
                .init(color: Color.white.opacity(0.20), location: 0.35),
                .init(color: Color.white.opacity(0.12), location: 0.70),
                .init(color: Color.white.opacity(0.30), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Letter-tile pairs from the connected mock, in order.
    static let tilePairs: [(Color, Color)] = [
        (Color(red: 0x1A / 255, green: 0x93 / 255, blue: 0xA8 / 255), Color(red: 0x4B / 255, green: 0x4B / 255, blue: 0xE0 / 255)),
        (Color(red: 0x5B / 255, green: 0x5B / 255, blue: 0xF0 / 255), Color(red: 0xB8 / 255, green: 0x3A / 255, blue: 0xD0 / 255)),
        (Color(red: 0xC9 / 255, green: 0x3B / 255, blue: 0xDD / 255), Color(red: 0x5B / 255, green: 0x5B / 255, blue: 0xF0 / 255)),
        (Color(red: 0xD9 / 255, green: 0x7A / 255, blue: 0x35 / 255), Color(red: 0xB8 / 255, green: 0x3A / 255, blue: 0xC8 / 255))
    ]

    static func tilePair(index: Int) -> LinearGradient {
        let pair = tilePairs[index % tilePairs.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
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
    static let panelCorner: CGFloat = 20
    static let padX: CGFloat = 18
    static let padTop: CGFloat = 18
    static let padBottom: CGFloat = 10
    static let sectionGap: CGFloat = 12
    static let ring: CGFloat = 176
    static let ok: CGFloat = 72
    static let side: CGFloat = 44
    static let power: CGFloat = 32
    static let small: CGFloat = 28
    static let smallHit: CGFloat = 32
    static let play: CGFloat = 34
    static let sliderRow: CGFloat = 22
    static let knob: CGFloat = 16
    static let track: CGFloat = 4
    static let inputHeight: CGFloat = 32
    static let fieldRadius: CGFloat = 12
    static let tile: CGFloat = 36
    static let tileRadius: CGFloat = 10
    static let tileGap: CGFloat = 10
    static let transportGap: CGFloat = 20
    static let footerHeight: CGFloat = 28
    static let primaryHeight: CGFloat = 38
    static let primaryRadius: CGFloat = 12
    static let wizardPrimaryHeight: CGFloat = 34
    static let wizardPrimaryRadius: CGFloat = 10
    static let toggleWidth: CGFloat = 32
    static let toggleHeight: CGFloat = 18
    static let menuWidth: CGFloat = 248
    static let menuRow: CGFloat = 26
    static let keyCapHeight: CGFloat = 20
    static let pinnedApps = 4
}

struct GlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        // macOS 26: .glassEffect would replace this backdrop. This build is the macOS 13.7 path only.
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        AppearanceLock.apply(to: view)
    }
}

struct GlassPlate: View {
    var corner: CGFloat = GlassMetrics.panelCorner
    var castsShadow: Bool = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let strong = contrast == .increased
        ZStack {
            if reduceTransparency {
                Folio.scrim
            } else {
                GlassBackdrop()
                Folio.diagonal.opacity(Folio.tintAlpha)
                Folio.scrimWash
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Folio.edge, lineWidth: strong ? 1.5 : 1)
        )
        .shadow(
            color: castsShadow ? Folio.shadow : Color.clear,
            radius: castsShadow ? 80 : 0,
            x: 0,
            y: castsShadow ? 30 : 0
        )
    }
}

struct Chip<Label: View>: View {
    var width: CGFloat
    var height: CGFloat
    var corner: CGFloat
    var hitOutset: CGFloat = 0
    /// OK uses the four-stop gradient and a 20% ink overlay. Other controls stay flat.
    var prominent: Bool = false
    var action: () -> Void
    @ViewBuilder var label: () -> Label

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
                prominent: prominent,
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
    var prominent: Bool
    var strongStroke: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = pressed ? Palette.chipPressed : (hover ? Palette.chipHover : Palette.chip)
        configuration.label
            .background {
                ZStack {
                    if prominent {
                        Folio.okGradient
                        Folio.ink.opacity(0.20)
                    } else {
                        fill
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            }
            .overlay {
                if strongStroke && !prominent {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                }
            }
            .overlay {
                if focused && !pressed {
                    RoundedRectangle(cornerRadius: corner + 3, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 3)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .opacity(prominent && pressed ? 0.86 : 1)
    }
}

struct FolioPrimaryStyle: ButtonStyle {
    var wizard: Bool = false
    var expands: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        FolioPrimaryBody(configuration: configuration, wizard: wizard, expands: expands)
    }
}

private struct FolioPrimaryBody: View {
    let configuration: ButtonStyleConfiguration
    var wizard: Bool
    var expands: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let height = wizard ? GlassMetrics.wizardPrimaryHeight : GlassMetrics.primaryHeight
        let radius = wizard ? GlassMetrics.wizardPrimaryRadius : GlassMetrics.primaryRadius
        configuration.label
            .font(.system(size: wizard ? 13 : 14, weight: .semibold))
            .foregroundColor(Palette.text)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(minHeight: height)
            .padding(.horizontal, expands ? 12 : 18)
            .background(
                ZStack {
                    Folio.diagonal
                    Folio.ink.opacity(0.30)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.45)
    }
}

private struct FolioFieldChrome: ViewModifier {
    var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let strong = contrast == .increased
        let border: CGFloat = focused ? 1.5 : (strong ? 1.5 : 1)
        let borderOpacity = focused ? 1.0 : (strong ? 0.55 : 0.28)
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(minHeight: GlassMetrics.inputHeight, alignment: .leading)
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
}

extension View {
    func folioFieldChrome(focused: Bool) -> some View {
        modifier(FolioFieldChrome(focused: focused))
    }

    func folioTextShadow() -> some View {
        shadow(color: Folio.textShadow, radius: 1, x: 0, y: 0.5)
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
        let stroke: CGFloat = contrast == .increased ? 1 : 0
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Palette.toggleOn : Palette.track)
                    .frame(width: GlassMetrics.toggleWidth, height: GlassMetrics.toggleHeight)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(stroke > 0 ? 0.55 : 0), lineWidth: stroke))
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 2)
            }
            .frame(width: 40, height: 24)
            .opacity(pressed ? 0.82 : (hover ? 1 : 0.96))
            .overlay {
                if focused && !pressed {
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 3)
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
