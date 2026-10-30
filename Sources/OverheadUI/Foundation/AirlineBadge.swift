import SwiftUI
import OverheadKit

/// Monogram badge in the airline's brand colour. Real logos can replace this later without touching callers.
struct AirlineBadge: View {
    var airline: Airline?
    var fallbackText: String = ""
    var size: CGFloat = 64

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        let base: Color = airline.map { Theme.color(hex: $0.color) } ?? Color(red: 0.26, green: 0.30, blue: 0.36)
        let light = airline.map { Theme.isLight(hex: $0.color) } ?? false
        ZStack {
            shape.fill(LinearGradient(colors: [base.opacity(1), base.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(.white.opacity(0.22), lineWidth: 1.2)
            if let airline, airline.iata != "--" {
                Text(airline.iata)
                    .font(.system(size: size * 0.40, weight: .heavy, design: .rounded))
                    .foregroundStyle(light ? Color.black.opacity(0.82) : .white)
            } else if let airline {
                Text(String(airline.icao.prefix(3)))
                    .font(.system(size: size * 0.30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            } else if !fallbackText.isEmpty {
                Text(fallbackText)
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Image(systemName: "airplane")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
    }
}
