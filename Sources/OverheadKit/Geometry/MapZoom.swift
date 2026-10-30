import Foundation

/// The map's zoom steps: round-number radii in whichever units the viewer reads.
public enum MapZoom {
    /// Radii in the viewer's own units, smallest (most zoomed in) first.
    public static func presets(for units: UnitSystem) -> [Double] {
        switch units {
        case .imperial: [5, 10, 25, 40, 60]
        case .metric: [10, 20, 40, 60, 100]
        case .aviation: [5, 10, 20, 35, 50]
        }
    }

    public static func presetsNM(for units: UnitSystem) -> [Double] {
        presets(for: units).map { $0 / units.perNM }
    }

    /// The next smaller radius, or nil when already at the closest zoom.
    public static func zoomedIn(from radiusNM: Double, units: UnitSystem) -> Double? {
        presetsNM(for: units).last { $0 < radiusNM - 0.05 }
    }

    /// The next larger radius, or nil when already at the widest zoom.
    public static func zoomedOut(from radiusNM: Double, units: UnitSystem) -> Double? {
        presetsNM(for: units).first { $0 > radiusNM + 0.05 }
    }

    /// The preset closest to a radius, for pickers.
    public static func nearestPreset(to radiusNM: Double, units: UnitSystem) -> Double {
        let current = radiusNM * units.perNM
        let all = presets(for: units)
        return all.min { abs($0 - current) < abs($1 - current) } ?? all[0]
    }

    /// Whole-number label such as "25 mi".
    public static func label(radiusNM: Double, units: UnitSystem) -> UnitSystem.Quantity {
        let unit = units.distance(nm: 1).unit
        return UnitSystem.Quantity(value: String(Int((radiusNM * units.perNM).rounded())), unit: unit)
    }
}
