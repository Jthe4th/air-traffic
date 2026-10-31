import Foundation

/// What counts as a flyby, taken from the viewer's settings.
public struct FlybyConfig: Equatable, Sendable {
    /// Closest approach must be within this distance (nautical miles, horizontal).
    public var distanceNM: Double
    /// Aircraft above this altitude are ignored. 0 means any altitude.
    public var maxAltitudeFt: Int
    /// Show the card this long before the closest approach, so there is time to get to a window.
    public var leadSeconds: Double = 45
    /// And keep it this long after, so a plane that just passed can still be found.
    public var graceSeconds: Double = 15

    /// A card already on screen is judged a little more loosely, so a plane on a turn doesn't flicker in and out.
    var relaxed: FlybyConfig {
        FlybyConfig(distanceNM: distanceNM * 1.25, maxAltitudeFt: maxAltitudeFt == 0 ? 0 : Int(Double(maxAltitudeFt) * 1.1),
                    leadSeconds: leadSeconds + 10, graceSeconds: graceSeconds + 5)
    }
}

extension AppSettings {
    public var flybyConfig: FlybyConfig? {
        flybyCards ? FlybyConfig(distanceNM: flybyDistanceNM, maxAltitudeFt: flybyMaxAltitudeFt) : nil
    }
}

/// An aircraft that is about to pass, or has just passed, close to the viewer.
public struct FlybyPass: Hashable, Sendable {
    public var distanceNM: Double
    /// Straight-line closest approach, if the aircraft is moving fast enough to predict one.
    public var closestNM: Double?
    /// Seconds until that closest approach; negative once it has passed.
    public var secondsToClosest: Double?
    public var altitudeFt: Int
    public var look: LookDirection
}

public enum Flyby {
    public static func evaluate(_ a: Aircraft, home: GeoPoint, heading: Double?, at now: Date, config: FlybyConfig) -> FlybyPass? {
        guard !a.onGround, let altitude = a.altitudeFt(at: now) else { return nil }
        if config.maxAltitudeFt > 0, altitude > Double(config.maxAltitudeFt) { return nil }

        let rel = a.relative(to: home, at: now)
        if let cpa = rel.closestApproach {
            guard cpa.distanceNM <= config.distanceNM, cpa.seconds <= config.leadSeconds, cpa.seconds >= -config.graceSeconds else { return nil }
        } else {
            // Too slow to predict a pass (a helicopter hovering, say): it counts while it is close.
            guard rel.distanceNM <= config.distanceNM else { return nil }
        }

        var motion: PassMotion?
        if let track = a.trackDeg, let gs = a.groundSpeedKt, gs > 20 {
            let off = Geo.offsetNM(from: home, to: a.position(at: now))
            motion = PassMotion.predict(east: off.east, north: off.north, trackDeg: track)
        }
        let look = LookDirection(bearingDeg: rel.bearingDeg, elevationDeg: rel.elevationDeg ?? 45, headingDeg: heading,
                                 motion: motion, trackDeg: a.trackDeg)
        return FlybyPass(distanceNM: rel.distanceNM, closestNM: rel.closestApproach?.distanceNM,
                         secondsToClosest: rel.closestApproach?.seconds, altitudeFt: Int(altitude.rounded()), look: look)
    }
}

/// The card shown on screen: who is passing, when, and which way to look.
public struct FlybyCard: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String?
    public var pass: FlybyPass
    /// "Behind you", or the viewer's own name for that side of the room.
    public var place: String
    public var isSample = false

    public init(id: String, title: String, detail: String?, pass: FlybyPass, place: String, isSample: Bool = false) {
        self.id = id; self.title = title; self.detail = detail; self.pass = pass; self.place = place; self.isSample = isSample
    }

    public enum Phase: Sendable { case approaching, passing, passed, close }

    public var phase: Phase {
        guard let s = pass.secondsToClosest else { return .close }
        if s > 4 { return .approaching }
        return s >= -4 ? .passing : .passed
    }

    public var headline: String {
        if isSample { return "Sample · a plane due north" }
        switch phase {
        case .approaching:
            let seconds = Int((((pass.secondsToClosest ?? 0) / 5).rounded()) * 5)
            return "Passing close in about \(max(5, seconds)) seconds"
        case .passing: return "Passing close now"
        case .passed: return "Just passed"
        case .close: return "Close by"
        }
    }

    /// "high up · moving left to right"
    public var directionDetail: String {
        [pass.look.height, pass.look.motionText].compactMap { $0 }.joined(separator: " · ")
    }
}
