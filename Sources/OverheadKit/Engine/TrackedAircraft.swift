import Foundation

public struct TrailPoint: Hashable, Sendable {
    public var position: GeoPoint
    public var altitudeFt: Double?
    public var time: Date
}

/// Where the search for an aircraft's route has got to.
public enum RouteStatus: Sendable {
    case checking
    case found
    /// A database lists a route for the callsign, but this aircraft doesn't fit it (callsigns are reused).
    case unconfirmed
    case unavailable
}

/// An aircraft plus everything we've learned about it while it's been in range.
public struct TrackedAircraft: Identifiable, Hashable, Sendable {
    public var aircraft: Aircraft
    public var route: FlightRoute?
    public var routeStatus = RouteStatus.checking
    public var photo: AircraftPhoto?
    public var trail: [TrailPoint] = []
    public var firstSeen: Date
    public var maxAltitudeFt: Int?

    var routeCheckedAt: Date?
    var photoRequested = false

    public var id: String { aircraft.hex }

    init(aircraft: Aircraft, firstSeen: Date) {
        self.aircraft = aircraft
        self.firstSeen = firstSeen
    }

    mutating func update(with new: Aircraft) {
        let moved = trail.last.map { Geo.distanceNM($0.position, new.position) > 0.02 } ?? true
        if moved && new.positionTime > (trail.last?.time ?? .distantPast) {
            trail.append(TrailPoint(position: new.position, altitudeFt: new.altitudeFt.map(Double.init), time: new.positionTime))
            if trail.count > 150 { trail.removeFirst(trail.count - 150) }
        }
        aircraft = new
        if let alt = new.altitudeFt { maxAltitudeFt = max(maxAltitudeFt ?? alt, alt) }
    }

    // MARK: Display helpers

    public var airline: Airline? { Airlines.airline(forCallsign: aircraft.callsign) }
    public var typeInfo: AircraftTypeInfo? { AircraftTypes.info(for: aircraft.typeCode) }

    /// "Boeing 737 MAX 8" — our friendly name, falling back to the feed's description, then the bare code.
    public var typeName: String? {
        typeInfo?.name ?? aircraft.typeDescription?.capitalizedWords ?? aircraft.typeCode
    }

    public var flightNumber: String? { route?.flightNumber ?? Airlines.flightNumber(forCallsign: aircraft.callsign) }

    public var operatorName: String? {
        airline?.name ?? aircraft.operatorName?.capitalizedWords
    }

    public var kindDescription: String? {
        typeInfo?.kind.rawValue ?? aircraft.wakeClass.title
    }
}

extension String {
    /// "UNITED AIRLINES INC" → "United Airlines Inc". Tokens with digits (737, ERJ-170) and known acronyms stay as-is.
    public var capitalizedWords: String {
        let keep: Set<String> = ["LLC", "LP", "USA", "US", "UK", "FBO"]
        return split(separator: " ").map { word -> String in
            if word.contains(where: \.isNumber) || keep.contains(String(word)) { return String(word) }
            return word.lowercased().capitalized
        }.joined(separator: " ")
    }
}

public struct Sighting: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(hex)-\(Int(firstSeen.timeIntervalSince1970))" }
    public var hex: String
    public var title: String
    public var airline: String?
    public var typeName: String?
    public var routeText: String?
    public var firstSeen: Date
    public var lastSeen: Date
    public var closestNM: Double
    public var altitudeFt: Int?
}
