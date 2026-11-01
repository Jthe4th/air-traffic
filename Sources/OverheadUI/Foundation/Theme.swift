import SwiftUI
import OverheadKit

/// Visual language: near-black glass over a dark map, white type, one sky-blue accent,
/// and altitude as the only colour on the map itself.
enum Theme {
    static let ink = Color(red: 0.035, green: 0.043, blue: 0.055)
    static let text = Color.white
    static let secondary = Color.white.opacity(0.66)
    static let tertiary = Color.white.opacity(0.42)
    static let hairline = Color.white.opacity(0.10)
    static let accent = Color(red: 0.40, green: 0.80, blue: 1.0)
    static let climb = Color(red: 0.45, green: 0.92, blue: 0.58)
    static let descend = Color(red: 1.0, green: 0.64, blue: 0.32)
    static let warning = Color(red: 1.0, green: 0.76, blue: 0.28)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.36)
    /// The Space Station's colour wherever aircraft take their colour from altitude: warm white, like sunlit metal.
    static let station = Color(red: 1.0, green: 0.93, blue: 0.62)

    // Typography. Serif for names and places, rounded for numbers, small caps for labels.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded).monospacedDigit() }
    static func body(_ size: CGFloat, weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight) }
    static let label: Font = .system(size: 21, weight: .semibold)

    private static let altitudeStops: [(ft: Double, rgb: (Double, Double, Double))] = [
        (0, (1.00, 0.56, 0.24)), (3_000, (1.00, 0.78, 0.28)), (8_000, (0.56, 0.88, 0.42)),
        (15_000, (0.26, 0.86, 0.78)), (25_000, (0.30, 0.66, 1.00)), (35_000, (0.56, 0.52, 1.00)), (45_000, (0.82, 0.46, 1.00)),
    ]

    static func altitudeColor(_ ft: Double?, onGround: Bool = false) -> Color {
        if onGround { return Color(red: 0.55, green: 0.58, blue: 0.63) }
        guard let ft else { return Color(red: 0.6, green: 0.65, blue: 0.7) }
        let stops = altitudeStops
        if ft <= stops[0].ft { return rgb(stops[0].rgb) }
        for i in 1..<stops.count where ft <= stops[i].ft {
            let a = stops[i - 1], b = stops[i]
            let f = (ft - a.ft) / (b.ft - a.ft)
            return rgb((a.rgb.0 + (b.rgb.0 - a.rgb.0) * f, a.rgb.1 + (b.rgb.1 - a.rgb.1) * f, a.rgb.2 + (b.rgb.2 - a.rgb.2) * f))
        }
        return rgb(stops.last!.rgb)
    }

    static func tint(_ a: Aircraft, at now: Date) -> Color {
        a.isSpacecraft ? station : altitudeColor(a.altitudeFt(at: now), onGround: a.onGround)
    }

    private static func rgb(_ c: (Double, Double, Double)) -> Color { Color(red: c.0, green: c.1, blue: c.2) }

    static func color(hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static func isLight(hex: UInt32) -> Bool {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 170
    }
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = 34
    var tint: Color = .black.opacity(0.42)

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(tint))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.04)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.45), radius: 36, y: 16)
        }
    }
}

extension View {
    func glassCard(radius: CGFloat = 34, tint: Color = .black.opacity(0.42)) -> some View {
        modifier(GlassCard(radius: radius, tint: tint))
    }

    /// Small-caps style label used above every value.
    func labelStyle(_ color: Color = Theme.tertiary) -> some View {
        self.font(Theme.label).tracking(1.6).textCase(.uppercase).foregroundStyle(color)
    }
}

/// Bare button: no system chrome and, on tvOS, no built-in focus lift. Views read `isFocused` and draw their own focus state.
struct FlatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
