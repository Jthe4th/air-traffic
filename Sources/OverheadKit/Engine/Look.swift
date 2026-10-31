import Foundation

/// A quarter of the room, as seen from the viewer's seat.
public enum Sector: String, CaseIterable, Codable, Sendable, Identifiable {
    case ahead, right, behind, left

    public var id: String { rawValue }

    /// `relativeDeg` is measured clockwise from the way the viewer faces, so 90 is their right.
    public init(relativeDeg: Double) {
        switch Int(Geo.normalize(relativeDeg + 45) / 90) {
        case 0: self = .ahead
        case 1: self = .right
        case 2: self = .behind
        default: self = .left
        }
    }

    var plainPhrase: String {
        switch self {
        case .ahead: "Ahead of you"
        case .right: "On your right"
        case .behind: "Behind you"
        case .left: "On your left"
        }
    }
}

/// What the viewer calls each quarter of the room ("Back door", "Kitchen window"). Blank uses the plain wording.
public struct DirectionNames: Codable, Equatable, Sendable {
    public var ahead = ""
    public var right = ""
    public var behind = ""
    public var left = ""

    public init() {}

    enum CodingKeys: String, CodingKey { case ahead, right, behind, left }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ahead = try c.decodeIfPresent(String.self, forKey: .ahead) ?? ""
        right = try c.decodeIfPresent(String.self, forKey: .right) ?? ""
        behind = try c.decodeIfPresent(String.self, forKey: .behind) ?? ""
        left = try c.decodeIfPresent(String.self, forKey: .left) ?? ""
    }

    public subscript(sector: Sector) -> String {
        get {
            switch sector {
            case .ahead: ahead
            case .right: right
            case .behind: behind
            case .left: left
            }
        }
        set {
            switch sector {
            case .ahead: ahead = newValue
            case .right: right = newValue
            case .behind: behind = newValue
            case .left: left = newValue
            }
        }
    }

    /// The viewer's own name for this quarter, capitalised, or nil if they left it blank.
    public func name(for sector: Sector) -> String? {
        let trimmed = self[sector].trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(1)).uppercased() + trimmed.dropFirst()
    }
}

/// How an aircraft will cross the sky during its pass. Whichever way the viewer faces, a plane whose compass bearing is
/// increasing travels left to right as they turn to look at it.
public enum PassMotion: Hashable, Sendable {
    case leftToRight, rightToLeft
    /// Passes within a few hundred feet of straight overhead, so left and right mean nothing.
    case overhead(headingDeg: Double)

    /// Straight-line prediction from a position (east/north of the viewer, in NM) and a track.
    public static func predict(east: Double, north: Double, trackDeg: Double) -> PassMotion {
        let vx = sin(Geo.rad(trackDeg)), vy = cos(Geo.rad(trackDeg))
        // For a unit velocity this is the signed distance of the straight track from the viewer, constant along the track.
        let offset = north * vx - east * vy
        if abs(offset) < 0.2 { return .overhead(headingDeg: trackDeg) }
        return offset > 0 ? .leftToRight : .rightToLeft
    }
}

/// Where in the sky to look, from the viewer's seat.
public struct LookDirection: Hashable, Sendable {
    /// Compass bearing from the viewer to the aircraft.
    public var bearingDeg: Double
    /// Angle above the horizon.
    public var elevationDeg: Double
    /// Compass direction the viewer faces while watching TV, if they have said.
    public var headingDeg: Double?
    public var motion: PassMotion?
    /// The aircraft's own track, used to point its silhouette.
    public var trackDeg: Double?

    public init(bearingDeg: Double, elevationDeg: Double, headingDeg: Double? = nil, motion: PassMotion? = nil, trackDeg: Double? = nil) {
        self.bearingDeg = Geo.normalize(bearingDeg)
        self.elevationDeg = max(0, min(90, elevationDeg))
        self.headingDeg = headingDeg.map(Geo.normalize)
        self.motion = motion
        self.trackDeg = trackDeg
    }

    /// Degrees clockwise from the way the viewer faces, -180...180. Nil until they have said which way that is.
    public var relativeDeg: Double? {
        headingDeg.map { let r = Geo.normalize(bearingDeg - $0); return r > 180 ? r - 360 : r }
    }

    public var sector: Sector? { relativeDeg.map(Sector.init(relativeDeg:)) }

    /// Close enough to the zenith that a direction means little.
    public var isOverhead: Bool { elevationDeg >= 80 }

    /// "Behind you", "Back door" (the viewer's own name), or a compass direction when they have not said which way they face.
    public func place(names: DirectionNames = DirectionNames()) -> String {
        if isOverhead { return "Almost straight overhead" }
        guard let sector else { return "To the \(Geo.compassName(bearingDeg))" }
        return names.name(for: sector) ?? sector.plainPhrase
    }

    /// How high to look.
    public var height: String? {
        switch elevationDeg {
        case ..<10: "right at the horizon"
        case ..<30: "low in the sky"
        case ..<55: "partway up"
        case ..<80: "high up"
        default: nil
        }
    }

    public var motionText: String? {
        switch motion {
        case .leftToRight: "moving left to right"
        case .rightToLeft: "moving right to left"
        case .overhead(let heading): "heading \(Geo.compassName(heading))"
        case nil: nil
        }
    }
}

extension Geo {
    private static let names16 = ["north", "north-northeast", "northeast", "east-northeast", "east", "east-southeast", "southeast",
                                  "south-southeast", "south", "south-southwest", "southwest", "west-southwest", "west", "west-northwest",
                                  "northwest", "north-northwest"]

    /// "northwest", "south-southeast": the 16-point compass in words.
    public static func compassName(_ degrees: Double) -> String {
        names16[Int((normalize(degrees) / 22.5).rounded()) % 16]
    }
}
