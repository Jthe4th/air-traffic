import Foundation

/// Time, frames, the Sun and Earth's shadow: the geometry between a satellite's TEME position and an observer on the ground.
enum Sky {
    static let equatorialRadiusKm = 6378.137
    static let flattening = 1 / 298.257223563
    /// Earth's rotation relative to the stars, radians per second.
    static let rotationRate = 7.2921150e-5

    static func julianDate(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + 2_440_587.5 }

    /// Greenwich mean sidereal time in radians (IAU 1982), which turns inertial TEME coordinates into Earth-fixed ones.
    /// Taking UTC for UT1 is off by under a second, about 0.004° of rotation.
    static func gmst(_ date: Date) -> Double {
        let t = (julianDate(date) - 2_451_545.0) / 36_525
        let seconds = -6.2e-6 * t * t * t + 0.093104 * t * t + (876_600.0 * 3600 + 8_640_184.812866) * t + 67_310.54841
        let radians = (seconds * .pi / 180 / 240).truncatingRemainder(dividingBy: 2 * .pi)
        return radians < 0 ? radians + 2 * .pi : radians
    }

    /// Earth-fixed position and velocity (the velocity relative to the rotating ground) from TEME.
    static func ecef(position r: Vec3, velocity v: Vec3, at date: Date) -> (position: Vec3, velocity: Vec3) {
        let theta = gmst(date), c = cos(theta), s = sin(theta)
        let p = Vec3(x: c * r.x + s * r.y, y: -s * r.x + c * r.y, z: r.z)
        let rotated = Vec3(x: c * v.x + s * v.y, y: -s * v.x + c * v.y, z: v.z)
        return (p, Vec3(x: rotated.x + rotationRate * p.y, y: rotated.y - rotationRate * p.x, z: rotated.z))
    }

    static func rotateToEarthFixed(_ r: Vec3, at date: Date) -> Vec3 {
        let theta = gmst(date), c = cos(theta), s = sin(theta)
        return Vec3(x: c * r.x + s * r.y, y: -s * r.x + c * r.y, z: r.z)
    }

    /// Latitude and longitude in degrees and height above the WGS-84 ellipsoid in kilometres.
    static func geodetic(_ p: Vec3) -> (latitudeDeg: Double, longitudeDeg: Double, altitudeKm: Double) {
        let a = equatorialRadiusKm, e2 = flattening * (2 - flattening)
        let rho = hypot(p.x, p.y)
        var lat = atan2(p.z, rho * (1 - e2)), alt = 0.0
        for _ in 0..<6 {
            let s = sin(lat), n = a / (1 - e2 * s * s).squareRoot()
            alt = rho / cos(lat) - n
            lat = atan2(p.z, rho * (1 - e2 * n / (n + alt)))
        }
        return (lat * 180 / .pi, atan2(p.y, p.x) * 180 / .pi, alt)
    }

    /// A point on the ground, with the local east/north/up directions ready for repeated look-angle calculations.
    struct Observer: Sendable {
        let position: Vec3
        private let sinLat, cosLat, sinLon, cosLon: Double

        init(_ point: GeoPoint, altitudeKm: Double = 0) {
            let lat = point.latitude * .pi / 180, lon = point.longitude * .pi / 180
            sinLat = sin(lat); cosLat = cos(lat); sinLon = sin(lon); cosLon = cos(lon)
            let e2 = Sky.flattening * (2 - Sky.flattening)
            let n = Sky.equatorialRadiusKm / (1 - e2 * sinLat * sinLat).squareRoot()
            position = Vec3(x: (n + altitudeKm) * cosLat * cosLon, y: (n + altitudeKm) * cosLat * sinLon,
                            z: (n * (1 - e2) + altitudeKm) * sinLat)
        }

        func east(_ d: Vec3) -> Double { -sinLon * d.x + cosLon * d.y }
        func north(_ d: Vec3) -> Double { -sinLat * cosLon * d.x - sinLat * sinLon * d.y + cosLat * d.z }
        func up(_ d: Vec3) -> Double { cosLat * cosLon * d.x + cosLat * sinLon * d.y + sinLat * d.z }

        /// Compass bearing (degrees clockwise from north), height above the horizon and distance to an Earth-fixed point.
        func look(at target: Vec3) -> (azimuthDeg: Double, elevationDeg: Double, rangeKm: Double) {
            let d = target - position
            let range = d.length
            let azimuth = atan2(east(d), north(d)) * 180 / .pi
            return (azimuth < 0 ? azimuth + 360 : azimuth, asin(max(-1, min(1, up(d) / range))) * 180 / .pi, range)
        }

        /// Height of a direction (a unit vector in Earth-fixed coordinates) above the horizon, in degrees.
        func elevation(ofDirection d: Vec3) -> Double { asin(max(-1, min(1, up(d)))) * 180 / .pi }
    }

    /// A unit vector toward the Sun in the TEME frame (low-precision almanac formula, good to about 0.01°).
    static func sunDirection(_ date: Date) -> Vec3 {
        let n = julianDate(date) - 2_451_545.0
        let meanLongitude = (280.460 + 0.9856474 * n) * .pi / 180
        let anomaly = (357.528 + 0.9856003 * n) * .pi / 180
        let longitude = meanLongitude + (1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * .pi / 180
        let obliquity = (23.439 - 0.0000004 * n) * .pi / 180
        return Vec3(x: cos(longitude), y: cos(obliquity) * sin(longitude), z: sin(obliquity) * sin(longitude))
    }

    /// Sunlight reaches the satellite unless it is on the night side and inside Earth's cylindrical shadow.
    static func isSunlit(_ satellite: Vec3, sunDirection s: Vec3) -> Bool {
        let along = satellite.dot(s)
        if along >= 0 { return true }
        return (satellite - s * along).length > equatorialRadiusKm
    }
}
