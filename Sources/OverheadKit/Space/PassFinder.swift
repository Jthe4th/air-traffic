import Foundation

/// A stretch of sky time when a satellite can be seen with the naked eye: above the horizon, lit by the Sun, while the viewer's
/// sky is dark.
public struct SatellitePass: Equatable, Sendable, Identifiable {
    public struct Point: Equatable, Sendable {
        public var date: Date
        public var azimuthDeg: Double
        public var elevationDeg: Double
    }

    /// Where and when it comes into view: rising above the horizon, or coming out of Earth's shadow.
    public var start: Point
    public var peak: Point
    /// Where and when it is lost: setting, or going into Earth's shadow.
    public var end: Point
    /// The path across the sky, a point every few seconds, for drawing.
    public var path: [Point]
    /// The brightest it gets (a smaller number is brighter; Venus is about -4).
    public var brightestMagnitude: Double
    public var startsOutOfShadow: Bool
    public var endsInShadow: Bool

    public var id: Int { Int(start.date.timeIntervalSince1970) }
    public var duration: TimeInterval { end.date.timeIntervalSince(start.date) }
}

public enum PassFinder {
    /// Below this height trees, rooftops and haze hide a satellite.
    public static let horizonDeg = 10.0
    /// The Sun must be this far below the horizon: the end of civil twilight, when the sky is dark enough for a bright satellite.
    public static let darkSkyDeg = -6.0

    /// The visible passes between two moments, soonest first. A pass is kept only if it climbs to `minimumPeakDeg` and lasts
    /// at least half a minute, so the list holds passes worth going outside for. A pass already under way at `start` begins there.
    public static func visiblePasses(of orbit: SatelliteOrbit, from home: GeoPoint, between start: Date, and end: Date,
                                     minimumPeakDeg: Double = 20, step: TimeInterval = 20) -> [SatellitePass] {
        let observer = Sky.Observer(home)

        /// Cheap height test first; the Sun and shadow only matter once the satellite is high enough to see.
        func visible(_ date: Date) -> Bool {
            guard let look = orbit.look(from: observer, at: date), look.elevationDeg >= horizonDeg,
                  let view = orbit.view(from: observer, at: date) else { return false }
            return view.isSunlit && view.sunElevationDeg < darkSkyDeg
        }
        func boundary(inside: Date, outside: Date) -> Date {
            var a = inside, b = outside
            for _ in 0..<9 {
                let mid = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2)
                if visible(mid) { a = mid } else { b = mid }
            }
            return a
        }

        var passes: [SatellitePass] = []
        var t = start
        var previous = visible(t), previousTime = t
        var begin: Date? = previous ? t : nil
        while t < end {
            t = t.addingTimeInterval(step)
            let now = visible(t)
            if now && !previous { begin = boundary(inside: t, outside: previousTime) }
            if !now && previous, let startedAt = begin {
                if let pass = makePass(orbit, observer, from: startedAt, to: boundary(inside: previousTime, outside: t),
                                       minimumPeakDeg: minimumPeakDeg) { passes.append(pass) }
                begin = nil
            }
            previous = now; previousTime = t
        }
        if previous, let startedAt = begin, let pass = makePass(orbit, observer, from: startedAt, to: previousTime, minimumPeakDeg: minimumPeakDeg) {
            passes.append(pass)
        }
        return passes
    }

    private static func makePass(_ orbit: SatelliteOrbit, _ observer: Sky.Observer, from begin: Date, to finish: Date,
                                 minimumPeakDeg: Double) -> SatellitePass? {
        guard finish.timeIntervalSince(begin) >= 30 else { return nil }
        func point(_ date: Date) -> SatellitePass.Point? {
            orbit.look(from: observer, at: date).map { .init(date: date, azimuthDeg: $0.azimuthDeg, elevationDeg: $0.elevationDeg) }
        }
        guard let first = point(begin), let last = point(finish) else { return nil }

        var peak = first, brightest = Double.infinity
        var path: [SatellitePass.Point] = [first]
        var t = begin
        var sinceSample = 0.0
        while t < finish {
            t = min(t.addingTimeInterval(2), finish)
            sinceSample += 2
            guard let p = point(t) else { continue }
            if p.elevationDeg > peak.elevationDeg { peak = p }
            if sinceSample >= 10 || t >= finish {
                path.append(p)
                sinceSample = 0
                if let view = orbit.view(from: observer, at: t) { brightest = min(brightest, view.magnitude) }
            }
        }
        guard peak.elevationDeg >= minimumPeakDeg, brightest.isFinite else { return nil }

        // Why it starts and stops: a moment either side tells whether the satellite was in the sky but in shadow.
        func hiddenOnlyByShadow(_ date: Date) -> Bool {
            guard let view = orbit.view(from: observer, at: date) else { return false }
            return view.elevationDeg >= horizonDeg && !view.isSunlit && view.sunElevationDeg < darkSkyDeg
        }
        return SatellitePass(start: first, peak: peak, end: last, path: path, brightestMagnitude: brightest,
                             startsOutOfShadow: hiddenOnlyByShadow(begin.addingTimeInterval(-6)),
                             endsInShadow: hiddenOnlyByShadow(finish.addingTimeInterval(6)))
    }
}
