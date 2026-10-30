import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var home: GeoPoint?
    public var homeName: String?
    /// Radius of the map and of the feed query.
    public var mapRadiusNM: Double = 25 / Geo.milesPerNM
    /// Aircraft inside this radius are "overhead": featured, listed as sightings.
    public var alertRadiusNM: Double = 5 / Geo.milesPerNM
    public var units: UnitSystem = .imperial
    public var feed: FeedProvider = .adsbFi
    public var autoCycle: Bool = true
    public var cycleSeconds: Double = 14
    public var refreshSeconds: Double = 5
    public var demoMode: Bool = false
    public var showTrails: Bool = true
    /// Email or website sent to Planespotters with photo requests. Blank uses the app's built-in contact.
    public var photoContact: String = ""
    /// Fall back to the other data provider when the preferred one fails.
    public var autoFailover: Bool = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case home, homeName, mapRadiusNM, alertRadiusNM, units, feed, autoCycle, cycleSeconds, refreshSeconds, demoMode, showTrails, photoContact
        case autoFailover
    }

    // Tolerant decoding so adding a setting later never wipes a saved home location.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        home = try c.decodeIfPresent(GeoPoint.self, forKey: .home)
        homeName = try c.decodeIfPresent(String.self, forKey: .homeName)
        mapRadiusNM = try c.decodeIfPresent(Double.self, forKey: .mapRadiusNM) ?? d.mapRadiusNM
        alertRadiusNM = try c.decodeIfPresent(Double.self, forKey: .alertRadiusNM) ?? d.alertRadiusNM
        units = try c.decodeIfPresent(UnitSystem.self, forKey: .units) ?? d.units
        feed = try c.decodeIfPresent(FeedProvider.self, forKey: .feed) ?? d.feed
        autoCycle = try c.decodeIfPresent(Bool.self, forKey: .autoCycle) ?? d.autoCycle
        cycleSeconds = try c.decodeIfPresent(Double.self, forKey: .cycleSeconds) ?? d.cycleSeconds
        refreshSeconds = try c.decodeIfPresent(Double.self, forKey: .refreshSeconds) ?? d.refreshSeconds
        demoMode = try c.decodeIfPresent(Bool.self, forKey: .demoMode) ?? d.demoMode
        showTrails = try c.decodeIfPresent(Bool.self, forKey: .showTrails) ?? d.showTrails
        photoContact = try c.decodeIfPresent(String.self, forKey: .photoContact) ?? d.photoContact
        autoFailover = try c.decodeIfPresent(Bool.self, forKey: .autoFailover) ?? d.autoFailover
    }
}

public enum SettingsStore {
    private static let key = "settings.v1"
    private static let sightingsKey = "sightings.v1"

    public static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    public static func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func loadSightings() -> [Sighting] {
        guard let data = UserDefaults.standard.data(forKey: sightingsKey),
              let s = try? JSONDecoder().decode([Sighting].self, from: data) else { return [] }
        return s
    }

    static func saveSightings(_ sightings: [Sighting]) {
        if let data = try? JSONEncoder().encode(sightings) { UserDefaults.standard.set(data, forKey: sightingsKey) }
    }
}
