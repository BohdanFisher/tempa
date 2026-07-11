import SwiftUI
import UIKit

// MARK: - Design Tokens (1:1 from tokens.jsx)

enum T {
    // Base — adaptive (light / warm-dark). The dark side mirrors the Focus aesthetic.
    static let bg = Color(lightHex: "#FBF8F3", darkHex: "#161210")
    static let bgWarm = Color(lightHex: "#F4EFE6", darkHex: "#1E1712")
    static let surface = Color(lightHex: "#FFFFFF", darkHex: "#241D18")

    // Brand — coral & teal pop on both light and dark, so they stay put.
    static let primary = Color(hex: "#FF7A59")
    static let primaryDeep = Color(hex: "#E5613F")
    static let secondary = Color(hex: "#4EC8B0")
    static let secondaryDeep = Color(hex: "#2FA993")

    // Text — adaptive (dark ink on light, warm off-white on dark).
    static let text = Color(lightHex: "#2A2A33", darkHex: "#F3EEE7")
    static let textSec = Color(lightHex: "#8A8A99", darkHex: "#A89F96")
    static let textTer = Color(lightHex: "#BDBDC7", darkHex: "#6F665E")

    // Soft semantic
    static let danger = Color(hex: "#E89B7A")
    static let warning = Color(hex: "#F0C674")

    // Radii
    enum r {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let pill: CGFloat = 9999
    }

    // Fonts
    static let fontHeader = "Nunito"
    static let fontBody = "Inter"
}

// MARK: - Category Colors

struct CatColors {
    let bg: Color
    let ink: Color
    let solid: Color
}

enum Cat {
    static let work     = CatColors(bg: Color(lightHex: "#E3EDFF", darkHex: "#1C2742"), ink: Color(lightHex: "#3F6BCA", darkHex: "#A6C3F1"), solid: Color(lightHex: "#7FA7E6", darkHex: "#6B95D7"))
    static let personal = CatColors(bg: Color(lightHex: "#FFE2D6", darkHex: "#3B2017"), ink: Color(lightHex: "#C55F3D", darkHex: "#F4B39B"), solid: Color(lightHex: "#F39E80", darkHex: "#E08661"))
    static let health   = CatColors(bg: Color(lightHex: "#D6F0E7", darkHex: "#143029"), ink: Color(lightHex: "#2F8C72", darkHex: "#80D7BB"), solid: Color(lightHex: "#7BCFB6", darkHex: "#54B496"))
    static let routine  = CatColors(bg: Color(lightHex: "#FFF1CE", darkHex: "#33280F"), ink: Color(lightHex: "#B6862A", darkHex: "#ECC872"), solid: Color(lightHex: "#E8C067", darkHex: "#C8A04C"))
    static let social   = CatColors(bg: Color(lightHex: "#EBDCFA", darkHex: "#281D3E"), ink: Color(lightHex: "#7148AE", darkHex: "#C7ADEE"), solid: Color(lightHex: "#B697DE", darkHex: "#9B78CF"))
    static let rest     = CatColors(bg: Color(lightHex: "#DCEDD3", darkHex: "#1E2D17"), ink: Color(lightHex: "#5C8A45", darkHex: "#A9D293"), solid: Color(lightHex: "#9BC586", darkHex: "#7BAD61"))

    static let all: [(String, CatColors)] = [
        ("work", work), ("personal", personal), ("health", health),
        ("routine", routine), ("social", social), ("rest", rest),
    ]

    static func named(_ name: String) -> CatColors {
        switch name {
        case "work": return work
        case "personal": return personal
        case "health": return health
        case "routine": return routine
        case "social": return social
        case "rest": return rest
        default: return work
        }
    }

    /// Default icon for a category, chosen from the app's existing task icon
    /// vocabulary (ClaudeAPIClient.iconVocabulary) — used when a task is created
    /// by hand, where there's no AI to pick a fitting icon.
    static func icon(for category: String) -> String {
        switch category {
        case "work": return "laptopcomputer"
        case "personal": return "bag"
        case "health": return "figure.walk"
        case "routine": return "alarm"
        case "social": return "phone"
        case "rest": return "bed.double"
        default: return "doc.text"
        }
    }

    /// Icons safe to refresh when the category changes (i.e. a category default
    /// or the old placeholder) — a custom / AI-chosen icon is left untouched.
    static let defaultIcons: Set<String> = [
        "laptopcomputer", "bag", "figure.walk", "alarm", "phone", "bed.double", "circle"
    ]
}

// MARK: - Shadows

enum TempaShadow {
    static func standard() -> some View {
        Color.clear.shadow(color: Color(red: 40/255, green: 30/255, blue: 20/255).opacity(0.06), radius: 12, x: 0, y: 8)
    }
}

extension Color {
    /// Drop-shadow tint — warm brown on light, deep black on dark.
    static let tempaShadowTint = Color.dynamic(
        Color(red: 40/255, green: 30/255, blue: 20/255),
        Color.black
    )
}

extension View {
    func tempaShadow() -> some View {
        self.shadow(color: Color.tempaShadowTint.opacity(0.06), radius: 12, x: 0, y: 8)
    }

    func tempaShadowSm() -> some View {
        self.shadow(color: Color.tempaShadowTint.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    func tempaShadowLg() -> some View {
        self.shadow(color: Color.tempaShadowTint.opacity(0.08), radius: 20, x: 0, y: 16)
    }

    func primaryButtonShadow() -> some View {
        self.shadow(color: Color(hex: "#FF7A59").opacity(0.32), radius: 8, x: 0, y: 6)
    }

    func secondaryButtonShadow() -> some View {
        self.shadow(color: Color(hex: "#4EC8B0").opacity(0.28), radius: 8, x: 0, y: 6)
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// A color that resolves differently for light vs dark interface style,
    /// driven automatically by the system appearance.
    static func dynamic(_ light: Color, _ dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    /// Adaptive color from two hex strings (light, dark).
    init(lightHex: String, darkHex: String) {
        self = .dynamic(Color(hex: lightHex), Color(hex: darkHex))
    }
}

// MARK: - Sonar Pulse

/// Smooth sonar pulse: rings ease outward + fade, a soft glow breathes, the core
/// has a gentle heartbeat. Driven by a single `TimelineView(.animation)` (one
/// continuous time source) instead of many `repeatForever` animations — no
/// reset-"pop" and far lighter on the GPU (smooth on older devices like iPhone 14).
struct SonarPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var coreSize: CGFloat = 46
    var ringSize: CGFloat = 92
    var maxScale: CGFloat = 2.0
    var tint: Color = T.primary
    var coreShadow: Color = Color(hex: "#FF7A59").opacity(0.4)

    var body: some View {
        Group {
            if reduceMotion {
                ZStack {
                    ForEach([1.6, 1.15, 0.82] as [CGFloat], id: \.self) { s in
                        Circle().stroke(tint.opacity(0.28), lineWidth: 1.5)
                            .frame(width: ringSize, height: ringSize)
                            .scaleEffect(s)
                    }
                    core
                }
            } else {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    ZStack {
                        Circle().fill(tint.opacity(0.12))
                            .frame(width: ringSize * 1.05, height: ringSize * 1.05)
                            .scaleEffect(0.9 + 0.22 * CGFloat(0.5 + 0.5 * sin(t * 1.4)))

                        ForEach(0..<3, id: \.self) { i in
                            let phase = ((t / 2.8) + Double(i) / 3.0).truncatingRemainder(dividingBy: 1)
                            Circle().stroke(tint.opacity(0.5), lineWidth: 1.5)
                                .frame(width: ringSize, height: ringSize)
                                .scaleEffect(0.7 + (maxScale - 0.7) * CGFloat(phase))
                                .opacity((1 - phase) * 0.55 * min(phase * 6, 1))
                        }

                        core.scaleEffect(1 + 0.07 * CGFloat(0.5 + 0.5 * sin(t * 2.0)))
                    }
                }
            }
        }
        .frame(width: ringSize * maxScale, height: ringSize * maxScale)
    }

    private var core: some View {
        Circle().fill(tint)
            .frame(width: coreSize, height: coreSize)
            .shadow(color: coreShadow, radius: coreSize * 0.3, x: 0, y: coreSize * 0.17)
    }
}

// MARK: - TempaButton

struct TempaButton: View {
    let label: String
    var variant: Variant = .primary
    var size: Size = .lg
    var fullWidth: Bool = false
    var showArrow: Bool = false
    var action: () -> Void = {}

    enum Variant { case primary, secondary, ghost, soft, dark }
    enum Size { case lg, md, sm }

    private var height: CGFloat {
        switch size { case .lg: 56; case .md: 48; case .sm: 36 }
    }
    private var fontSize: CGFloat {
        switch size { case .lg: 17; case .md: 15; case .sm: 13 }
    }
    private var hPad: CGFloat {
        switch size { case .lg: 24; case .md: 20; case .sm: 14 }
    }
    private var radius: CGFloat {
        switch size { case .lg: 16; case .md: 14; case .sm: 10 }
    }

    private var bgColor: Color {
        switch variant {
        case .primary: T.primary
        case .secondary: T.secondary
        case .ghost: .clear
        case .soft: Color(hex: "#FFE9E1")
        case .dark: T.text
        }
    }
    private var fgColor: Color {
        switch variant {
        case .primary, .secondary, .dark: .white
        case .ghost: T.text
        case .soft: T.primaryDeep
        }
    }

    var body: some View {
        Button {
            #if os(iOS)
            switch variant {
            case .primary, .secondary, .dark:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .ghost, .soft:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            #endif
            action()
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.custom("Nunito-ExtraBold", size: fontSize))
                    .tracking(-0.2)
                if showArrow {
                    Image(systemName: "arrow.right")
                        .font(.system(size: fontSize - 3, weight: .bold))
                }
            }
            .foregroundColor(fgColor)
            .frame(height: height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, hPad)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if variant == .ghost {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(T.textTer, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .modifier(ButtonShadow(variant: variant))
    }
}

private struct ButtonShadow: ViewModifier {
    let variant: TempaButton.Variant
    func body(content: Content) -> some View {
        switch variant {
        case .primary:
            content.shadow(color: Color(hex: "#FF7A59").opacity(0.32), radius: 8, x: 0, y: 6)
        case .secondary:
            content.shadow(color: Color(hex: "#4EC8B0").opacity(0.28), radius: 8, x: 0, y: 6)
        case .dark:
            content.shadow(color: Color(hex: "#2A2A33").opacity(0.18), radius: 8, x: 0, y: 6)
        default:
            content
        }
    }
}

// MARK: - TempaWaveform

/// The signature "tempo" equalizer — a bell-shaped row of bars that gently
/// breathe. Driven by TimelineView so it animates smoothly AND keeps running
/// even when Reduce Motion is on (it's a soft equalizer, not vestibular motion).
struct TempaWaveform: View {
    var color: Color = T.primary
    var bars: Int = 15
    var maxHeight: CGFloat = 110
    var barWidth: CGFloat = 7
    var spacing: CGFloat = 7

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.04)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(0..<bars, id: \.self) { i in
                    let env = sin(Double.pi * Double(i) / Double(max(bars - 1, 1)))   // bell
                    let wave = (sin(t * 2.2 + Double(i) * 0.55) + 1) / 2               // travelling
                    let h = 0.13 * maxHeight + env * (0.30 * maxHeight + wave * 0.57 * maxHeight)
                    Capsule()
                        .fill(color.opacity(0.25 + env * 0.40))
                        .frame(width: barWidth, height: h)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - PulseDot

struct PulseDot: View {
    var size: CGFloat = 14
    var color: Color = T.primary
    var rings: Int = 2
    var speed: Double = 3

    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<rings, id: \.self) { i in
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: size, height: size)
                    .scaleEffect(animate ? 1.3 : 0.95)
                    .opacity(animate ? 0 : 0.5)
                    .animation(
                        .easeOut(duration: speed)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * (speed / Double(rings))),
                        value: animate
                    )
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .onAppear { animate = true }
    }
}

// MARK: - TempaScreen wrapper

struct TempaScreen<Content: View>: View {
    var bg: Color = T.bg
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            content()
        }
    }
}
