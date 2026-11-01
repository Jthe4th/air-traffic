import Foundation

/// Where a satellite is at one moment, in the terms the rest of the app uses for aircraft.
public struct OrbitSample: Equatable, Sendable {
    public var date: Date
    /// The point on the ground directly below.
    public var subpoint: GeoPoint
    public var altitudeKm: Double
    /// Speed through space (the figure usually quoted: about 7.66 km/s for the Space Station).
    public var orbitalSpeedKmS: Double
    /// How fast the point below moves over the ground, so a map marker can glide between updates.
    public var groundSpeedKt: Double
    /// Compass direction the point below is moving.
    public var trackDeg: Double
    public var isSunlit: Bool
}

/// A satellite orbit that can be asked where the satellite is, and what it looks like from the ground.
public struct SatelliteOrbit: Sendable {
    public let elements: OrbitalElements
    /// How bright it is at 1,000 km and half lit (smaller is brighter); the Space Station's figure unless told otherwise.
    public let standardMagnitude: Double
    private let model: SGP4

    /// Nil when the element set describes an orbit SGP4 cannot model.
    public init?(_ elements: OrbitalElements, standardMagnitude: Double = SpaceObject.iss.standardMagnitude) {
        guard let model = SGP4(elements) else { return nil }
        self.elements = elements
        self.standardMagnitude = standardMagnitude
        self.model = model
    }

    public func sample(at date: Date) -> OrbitSample? {
        guard let state = model.propagate(at: date) else { return nil }
        let fixed = Sky.ecef(position: state.position, velocity: state.velocity, at: date)
        let g = Sky.geodetic(fixed.position)
        let observer = Sky.Observer(GeoPoint(latitude: g.latitudeDeg, longitude: g.longitudeDeg))
        let east = observer.east(fixed.velocity), north = observer.north(fixed.velocity)
        let earthKm = Geo.earthRadiusNM * Geo.kmPerNM
        let groundKmS = hypot(east, north) * earthKm / (earthKm + g.altitudeKm)
        let track = atan2(east, north) * 180 / .pi
        return OrbitSample(
            date: date, subpoint: GeoPoint(latitude: g.latitudeDeg, longitude: g.longitudeDeg), altitudeKm: g.altitudeKm,
            orbitalSpeedKmS: state.velocity.length, groundSpeedKt: groundKmS * 3600 / Geo.kmPerNM,
            trackDeg: track < 0 ? track + 360 : track, isSunlit: Sky.isSunlit(state.position, sunDirection: Sky.sunDirection(date)))
    }

    /// What the satellite looks like from `observer` at `date`: where it is in the sky, whether the Sun lights it, whether the
    /// sky is dark there, and how bright it would appear.
    func view(from observer: Sky.Observer, at date: Date) -> SkyView? {
        guard let state = model.propagate(at: date) else { return nil }
        let position = Sky.rotateToEarthFixed(state.position, at: date)
        let look = observer.look(at: position)
        let sun = Sky.sunDirection(date)
        return SkyView(azimuthDeg: look.azimuthDeg, elevationDeg: look.elevationDeg, rangeKm: look.rangeKm,
                       isSunlit: Sky.isSunlit(state.position, sunDirection: sun),
                       sunElevationDeg: observer.elevation(ofDirection: Sky.rotateToEarthFixed(sun, at: date)),
                       magnitude: Self.magnitude(satellite: position, observer: observer.position,
                                                 sun: Sky.rotateToEarthFixed(sun, at: date), rangeKm: look.rangeKm,
                                                 standard: standardMagnitude))
    }

    /// Height and direction only: the cheap part, for scanning many moments.
    func look(from observer: Sky.Observer, at date: Date) -> (azimuthDeg: Double, elevationDeg: Double)? {
        guard let state = model.propagate(at: date) else { return nil }
        let look = observer.look(at: Sky.rotateToEarthFixed(state.position, at: date))
        return (look.azimuthDeg, look.elevationDeg)
    }

    /// Apparent magnitude (smaller is brighter) for a satellite of the given standard magnitude (at 1,000 km range and half lit),
    /// corrected for distance and for how much of its sunlit side faces the observer.
    static func magnitude(satellite: Vec3, observer: Vec3, sun: Vec3, rangeKm: Double, standard: Double) -> Double {
        let toObserver = (observer - satellite).unit
        let phase = acos(max(-1, min(1, sun.dot(toObserver))))
        let illumination = sin(phase) + (.pi - phase) * cos(phase)
        return standard + 5 * log10(rangeKm / 1000) - 2.5 * log10(max(illumination, 1e-3))
    }
}

struct SkyView: Sendable {
    var azimuthDeg: Double
    var elevationDeg: Double
    var rangeKm: Double
    var isSunlit: Bool
    var sunElevationDeg: Double
    var magnitude: Double
}
