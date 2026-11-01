import Foundation

/// The crewed stations the app watches for: each crosses the sky as a bright, steady, fast-moving star.
public enum SpaceObject: String, CaseIterable, Sendable, Hashable {
    case iss, tiangong

    public var catalogNumber: Int {
        switch self {
        case .iss: 25544
        case .tiangong: 48274         // the Tianhe core module; the other modules are docked to it on the same orbit
        }
    }

    public var name: String {
        switch self {
        case .iss: "International Space Station"
        case .tiangong: "Tiangong Space Station"
        }
    }

    /// The name on cards and labels.
    public var shortName: String {
        switch self {
        case .iss: "Space Station"
        case .tiangong: "Tiangong"
        }
    }

    /// The station's identifier in the aircraft list, and the type code it is looked up by.
    public var id: String {
        switch self {
        case .iss: "ISS"
        case .tiangong: "CSS"
        }
    }

    /// What the map and strip call it.
    public var callsign: String {
        switch self {
        case .iss: "ISS"
        case .tiangong: "Tiangong"
        }
    }

    /// Apparent magnitude at 1,000 km range and half lit; smaller is brighter. The ISS figure is the one pass-prediction sites use.
    /// Tiangong's is an estimate, about 1.3 magnitudes fainter, from published typical peaks (about -2.6 against the ISS's -3.8).
    public var standardMagnitude: Double {
        switch self {
        case .iss: -1.8
        case .tiangong: -0.5
        }
    }

    /// The outline drawn for it on the map, in the strip and on its card.
    public var silhouette: AircraftKind.Silhouette { AircraftTypes.info(for: id)?.kind.silhouette ?? .station }

    /// A visible pass is only announced if it is at least this bright (a smaller number is brighter), so a faint pass does not send
    /// anyone outside for a dim star. The Space Station's passes are all bright enough to need no floor; Tiangong's low passes are not.
    public var announceBrighterThan: Double {
        switch self {
        case .iss: .infinity
        case .tiangong: -1.0
        }
    }

    public init?(catalogNumber: Int) {
        guard let match = Self.allCases.first(where: { $0.catalogNumber == catalogNumber }) else { return nil }
        self = match
    }

    /// Elements older than this are too far from their epoch to trust for a visual prediction.
    public static let maximumElementAge: TimeInterval = 14 * 86_400

    /// The station as a tracked object, so the map, nearby strip and detail card can show it like an aircraft.
    func aircraft(from sample: OrbitSample, periodMinutes: Double) -> Aircraft {
        Aircraft(hex: id, callsign: callsign, typeCode: id, position: sample.subpoint, positionTime: sample.date,
                 geometricAltitudeFt: Int((sample.altitudeKm * 3280.84).rounded()), groundSpeedKt: sample.groundSpeedKt,
                 trackDeg: sample.trackDeg, verticalRateFpm: 0, wakeClass: .spaceVehicle,
                 spacecraft: SpacecraftInfo(name: name, altitudeKm: sample.altitudeKm, orbitalSpeedKmS: sample.orbitalSpeedKmS,
                                            periodMinutes: periodMinutes, isSunlit: sample.isSunlit))
    }
}

/// Where the app gets a station's orbit. Only the object's public catalogue number is sent, never a location.
public protocol OrbitalElementsProviding: Sendable {
    func elements(for object: SpaceObject) async throws -> OrbitalElements
}

public struct CelesTrakProvider: OrbitalElementsProviding {
    public static func url(for object: SpaceObject) -> URL {
        URL(string: "https://celestrak.org/NORAD/elements/gp.php?CATNR=\(object.catalogNumber)&FORMAT=TLE")!
    }

    public init() {}

    public func elements(for object: SpaceObject) async throws -> OrbitalElements {
        var request = URLRequest(url: Self.url(for: object))
        request.setValue(ClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await HTTP.liveSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw FeedError.http(http.statusCode) }
        guard let text = String(data: data, encoding: .utf8), let elements = OrbitalElements.parse(text),
              elements.catalogNumber == object.catalogNumber else { throw FeedError.malformed }
        return elements
    }
}

/// The last orbit downloaded for each station, kept so a restart or an outage does not lose the predictions.
enum StationElementsCache {
    private struct Stored: Codable { var elements: OrbitalElements; var fetchedAt: Date }

    /// The ISS keeps the key from before there was a second station, so an existing cache is still found.
    private static func key(_ object: SpaceObject) -> String {
        object == .iss ? "station.elements.v1" : "station.elements.v1.\(object.catalogNumber)"
    }

    static func load(_ object: SpaceObject) -> (elements: OrbitalElements, fetchedAt: Date)? {
        guard let data = UserDefaults.standard.data(forKey: key(object)), let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.elements.catalogNumber == object.catalogNumber else { return nil }
        return (stored.elements, stored.fetchedAt)
    }

    static func save(_ elements: OrbitalElements, fetchedAt: Date, for object: SpaceObject) {
        if let data = try? JSONEncoder().encode(Stored(elements: elements, fetchedAt: fetchedAt)) { UserDefaults.standard.set(data, forKey: key(object)) }
    }
}

extension OrbitalElements {
    /// Minutes for one trip round the Earth.
    public var periodMinutes: Double { 2 * .pi / meanMotion }
}

/// What the Settings screen reports about the Space Station feature.
public enum StationStatus: Equatable, Sendable {
    case off
    case demo
    case waiting
    case ready(epoch: Date)
    case outdated(epoch: Date)
    case failed(String)
}

/// A sound the screen should make: a gentle heads-up when a pass is announced, a brighter one as it begins.
public struct StationChime: Equatable, Sendable {
    public enum Kind: Sendable { case headsUp, rising }
    public var kind: Kind
    public var serial: Int
}

/// A visible pass of one of the stations.
public struct StationPass: Identifiable, Equatable, Sendable {
    public var object: SpaceObject
    public var pass: SatellitePass

    public var id: String { "\(object.rawValue)-\(pass.id)" }
}

/// The card announcing a visible pass: when it starts, where to look, and how bright it will be.
public struct StationPassCard: Identifiable, Equatable, Sendable {
    public var object: SpaceObject
    public var pass: SatellitePass
    public var asOf: Date
    public var isSample = false

    public init(pass: SatellitePass, asOf: Date, object: SpaceObject = .iss, isSample: Bool = false) {
        self.object = object; self.pass = pass; self.asOf = asOf; self.isSample = isSample
    }

    public init(_ stationPass: StationPass, asOf: Date) { self.init(pass: stationPass.pass, asOf: asOf, object: stationPass.object) }

    public var id: String { "\(object.rawValue)-\(pass.id)" }
    public var name: String { object.name }

    public enum Phase: Sendable { case upcoming, imminent, underway, ended }

    public var secondsToStart: Double { pass.start.date.timeIntervalSince(asOf) }
    public var secondsToEnd: Double { pass.end.date.timeIntervalSince(asOf) }

    /// Upcoming is the long wait with a compact card; imminent is the last two minutes, when it is time to get outside.
    public var phase: Phase {
        if secondsToStart > 120 { return .upcoming }
        if secondsToStart > 0 { return .imminent }
        return secondsToEnd > 0 ? .underway : .ended
    }

    public var headline: String {
        if isSample && phase != .underway { return "Sample · \(object.shortName) pass" }
        switch phase {
        case .upcoming: return "Visible in \(Self.minutes(secondsToStart))"
        case .imminent: return "Appears in \(Self.countdown(secondsToStart))"
        case .underway: return "Visible now"
        case .ended: return "Just passed"
        }
    }

    /// "Rises in the southwest", "Appears high in the north" — where it first comes into view.
    public var appearsPlace: String { Self.place(pass.start) }
    public var highestPlace: String { Self.place(pass.peak) }
    public var endPlace: String { Self.place(pass.end) }

    /// The key moments with their clock times, for the full card. The highest point is left out when it is where the pass begins or ends.
    public struct Moment: Equatable, Sendable { public var label: String; public var time: String; public var place: String }

    public var moments: [Moment] {
        var out = [Moment(label: pass.start.elevationDeg < 15 && !pass.startsOutOfShadow ? "Rises" : "Appears",
                          time: Self.clock(pass.start.date), place: Self.place(pass.start))]
        if pass.peak.date.timeIntervalSince(pass.start.date) > 8, pass.end.date.timeIntervalSince(pass.peak.date) > 8 {
            out.append(Moment(label: "Highest", time: Self.clock(pass.peak.date), place: Self.place(pass.peak)))
        }
        out.append(Moment(label: pass.endsInShadow ? "Fades" : "Sets", time: Self.clock(pass.end.date),
                          place: Self.place(pass.end) + (pass.endsInShadow ? ", into Earth's shadow" : "")))
        return out
    }

    /// For the compact card: "SW to E".
    public var route: String { "\(Geo.compass(pass.start.azimuthDeg)) to \(Geo.compass(pass.end.azimuthDeg))" }

    public var durationText: String { humanInterval(pass.duration) }

    public var brightnessText: String {
        switch pass.brightestMagnitude {
        case ..<(-3.5): "Brilliant"
        case ..<(-2.5): "Very bright"
        case ..<(-1.5): "Bright"
        case ..<(-0.5): "Moderate"
        default: "Faint"
        }
    }

    public var peakDegrees: Int { Int(pass.peak.elevationDeg.rounded()) }

    static func place(_ point: SatellitePass.Point) -> String {
        "\(Geo.compassName(point.azimuthDeg)), \(height(point.elevationDeg))"
    }

    static func height(_ elevation: Double) -> String {
        switch elevation {
        case ..<20: "low"
        case ..<40: "partway up"
        case ..<70: "high"
        default: "almost overhead"
        }
    }

    /// "Today at 6:12 PM", "Tomorrow at 5:58 AM", "Thursday, Nov 5 at 6:12 PM".
    public static func whenText(for pass: SatellitePass, now: Date) -> String {
        let calendar = Calendar.current, date = pass.start.date
        let day: String
        if calendar.isDate(date, inSameDayAs: now) { day = "Today" }
        else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { day = "Tomorrow" }
        else { day = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
        return "\(day) at \(clock(date))"
    }

    static func clock(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }

    static func minutes(_ seconds: Double) -> String {
        let m = max(1, Int((seconds / 60).rounded(.up)))
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

    static func countdown(_ seconds: Double) -> String {
        if seconds >= 90 { return "\(Int((seconds / 60).rounded())) minutes" }
        return "about \(max(5, Int((seconds / 5).rounded()) * 5)) seconds"
    }
}
