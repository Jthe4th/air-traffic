import Foundation

public struct GeoPoint: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 85 && abs(longitude) <= 180
    }
}

/// Great-circle and local-plane math. Distances are nautical miles, angles are degrees.
public enum Geo {
    public static let earthRadiusNM = 3440.065
    public static let metersPerNM = 1852.0
    public static let milesPerNM = 1.150779
    public static let kmPerNM = 1.852

    @inline(__always) static func rad(_ d: Double) -> Double { d * .pi / 180 }
    @inline(__always) static func deg(_ r: Double) -> Double { r * 180 / .pi }

    public static func distanceNM(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let dLat = rad(b.latitude - a.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(rad(a.latitude)) * cos(rad(b.latitude)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusNM * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from a to b, 0..<360.
    public static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let lat1 = rad(a.latitude), lat2 = rad(b.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalize(deg(atan2(y, x)))
    }

    public static func destination(from p: GeoPoint, bearing: Double, distanceNM: Double) -> GeoPoint {
        let d = distanceNM / earthRadiusNM
        let brg = rad(bearing)
        let lat1 = rad(p.latitude), lon1 = rad(p.longitude)
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brg))
        let lon2 = lon1 + atan2(sin(brg) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        return GeoPoint(latitude: deg(lat2), longitude: normalizeLongitude(deg(lon2)))
    }

    /// Signed cross-track distance of `p` from the great circle a→b (positive = right of course).
    public static func crossTrackNM(of p: GeoPoint, from a: GeoPoint, to b: GeoPoint) -> Double {
        let d13 = distanceNM(a, p) / earthRadiusNM
        let t13 = rad(bearing(from: a, to: p))
        let t12 = rad(bearing(from: a, to: b))
        return asin(max(-1, min(1, sin(d13) * sin(t13 - t12)))) * earthRadiusNM
    }

    /// Distance along the great circle a→b of the foot of the perpendicular from `p`. Negative before `a`.
    public static func alongTrackNM(of p: GeoPoint, from a: GeoPoint, to b: GeoPoint) -> Double {
        let d13 = distanceNM(a, p) / earthRadiusNM
        let xt = crossTrackNM(of: p, from: a, to: b) / earthRadiusNM
        let t13 = rad(bearing(from: a, to: p))
        let t12 = rad(bearing(from: a, to: b))
        let along = acos(max(-1, min(1, cos(d13) / max(1e-12, cos(xt))))) * earthRadiusNM
        return cos(t13 - t12) >= 0 ? along : -along
    }

    /// East/north offset of `p` from `origin`, in nautical miles (flat-earth; fine inside ~200 NM).
    public static func offsetNM(from origin: GeoPoint, to p: GeoPoint) -> (east: Double, north: Double) {
        let north = (p.latitude - origin.latitude) * 60
        let east = (p.longitude - origin.longitude) * 60 * cos(rad((p.latitude + origin.latitude) / 2))
        return (east, north)
    }

    public static func normalize(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    static func normalizeLongitude(_ lon: Double) -> Double {
        var l = lon
        while l > 180 { l -= 360 }
        while l < -180 { l += 360 }
        return l
    }

    /// Smallest absolute difference between two bearings, 0...180.
    public static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(normalize(a) - normalize(b))
        return d > 180 ? 360 - d : d
    }

    private static let points16 = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                                   "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    public static func compass(_ degrees: Double) -> String {
        points16[Int((normalize(degrees) / 22.5).rounded()) % 16]
    }

    /// Angle above the horizon for an object `altitudeFt` above the observer at ground distance `distanceNM`.
    public static func elevationAngle(heightFt: Double, groundDistanceNM: Double) -> Double {
        let heightNM = heightFt / 6076.12
        // Earth curvature drops the apparent height by d²/2R.
        let apparent = heightNM - (groundDistanceNM * groundDistanceNM) / (2 * earthRadiusNM)
        return deg(atan2(apparent, max(groundDistanceNM, 0.001)))
    }

    /// Angle above the horizon of something `heightKm` up, seen from `groundDistanceNM` away along the surface, on a round Earth.
    /// For high things such as satellites; `elevationAngle` is the simpler version for aircraft, which allows for curvature only roughly.
    public static func sphericalElevation(heightKm: Double, groundDistanceNM: Double) -> Double {
        let radius = earthRadiusNM * kmPerNM
        let central = groundDistanceNM * kmPerNM / radius
        let r = radius + heightKm
        return deg(atan2(r * cos(central) - radius, r * sin(central)))
    }
}

public struct ClosestApproach: Hashable, Sendable {
    /// Seconds from now until closest approach. Negative if the aircraft is already moving away.
    public var seconds: Double
    public var distanceNM: Double
    public var movingAway: Bool { seconds <= 0 }
}

extension Geo {
    /// Straight-line closest approach to the observer, assuming constant track and speed.
    public static func closestApproach(east: Double, north: Double, trackDeg: Double, speedKt: Double) -> ClosestApproach? {
        guard speedKt > 20 else { return nil }
        let vx = speedKt * sin(rad(trackDeg)), vy = speedKt * cos(rad(trackDeg)) // NM per hour
        let v2 = vx * vx + vy * vy
        let tHours = -(east * vx + north * vy) / v2
        let cx = east + vx * tHours, cy = north + vy * tHours
        return ClosestApproach(seconds: tHours * 3600, distanceNM: (cx * cx + cy * cy).squareRoot())
    }
}
