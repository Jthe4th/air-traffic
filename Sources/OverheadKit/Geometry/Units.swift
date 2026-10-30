import Foundation

public enum UnitSystem: String, CaseIterable, Codable, Sendable, Identifiable {
    case imperial, metric, aviation

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .imperial: "Miles · feet · mph"
        case .metric: "Kilometres · metres · km/h"
        case .aviation: "Nautical miles · feet · knots"
        }
    }

    /// How many of this system's distance unit fit in one nautical mile.
    public var perNM: Double {
        switch self {
        case .imperial: Geo.milesPerNM
        case .metric: Geo.kmPerNM
        case .aviation: 1
        }
    }

    public struct Quantity: Hashable, Sendable {
        public var value: String
        public var unit: String
        public var text: String { "\(value) \(unit)" }
    }

    private static func int(_ v: Double) -> String {
        v.rounded().formatted(.number.precision(.fractionLength(0)))
    }

    private static func short(_ v: Double) -> String {
        if v >= 100 { return int(v) }
        return v.formatted(.number.precision(.fractionLength(v < 10 ? 1 : 0)))
    }

    public func distance(nm: Double) -> Quantity {
        switch self {
        case .imperial: Quantity(value: Self.short(nm * Geo.milesPerNM), unit: "mi")
        case .metric: Quantity(value: Self.short(nm * Geo.kmPerNM), unit: "km")
        case .aviation: Quantity(value: Self.short(nm), unit: "NM")
        }
    }

    /// Long distances (route totals): no decimals.
    public func longDistance(nm: Double) -> Quantity {
        switch self {
        case .imperial: Quantity(value: Self.int(nm * Geo.milesPerNM), unit: "mi")
        case .metric: Quantity(value: Self.int(nm * Geo.kmPerNM), unit: "km")
        case .aviation: Quantity(value: Self.int(nm), unit: "NM")
        }
    }

    public func altitude(ft: Double) -> Quantity {
        switch self {
        case .metric: Quantity(value: Self.int(ft * 0.3048), unit: "m")
        default: Quantity(value: Self.int(ft), unit: "ft")
        }
    }

    public func speed(kt: Double) -> Quantity {
        switch self {
        case .imperial: Quantity(value: Self.int(kt * Geo.milesPerNM), unit: "mph")
        case .metric: Quantity(value: Self.int(kt * Geo.kmPerNM), unit: "km/h")
        case .aviation: Quantity(value: Self.int(kt), unit: "kt")
        }
    }

    public func verticalRate(fpm: Double) -> Quantity {
        switch self {
        case .metric: Quantity(value: Self.int(abs(fpm) * 0.00508), unit: "m/s")
        default: Quantity(value: Self.int(abs(fpm)), unit: "ft/min")
        }
    }

    public func temperature(celsius: Double) -> Quantity {
        switch self {
        case .imperial: Quantity(value: Self.int(celsius * 9 / 5 + 32), unit: "°F")
        default: Quantity(value: Self.int(celsius), unit: "°C")
        }
    }
}

public func flightLevelText(altitudeFt: Int) -> String? {
    altitudeFt >= 18_000 ? "FL\(altitudeFt / 100)" : nil
}

public func clockInterval(_ seconds: Double) -> String {
    let s = Int(max(0, seconds).rounded())
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

public func humanInterval(_ seconds: Double) -> String {
    let s = Int(max(0, seconds).rounded())
    if s >= 3600 { return "\(s / 3600) h \((s % 3600) / 60) min" }
    if s >= 60 { return "\(s / 60) min" }
    return "\(s) s"
}
