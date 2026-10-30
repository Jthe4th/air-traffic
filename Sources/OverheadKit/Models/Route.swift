import Foundation

public struct Airport: Hashable, Sendable, Codable {
    public var icao: String
    public var iata: String?
    public var name: String
    public var city: String
    public var countryCode: String
    public var location: GeoPoint
    public var elevationFt: Double?

    public init(icao: String, iata: String?, name: String, city: String, countryCode: String, location: GeoPoint, elevationFt: Double? = nil) {
        self.icao = icao; self.iata = iata; self.name = name; self.city = city
        self.countryCode = countryCode; self.location = location; self.elevationFt = elevationFt
    }

    /// Three-letter code travellers recognise, falling back to ICAO.
    public var code: String { iata ?? icao }
}

public struct FlightRoute: Hashable, Sendable, Codable {
    public var origin: Airport
    public var destination: Airport
    /// Other stops on a multi-leg callsign (not the leg being flown).
    public var otherStops: [Airport]
    public var flightNumber: String?

    public init(origin: Airport, destination: Airport, otherStops: [Airport] = [], flightNumber: String? = nil) {
        self.origin = origin; self.destination = destination; self.otherStops = otherStops; self.flightNumber = flightNumber
    }

    public var lengthNM: Double { Geo.distanceNM(origin.location, destination.location) }

    public struct Progress: Hashable, Sendable {
        public var fraction: Double
        public var flownNM: Double
        public var remainingNM: Double
        public var etaSeconds: Double?
    }

    public func progress(position: GeoPoint, groundSpeedKt: Double?) -> Progress {
        let total = max(lengthNM, 1)
        let along = Geo.alongTrackNM(of: position, from: origin.location, to: destination.location)
        let remaining = Geo.distanceNM(position, destination.location)
        let flown = Geo.distanceNM(origin.location, position)
        let fraction = min(max(along / total, 0), 1)
        let eta = (groundSpeedKt ?? 0) > 60 ? remaining / groundSpeedKt! * 3600 : nil
        return Progress(fraction: fraction, flownNM: flown, remainingNM: remaining, etaSeconds: eta)
    }
}

public struct AircraftPhoto: Hashable, Sendable {
    public var imageURL: URL
    public var pageURL: URL?
    public var photographer: String?

    public init(imageURL: URL, pageURL: URL? = nil, photographer: String? = nil) {
        self.imageURL = imageURL; self.pageURL = pageURL; self.photographer = photographer
    }
}
