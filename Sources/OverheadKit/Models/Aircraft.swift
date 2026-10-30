import Foundation

public struct DatabaseFlags: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let military = DatabaseFlags(rawValue: 1)
    public static let interesting = DatabaseFlags(rawValue: 2)
    public static let pia = DatabaseFlags(rawValue: 4)
    public static let ladd = DatabaseFlags(rawValue: 8)
}

/// ADS-B emitter category, as broadcast by the aircraft (A0–A7, B1–B7, C1–C3).
public enum WakeClass: String, Sendable {
    case light, small, large, highVortex, heavy, highPerformance, rotorcraft, glider, lighterThanAir, parachutist, ultralight, uav, spaceVehicle, surfaceVehicle, unknown

    public init(category: String?) {
        switch category {
        case "A1": self = .light
        case "A2": self = .small
        case "A3": self = .large
        case "A4": self = .highVortex
        case "A5": self = .heavy
        case "A6": self = .highPerformance
        case "A7": self = .rotorcraft
        case "B1": self = .glider
        case "B2": self = .lighterThanAir
        case "B3": self = .parachutist
        case "B4": self = .ultralight
        case "B6": self = .uav
        case "B7": self = .spaceVehicle
        case "C1", "C2", "C3": self = .surfaceVehicle
        default: self = .unknown
        }
    }

    public var title: String? {
        switch self {
        case .light: "Light (< 15,500 lb)"
        case .small: "Small (15,500–75,000 lb)"
        case .large: "Large (75,000–300,000 lb)"
        case .highVortex: "High-vortex large"
        case .heavy: "Heavy (> 300,000 lb)"
        case .highPerformance: "High performance"
        case .rotorcraft: "Rotorcraft"
        case .glider: "Glider"
        case .lighterThanAir: "Balloon"
        case .parachutist: "Skydiver"
        case .ultralight: "Ultralight"
        case .uav: "Unmanned"
        case .spaceVehicle: "Space vehicle"
        case .surfaceVehicle: "Ground vehicle"
        case .unknown: nil
        }
    }
}

/// One decoded ADS-B/Mode-S position report plus whatever the feed knows about the airframe.
public struct Aircraft: Identifiable, Hashable, Sendable {
    public var id: String { hex }
    public let hex: String
    public var callsign: String?
    public var registration: String?
    public var typeCode: String?
    public var typeDescription: String?
    public var operatorName: String?
    public var yearBuilt: Int?

    public var position: GeoPoint
    /// Time the position was actually valid (feed time minus position age).
    public var positionTime: Date
    public var onGround: Bool
    public var barometricAltitudeFt: Int?
    public var geometricAltitudeFt: Int?
    public var groundSpeedKt: Double?
    public var trackDeg: Double?
    public var verticalRateFpm: Int?
    public var squawk: String?
    public var emergency: String?
    public var wakeClass: WakeClass
    public var flags: DatabaseFlags

    public var mach: Double?
    public var indicatedAirspeedKt: Double?
    public var trueAirspeedKt: Double?
    public var trueHeadingDeg: Double?
    public var magneticHeadingDeg: Double?
    public var rollDeg: Double?
    public var selectedAltitudeFt: Int?
    public var selectedHeadingDeg: Double?
    public var autopilotModes: [String]
    public var windDirectionDeg: Double?
    public var windSpeedKt: Double?
    public var outsideAirTempC: Double?
    public var sourceType: String?

    public init(
        hex: String, callsign: String? = nil, registration: String? = nil, typeCode: String? = nil,
        typeDescription: String? = nil, operatorName: String? = nil, yearBuilt: Int? = nil,
        position: GeoPoint, positionTime: Date, onGround: Bool = false,
        barometricAltitudeFt: Int? = nil, geometricAltitudeFt: Int? = nil, groundSpeedKt: Double? = nil,
        trackDeg: Double? = nil, verticalRateFpm: Int? = nil, squawk: String? = nil, emergency: String? = nil,
        wakeClass: WakeClass = .unknown, flags: DatabaseFlags = [], mach: Double? = nil,
        indicatedAirspeedKt: Double? = nil, trueAirspeedKt: Double? = nil, trueHeadingDeg: Double? = nil,
        magneticHeadingDeg: Double? = nil, rollDeg: Double? = nil, selectedAltitudeFt: Int? = nil,
        selectedHeadingDeg: Double? = nil, autopilotModes: [String] = [], windDirectionDeg: Double? = nil,
        windSpeedKt: Double? = nil, outsideAirTempC: Double? = nil, sourceType: String? = nil
    ) {
        self.hex = hex; self.callsign = callsign; self.registration = registration; self.typeCode = typeCode
        self.typeDescription = typeDescription; self.operatorName = operatorName; self.yearBuilt = yearBuilt
        self.position = position; self.positionTime = positionTime; self.onGround = onGround
        self.barometricAltitudeFt = barometricAltitudeFt; self.geometricAltitudeFt = geometricAltitudeFt
        self.groundSpeedKt = groundSpeedKt; self.trackDeg = trackDeg; self.verticalRateFpm = verticalRateFpm
        self.squawk = squawk; self.emergency = emergency; self.wakeClass = wakeClass; self.flags = flags
        self.mach = mach; self.indicatedAirspeedKt = indicatedAirspeedKt; self.trueAirspeedKt = trueAirspeedKt
        self.trueHeadingDeg = trueHeadingDeg; self.magneticHeadingDeg = magneticHeadingDeg; self.rollDeg = rollDeg
        self.selectedAltitudeFt = selectedAltitudeFt; self.selectedHeadingDeg = selectedHeadingDeg
        self.autopilotModes = autopilotModes; self.windDirectionDeg = windDirectionDeg
        self.windSpeedKt = windSpeedKt; self.outsideAirTempC = outsideAirTempC; self.sourceType = sourceType
    }

    public var altitudeFt: Int? { onGround ? 0 : (barometricAltitudeFt ?? geometricAltitudeFt) }
    public var isMoving: Bool { (groundSpeedKt ?? 0) > 5 }

    /// Dead-reckoned position, so markers glide between 5-second feed updates.
    public func position(at date: Date) -> GeoPoint {
        guard let gs = groundSpeedKt, let track = trackDeg, gs > 5 else { return position }
        let dt = min(max(date.timeIntervalSince(positionTime), 0), 60)
        return Geo.destination(from: position, bearing: track, distanceNM: gs * dt / 3600)
    }

    /// Altitude at `date`, following the reported vertical rate.
    public func altitudeFt(at date: Date) -> Double? {
        guard !onGround, let alt = altitudeFt else { return onGround ? 0 : nil }
        guard let rate = verticalRateFpm else { return Double(alt) }
        let dt = min(max(date.timeIntervalSince(positionTime), 0), 30)
        return Double(alt) + Double(rate) * dt / 60
    }

    /// Callsign with trailing padding removed. Nil for blank.
    public var displayCallsign: String? {
        guard let c = callsign?.trimmingCharacters(in: .whitespaces), !c.isEmpty else { return nil }
        return c
    }

    public var title: String { displayCallsign ?? registration ?? hex.uppercased() }
}

/// Where an aircraft is relative to the viewer, at a moment in time.
public struct Relative: Hashable, Sendable {
    public var distanceNM: Double
    public var bearingDeg: Double
    public var elevationDeg: Double?
    public var closestApproach: ClosestApproach?
    public var approaching: Bool?
}

extension Aircraft {
    public func relative(to home: GeoPoint, at date: Date) -> Relative {
        let p = position(at: date)
        let d = Geo.distanceNM(home, p)
        let brg = Geo.bearing(from: home, to: p)
        let alt = altitudeFt(at: date)
        let elev = alt.map { Geo.elevationAngle(heightFt: $0, groundDistanceNM: d) }
        var cpa: ClosestApproach?
        var approaching: Bool?
        if let track = trackDeg, let gs = groundSpeedKt, gs > 20, !onGround {
            let off = Geo.offsetNM(from: home, to: p)
            cpa = Geo.closestApproach(east: off.east, north: off.north, trackDeg: track, speedKt: gs)
            approaching = cpa.map { !$0.movingAway }
        }
        return Relative(distanceNM: d, bearingDeg: brg, elevationDeg: elev, closestApproach: cpa, approaching: approaching)
    }
}
