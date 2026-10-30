import Foundation

public protocol RouteProviding: Sendable {
    /// A validated route for this aircraft, or nil when unknown or implausible.
    func route(for aircraft: Aircraft) async -> FlightRoute?
}

public protocol PhotoProviding: Sendable {
    func photo(for aircraft: Aircraft) async -> AircraftPhoto?
}

public struct NoPhotos: PhotoProviding {
    public init() {}
    public func photo(for aircraft: Aircraft) async -> AircraftPhoto? { nil }
}

// MARK: - Routes (ADSB.lol / Virtual Radar Server "standing data")

public actor StandingDataRouteProvider: RouteProviding {
    private struct Entry {
        var airports: [Airport]?   // nil = confirmed unknown
        var fetched: Date
    }

    private var cache: [String: Entry] = [:]
    private var inFlight: Set<String> = []
    private var nextRequest = Date.distantPast
    private let baseURL = URL(string: "https://vrs-standing-data.adsb.lol/routes")!

    public init() {}

    public func route(for aircraft: Aircraft) async -> FlightRoute? {
        guard let callsign = aircraft.displayCallsign?.uppercased(), Airlines.split(callsign: callsign) != nil else { return nil }
        let airports = await airports(forCallsign: callsign)
        guard let airports,
              let leg = RouteValidator.plausibleLeg(airports: airports, for: aircraft)
        else { return nil }
        let others = airports.filter { $0.icao != leg.origin.icao && $0.icao != leg.destination.icao }
        return FlightRoute(origin: leg.origin, destination: leg.destination, otherStops: others,
                           flightNumber: Airlines.flightNumber(forCallsign: callsign))
    }

    private func airports(forCallsign callsign: String) async -> [Airport]? {
        if let entry = cache[callsign] {
            let ttl: TimeInterval = entry.airports == nil ? 3600 : 12 * 3600
            if Date().timeIntervalSince(entry.fetched) < ttl { return entry.airports }
        }
        guard !inFlight.contains(callsign) else { return nil }
        inFlight.insert(callsign)
        defer { inFlight.remove(callsign) }

        // Be polite to a free static host: one request at a time, spaced out.
        let wait = nextRequest.timeIntervalSinceNow
        nextRequest = Date().addingTimeInterval(max(wait, 0) + 0.4)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }

        let url = baseURL.appending(path: String(callsign.prefix(2))).appending(path: "\(callsign).json")
        var request = URLRequest(url: url)
        request.setValue(ClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await HTTP.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { cache[callsign] = Entry(airports: nil, fetched: Date()); return nil }
            guard status == 200 else { return nil }
            let parsed = Self.parse(data)
            cache[callsign] = Entry(airports: parsed, fetched: Date())
            return parsed
        } catch {
            return nil   // transient; try again on a later poll
        }
    }

    static func parse(_ data: Data) -> [Airport]? {
        struct Payload: Decodable {
            struct A: Decodable {
                var name: String?, icao: String?, iata: String?, location: String?, countryiso2: String?
                var lat: Double?, lon: Double?, alt_feet: Double?
            }
            var _airports: [A]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let airports: [Airport] = (payload._airports ?? []).compactMap { a in
            guard let icao = a.icao, let lat = a.lat, let lon = a.lon else { return nil }
            let iata = (a.iata?.isEmpty ?? true) ? nil : a.iata
            return Airport(icao: icao, iata: iata, name: a.name ?? icao, city: a.location ?? icao,
                           countryCode: a.countryiso2 ?? "", location: GeoPoint(latitude: lat, longitude: lon),
                           elevationFt: a.alt_feet)
        }
        return airports.count >= 2 ? airports : nil
    }
}

// MARK: - Photos (Planespotters public API)

public actor PlanespottersPhotoProvider: PhotoProviding {
    private struct Entry { var photo: AircraftPhoto?; var fetched: Date }
    private var cache: [String: Entry] = [:]
    private var inFlight: Set<String> = []

    public init() {}

    public func photo(for aircraft: Aircraft) async -> AircraftPhoto? {
        // Planespotters requires a User-Agent that identifies the app and a way to contact its author.
        guard ClientIdentity.hasContact else { return nil }
        let hex = aircraft.hex
        if let entry = cache[hex] {
            let ttl: TimeInterval = entry.photo == nil ? 6 * 3600 : 7 * 24 * 3600
            if Date().timeIntervalSince(entry.fetched) < ttl { return entry.photo }
        }
        guard !inFlight.contains(hex) else { return nil }
        inFlight.insert(hex)
        defer { inFlight.remove(hex) }

        var request = URLRequest(url: URL(string: "https://api.planespotters.net/pub/photos/hex/\(hex)")!)
        request.setValue(ClientIdentity.photoUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await HTTP.session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let photo = Self.parse(data)
            cache[hex] = Entry(photo: photo, fetched: Date())
            return photo
        } catch {
            return nil
        }
    }

    static func parse(_ data: Data) -> AircraftPhoto? {
        struct Payload: Decodable {
            struct Photo: Decodable {
                struct Thumb: Decodable { var src: String }
                var thumbnail_large: Thumb?
                var link: String?
                var photographer: String?
            }
            var photos: [Photo]?
        }
        guard let first = (try? JSONDecoder().decode(Payload.self, from: data))?.photos?.first,
              let src = first.thumbnail_large?.src, let url = URL(string: src) else { return nil }
        return AircraftPhoto(imageURL: url, pageURL: first.link.flatMap(URL.init(string:)), photographer: first.photographer)
    }
}

// MARK: - Place search (Open-Meteo geocoding)

public struct Place: Hashable, Sendable, Identifiable {
    public var name: String
    public var region: String?
    public var country: String?
    public var countryCode: String?
    public var location: GeoPoint
    public var id: String { "\(name)|\(location.latitude)|\(location.longitude)" }

    public init(name: String, region: String? = nil, country: String? = nil, countryCode: String? = nil, location: GeoPoint) {
        self.name = name; self.region = region; self.country = country; self.countryCode = countryCode; self.location = location
    }

    public var subtitle: String { [region, country].compactMap { $0 }.joined(separator: ", ") }
    /// "Silver Spring, Maryland" (country only when there is no region).
    public var fullName: String {
        let tail = region ?? country
        return tail.map { "\(name), \($0)" } ?? name
    }
}

/// Finds places by name or postal code. Understands "City, ST", "City ST", "City, State" and "City, Country".
public enum PlaceSearch {
    public static func search(_ query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let (name, region) = interpret(trimmed)
        // The geocoder only searches by name, so with a region hint fetch plenty and filter locally.
        let results = try await fetch(name: name, count: region == nil ? 8 : 40)
        guard let region else { return results }
        let matches = rank(results, region: region)
        return Array((matches.isEmpty ? results : matches).prefix(8))
    }

    /// Splits a query into a place name and an optional region hint.
    static func interpret(_ query: String) -> (name: String, region: String?) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = q.firstIndex(of: ",") {
            let name = q[..<comma].trimmingCharacters(in: .whitespaces)
            let hint = q[q.index(after: comma)...].split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
            if name.count >= 2 { return (name, (hint?.isEmpty ?? true) ? nil : hint) }
        }
        // "Silver Spring MD": a trailing two-letter state or province code.
        let tokens = q.split(separator: " ")
        if tokens.count >= 2, let last = tokens.last, last.count == 2, regionNames[last.uppercased()] != nil {
            let name = tokens.dropLast().joined(separator: " ")
            if name.count >= 2 { return (name, String(last)) }
        }
        return (q, nil)
    }

    /// Keeps the places whose state/province or country matches the hint, preserving the geocoder's ordering.
    static func rank(_ places: [Place], region: String) -> [Place] {
        let hint = region.lowercased()
        let expanded = regionNames[region.uppercased()]?.lowercased()
        let countryAliases = ["usa": "US", "us": "US", "united states": "US", "uk": "GB", "united kingdom": "GB", "england": "GB"]
        return places.filter { p in
            let admin = p.region?.lowercased() ?? ""
            let country = p.country?.lowercased() ?? ""
            if let expanded, admin == expanded { return true }
            if admin == hint || country == hint { return true }
            if hint.count >= 3, admin.hasPrefix(hint) || country.hasPrefix(hint) { return true }
            if let code = countryAliases[hint], p.countryCode == code { return true }
            // A bare two-letter hint that isn't a state or province is probably a country code ("Paris, FR").
            if expanded == nil, hint.count == 2, p.countryCode == hint.uppercased() { return true }
            return false
        }
    }

    private static func fetch(name: String, count: Int) async throws -> [Place] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: name), .init(name: "count", value: String(count)),
            .init(name: "language", value: "en"), .init(name: "format", value: "json"),
        ]
        let (data, _) = try await HTTP.liveSession.data(from: components.url!)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> [Place] {
        struct Payload: Decodable {
            struct R: Decodable {
                var name: String; var latitude: Double; var longitude: Double
                var admin1: String?; var country: String?; var country_code: String?
            }
            var results: [R]?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return (payload.results ?? []).map {
            Place(name: $0.name, region: $0.admin1, country: $0.country, countryCode: $0.country_code,
                  location: GeoPoint(latitude: $0.latitude, longitude: $0.longitude))
        }
    }

    static let regionNames: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
        "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia",
        "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
        "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts",
        "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
        "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
        "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
        "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "PR": "Puerto Rico",
        "AB": "Alberta", "BC": "British Columbia", "MB": "Manitoba", "NB": "New Brunswick",
        "NL": "Newfoundland and Labrador", "NS": "Nova Scotia", "NT": "Northwest Territories", "NU": "Nunavut",
        "ON": "Ontario", "PE": "Prince Edward Island", "QC": "Quebec", "SK": "Saskatchewan", "YT": "Yukon",
    ]
}
