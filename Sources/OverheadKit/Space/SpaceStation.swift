import Foundation

/// Where the app gets the Space Station's orbit. Only the object's public catalogue number is sent, never a location.
public protocol OrbitalElementsProviding: Sendable {
    func stationElements() async throws -> OrbitalElements
}

public struct CelesTrakProvider: OrbitalElementsProviding {
    public static let url = URL(string: "https://celestrak.org/NORAD/elements/gp.php?CATNR=\(SpaceStation.catalogNumber)&FORMAT=TLE")!

    public init() {}

    public func stationElements() async throws -> OrbitalElements {
        var request = URLRequest(url: Self.url)
        request.setValue(ClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await HTTP.liveSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw FeedError.http(http.statusCode) }
        guard let text = String(data: data, encoding: .utf8), let elements = OrbitalElements.parse(text),
              elements.catalogNumber == SpaceStation.catalogNumber else { throw FeedError.malformed }
        return elements
    }
}

/// The last orbit downloaded, kept so a restart or an outage does not lose the predictions.
enum StationElementsCache {
    private static let key = "station.elements.v1"
    private struct Stored: Codable { var elements: OrbitalElements; var fetchedAt: Date }

    static func load() -> (elements: OrbitalElements, fetchedAt: Date)? {
        guard let data = UserDefaults.standard.data(forKey: key), let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        return (stored.elements, stored.fetchedAt)
    }

    static func save(_ elements: OrbitalElements, fetchedAt: Date) {
        if let data = try? JSONEncoder().encode(Stored(elements: elements, fetchedAt: fetchedAt)) { UserDefaults.standard.set(data, forKey: key) }
    }
}

public enum SpaceStation {
    public static let catalogNumber = 25544
    public static let name = "International Space Station"
    public static let shortName = "Space Station"
    /// The station's identifier in the aircraft list.
    public static let id = "ISS"
    /// Elements older than this are too far from their epoch to trust for a visual prediction.
    public static let maximumElementAge: TimeInterval = 14 * 86_400

    /// The station as a tracked object, so the map, nearby strip and detail card can show it like an aircraft.
    static func aircraft(from sample: OrbitSample, periodMinutes: Double) -> Aircraft {
        Aircraft(hex: id, callsign: "ISS", typeCode: "ISS", position: sample.subpoint, positionTime: sample.date,
                 geometricAltitudeFt: Int((sample.altitudeKm * 3280.84).rounded()), groundSpeedKt: sample.groundSpeedKt,
                 trackDeg: sample.trackDeg, verticalRateFpm: 0, wakeClass: .spaceVehicle,
                 spacecraft: SpacecraftInfo(name: name, altitudeKm: sample.altitudeKm, orbitalSpeedKmS: sample.orbitalSpeedKmS,
                                            periodMinutes: periodMinutes, isSunlit: sample.isSunlit))
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

/// The card announcing a visible pass: when it starts, where to look, and how bright it will be.
public struct StationPassCard: Identifiable, Equatable, Sendable {
    public var pass: SatellitePass
    public var asOf: Date
    public var isSample = false

    public init(pass: SatellitePass, asOf: Date, isSample: Bool = false) {
        self.pass = pass; self.asOf = asOf; self.isSample = isSample
    }

    public var id: Int { pass.id }
    public var name: String { SpaceStation.name }

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
        if isSample && phase != .underway { return "Sample · Space Station pass" }
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
