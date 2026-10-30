import Foundation

public protocol AircraftFeed: Sendable {
    var name: String { get }
    /// Aircraft within `radiusNM` of `center`, with positions timestamped to when they were true.
    func fetch(around center: GeoPoint, radiusNM: Double) async throws -> [Aircraft]
}

public enum FeedError: Error, LocalizedError, Sendable {
    case http(Int)
    case malformed

    public var errorDescription: String? {
        switch self {
        case .http(429): "Rate limited by the data provider"
        case .http(let code): "Data provider returned HTTP \(code)"
        case .malformed: "Unreadable response from the data provider"
        }
    }
}

public enum FeedProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case adsbFi, adsbLol

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .adsbFi: "adsb.fi"
        case .adsbLol: "adsb.lol"
        }
    }

    /// The provider used as the backup for this one.
    public var other: FeedProvider { self == .adsbFi ? .adsbLol : .adsbFi }

    public func makeFeed() -> any AircraftFeed {
        switch self {
        case .adsbFi:
            ReadsbFeed(name: "adsb.fi") { c, r in
                URL(string: "https://opendata.adsb.fi/api/v2/lat/\(c.latitude.formatted4)/lon/\(c.longitude.formatted4)/dist/\(Int(r.rounded(.up)))")!
            }
        case .adsbLol:
            ReadsbFeed(name: "adsb.lol") { c, r in
                URL(string: "https://api.adsb.lol/v2/point/\(c.latitude.formatted4)/\(c.longitude.formatted4)/\(Int(r.rounded(.up)))")!
            }
        }
    }
}

extension Double {
    var formatted4: String { String(format: "%.4f", self) }
}

/// Anything speaking the readsb/tar1090 JSON dialect (adsb.fi, adsb.lol, a local dump1090/readsb receiver).
public struct ReadsbFeed: AircraftFeed {
    public let name: String
    private let makeURL: @Sendable (GeoPoint, Double) -> URL

    public init(name: String, makeURL: @escaping @Sendable (GeoPoint, Double) -> URL) {
        self.name = name
        self.makeURL = makeURL
    }

    public func fetch(around center: GeoPoint, radiusNM: Double) async throws -> [Aircraft] {
        // The providers see only an approximate (≈0.7 mi) location, never the exact home coordinates.
        let rounded = GeoPoint(latitude: (center.latitude * 100).rounded() / 100,
                               longitude: (center.longitude * 100).rounded() / 100)
        var request = URLRequest(url: makeURL(rounded, radiusNM))
        request.setValue(ClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await HTTP.session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.http(http.statusCode)
        }
        return try ReadsbDecoder.decode(data, fallbackNow: Date())
    }
}

/// Identifies this app to the services it calls. A contact (email or website) is only ever sent to
/// Planespotters, which requires one; every other service sees a generic app identifier.
public enum ClientIdentity {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _default: String?
    nonisolated(unsafe) private static var _user: String?

    /// The app's built-in contact, read from Info.plist (AT_CONTACT) at launch.
    public static var defaultContact: String? {
        get { lock.withLock { _default } }
        set { let v = sanitize(newValue); lock.withLock { _default = v } }
    }

    /// A contact the viewer entered in Settings. Takes precedence over the built-in one.
    public static var userContact: String? {
        get { lock.withLock { _user } }
        set { let v = sanitize(newValue); lock.withLock { _user = v } }
    }

    public static var contact: String? { userContact ?? defaultContact }
    public static var hasContact: Bool { contact != nil }

    /// For every service that doesn't need a contact.
    public static var userAgent: String { "AirTrafficTV/\(AppVersion.number) (personal, non-commercial)" }

    /// For Planespotters only: identifies the app and how to reach whoever runs it.
    public static var photoUserAgent: String {
        guard let contact else { return userAgent }
        return "AirTrafficTV/\(AppVersion.number) (personal, non-commercial; +\(contact))"
    }

    /// Accepts an email address or a web address, strips anything that could break a header, and
    /// rejects half-typed values so a partial entry is never sent anywhere.
    public static func sanitize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = String(raw.unicodeScalars.filter { $0.value >= 0x20 && $0.value < 0x7F && $0 != "(" && $0 != ")" })
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned.count <= 100 else { return nil }
        let email = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        let url = #"^https?://[A-Za-z0-9.\-]+\.[A-Za-z]{2,}(/\S*)?$"#
        let ok = cleaned.range(of: email, options: .regularExpression) != nil
            || cleaned.range(of: url, options: .regularExpression) != nil
        return ok ? cleaned : nil
    }
}

public enum HTTP {
    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.waitsForConnectivity = false
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    /// Live data must never come from the cache.
    public static let liveSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
}
