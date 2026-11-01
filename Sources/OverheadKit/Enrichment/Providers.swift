import Foundation

/// What a route provider found out about one aircraft.
public enum RouteLookup: Equatable, Sendable {
    case found(FlightRoute)
    /// A database lists a route for this callsign, but the aircraft doesn't fit it: callsigns are reused for other trips.
    case unconfirmed
    /// No database has a route for this callsign.
    case unavailable
    /// Couldn't ask (offline, rate limited, or a busy lookup); worth trying again.
    case failed
}

public protocol RouteProviding: Sendable {
    /// A validated route for this aircraft, or the reason there isn't one.
    func lookup(for aircraft: Aircraft) async -> RouteLookup
}

public protocol PhotoProviding: Sendable {
    func photo(for aircraft: Aircraft) async -> AircraftPhoto?
}

public struct NoPhotos: PhotoProviding {
    public init() {}
    public func photo(for aircraft: Aircraft) async -> AircraftPhoto? { nil }
}

// MARK: - Routes

/// What one database said about a callsign.
enum CallsignAnswer: Equatable, Sendable {
    case airports([Airport])
    case unknown
    case failed
}

/// A database of routes keyed by callsign. Each holds a single static route per callsign, so what it says may be for another trip.
protocol CallsignSource: Sendable {
    func airports(forCallsign callsign: String) async -> CallsignAnswer
}

/// Asks each database in turn and keeps the first route the aircraft actually fits. Every answer goes through `RouteValidator`:
/// a route is never shown just because a database lists it.
public struct LiveRouteProvider: RouteProviding {
    private let sources: [any CallsignSource]

    public init() { sources = [StandingDataSource(), AdsbdbSource()] }
    init(sources: [any CallsignSource]) { self.sources = sources }

    public func lookup(for aircraft: Aircraft) async -> RouteLookup {
        guard let callsign = aircraft.displayCallsign?.uppercased(), Airlines.split(callsign: callsign) != nil else { return .unavailable }
        var listed = false, failed = false
        for source in sources {
            switch await source.airports(forCallsign: callsign) {
            case .airports(let airports):
                listed = true
                guard let leg = RouteValidator.plausibleLeg(airports: airports, for: aircraft) else { continue }
                let others = airports.filter { $0.icao != leg.origin.icao && $0.icao != leg.destination.icao }
                return .found(FlightRoute(origin: leg.origin, destination: leg.destination, otherStops: others,
                                          flightNumber: Airlines.flightNumber(forCallsign: callsign)))
            case .unknown: break
            case .failed: failed = true
            }
        }
        if listed { return .unconfirmed }
        return failed ? .failed : .unavailable
    }
}

/// Caches answers (a long time for a route, an hour for "unknown"), asks one at a time with a pause between, and backs off when
/// a free host says it is busy.
private struct AnswerCache {
    struct Entry { var airports: [Airport]?; var fetched: Date }
    var entries: [String: Entry] = [:]
    var inFlight: Set<String> = []
    var nextRequest = Date.distantPast

    func cached(_ callsign: String) -> CallsignAnswer? {
        guard let entry = entries[callsign] else { return nil }
        let ttl: TimeInterval = entry.airports == nil ? 3600 : 12 * 3600
        guard Date().timeIntervalSince(entry.fetched) < ttl else { return nil }
        return entry.airports.map { .airports($0) } ?? .unknown
    }

    /// How long to wait before this request, reserving the next slot `spacing` seconds on.
    mutating func reserveSlot(spacing: TimeInterval) -> TimeInterval {
        let wait = max(nextRequest.timeIntervalSinceNow, 0)
        nextRequest = Date().addingTimeInterval(wait + spacing)
        return wait
    }
}

// MARK: Routes (ADSB.lol / Virtual Radar Server "standing data")

actor StandingDataSource: CallsignSource {
    private var cache = AnswerCache()
    private let baseURL = URL(string: "https://vrs-standing-data.adsb.lol/routes")!

    func airports(forCallsign callsign: String) async -> CallsignAnswer {
        if let answer = cache.cached(callsign) { return answer }
        guard !cache.inFlight.contains(callsign) else { return .failed }
        cache.inFlight.insert(callsign)
        defer { cache.inFlight.remove(callsign) }

        // Be polite to a free static host: one request at a time, spaced out.
        let wait = cache.reserveSlot(spacing: 0.4)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }

        let url = baseURL.appending(path: String(callsign.prefix(2))).appending(path: "\(callsign).json")
        var request = URLRequest(url: url)
        request.setValue(ClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await HTTP.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { cache.entries[callsign] = .init(airports: nil, fetched: Date()); return .unknown }
            guard status == 200 else { return .failed }
            let parsed = Self.parse(data)
            cache.entries[callsign] = .init(airports: parsed, fetched: Date())
            return parsed.map { .airports($0) } ?? .unknown
        } catch {
            return .failed   // transient; try again on a later poll
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

// MARK: Routes (adsbdb.com, a second database that often knows callsigns the first doesn't)

actor AdsbdbSource: CallsignSource {
    private var cache = AnswerCache()
    private var coolOffUntil = Date.distantPast
    private let baseURL = URL(string: "https://api.adsbdb.com/v0/callsign")!

    func airports(forCallsign callsign: String) async -> CallsignAnswer {
        if let answer = cache.cached(callsign) { return answer }
        guard !cache.inFlight.contains(callsign), Date() >= coolOffUntil else { return .failed }
        cache.inFlight.insert(callsign)
        defer { cache.inFlight.remove(callsign) }

        let wait = cache.reserveSlot(spacing: 0.5)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }

        var request = URLRequest(url: baseURL.appending(path: callsign))
        request.setValue(ClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await HTTP.session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 { coolOffUntil = Date().addingTimeInterval(120); return .failed }
            // An unknown callsign is a 404 with a plain-text body.
            if status == 404 { cache.entries[callsign] = .init(airports: nil, fetched: Date()); return .unknown }
            guard status == 200 else { return .failed }
            let parsed = Self.parse(data)
            cache.entries[callsign] = .init(airports: parsed, fetched: Date())
            return parsed.map { .airports($0) } ?? .unknown
        } catch {
            return .failed
        }
    }

    static func parse(_ data: Data) -> [Airport]? {
        struct Payload: Decodable {
            struct Response: Decodable {
                struct Route: Decodable {
                    struct A: Decodable {
                        var icao_code: String?, iata_code: String?, name: String?, municipality: String?, country_iso_name: String?
                        var latitude: Double?, longitude: Double?, elevation: Double?
                    }
                    var origin: A?, destination: A?
                }
                var flightroute: Route?
            }
            var response: Response?
        }
        guard let route = (try? JSONDecoder().decode(Payload.self, from: data))?.response?.flightroute else { return nil }
        func airport(_ a: Payload.Response.Route.A?) -> Airport? {
            guard let a, let icao = a.icao_code, let lat = a.latitude, let lon = a.longitude else { return nil }
            let iata = (a.iata_code?.isEmpty ?? true) ? nil : a.iata_code
            return Airport(icao: icao, iata: iata, name: a.name ?? icao, city: a.municipality ?? icao, countryCode: a.country_iso_name ?? "",
                           location: GeoPoint(latitude: lat, longitude: lon), elevationFt: a.elevation)
        }
        guard let origin = airport(route.origin), let destination = airport(route.destination) else { return nil }
        return [origin, destination]
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
