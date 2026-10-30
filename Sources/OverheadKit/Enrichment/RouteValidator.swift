import Foundation

/// Callsigns are reused (the route database says UAL2850 is SFO→ONT even when that callsign is flying
/// near Washington). A reported route is only shown if the aircraft's position and heading actually fit it.
public enum RouteValidator {
    public struct Leg: Sendable {
        public var origin: Airport
        public var destination: Airport
        public var crossTrackNM: Double
    }

    /// Best-fitting leg of a (possibly multi-stop) callsign for this aircraft, or nil if none fits.
    public static func plausibleLeg(airports: [Airport], for aircraft: Aircraft, at date: Date = Date()) -> Leg? {
        guard airports.count >= 2 else { return nil }
        var best: Leg?
        for i in 0..<(airports.count - 1) {
            if let leg = evaluate(origin: airports[i], destination: airports[i + 1], aircraft: aircraft, at: date) {
                if best == nil || leg.crossTrackNM < best!.crossTrackNM { best = leg }
            }
        }
        return best
    }

    public static func isPlausible(origin: Airport, destination: Airport, aircraft: Aircraft, at date: Date = Date()) -> Bool {
        evaluate(origin: origin, destination: destination, aircraft: aircraft, at: date) != nil
    }

    static func evaluate(origin o: Airport, destination d: Airport, aircraft: Aircraft, at date: Date) -> Leg? {
        let length = Geo.distanceNM(o.location, d.location)
        guard length > 10 else { return nil }
        let p = aircraft.position(at: date)
        let nearOrigin = Geo.distanceNM(p, o.location)
        let nearDestination = Geo.distanceNM(p, d.location)

        if aircraft.onGround {
            return (nearOrigin < 8 || nearDestination < 8) ? Leg(origin: o, destination: d, crossTrackNM: min(nearOrigin, nearDestination)) : nil
        }

        let cross = abs(Geo.crossTrackNM(of: p, from: o.location, to: d.location))
        let corridor = min(150, max(40, length * 0.10))
        let along = Geo.alongTrackNM(of: p, from: o.location, to: d.location)
        guard cross <= corridor, along >= -20, along <= length + 20 else { return nil }

        if let track = aircraft.trackDeg, (aircraft.groundSpeedKt ?? 0) > 80 {
            let toDestination = Geo.bearing(from: p, to: d.location)
            let diff = Geo.angleDifference(track, toDestination)
            // Departure and approach involve big turns; en route the track must point at the destination.
            let terminalArea = nearDestination < 30 || nearOrigin < 25
            if diff > (terminalArea ? 110 : 60) { return nil }
        }
        return Leg(origin: o, destination: d, crossTrackNM: cross)
    }
}
