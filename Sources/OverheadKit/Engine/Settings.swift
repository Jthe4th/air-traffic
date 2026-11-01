import Foundation

/// How the home location was chosen. A city or ZIP search lands on the middle of the place, which can be a mile or more away.
public enum HomeSource: String, Codable, Sendable {
    case place, device, coordinates, address

    public var isApproximate: Bool { self == .place || self == .device }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var home: GeoPoint?
    public var homeName: String?
    public var homeSource: HomeSource?
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
    /// Seconds without remote input before the on-screen controls fade out. 0 keeps them visible.
    public var idleHideSeconds: Double = 15
    public var nightDimming: Bool = true
    public var alertLevel: AlertLevel = .emergencyAndNotable
    /// Fall back to the other data provider when the preferred one fails.
    public var autoFailover: Bool = true
    /// Pop up a card, with which way to look, when an aircraft is about to pass close.
    public var flybyCards: Bool = true
    /// An aircraft whose closest pass is within this distance counts as a flyby.
    public var flybyDistanceNM: Double = 2 / Geo.milesPerNM
    /// Flybys above this altitude are ignored (they are specks). 0 means any altitude.
    public var flybyMaxAltitudeFt: Int = 20_000
    /// The compass direction you look when watching TV, from your seat toward the screen. Nil until set.
    public var viewerHeadingDeg: Double?
    public var directionNames = DirectionNames()
    /// Watch for the International Space Station: show it when it flies over, and announce passes you can see.
    public var issEnabled: Bool = true
    /// The same for China's Tiangong space station.
    public var tiangongEnabled: Bool = true
    /// How long before a visible pass the card appears (for either station).
    public var issLeadMinutes: Int = 15
    public var issChime: Bool = true

    public static let issLeadChoices = [5, 10, 15, 30]

    public func watches(_ object: SpaceObject) -> Bool {
        switch object {
        case .iss: issEnabled
        case .tiangong: tiangongEnabled
        }
    }

    public var watchesAnyStation: Bool { SpaceObject.allCases.contains(where: watches) }

    public init() {}

    enum CodingKeys: String, CodingKey {
        case home, homeName, homeSource, mapRadiusNM, alertRadiusNM, units, feed, autoCycle, cycleSeconds, refreshSeconds, demoMode, showTrails, photoContact
        case idleHideSeconds, nightDimming, alertLevel, autoFailover
        case flybyCards, flybyDistanceNM, flybyMaxAltitudeFt, viewerHeadingDeg, directionNames
        case issEnabled, tiangongEnabled, issLeadMinutes, issChime
    }

    // Tolerant decoding so adding a setting later never wipes a saved home location.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        home = try c.decodeIfPresent(GeoPoint.self, forKey: .home)
        homeName = try c.decodeIfPresent(String.self, forKey: .homeName)
        homeSource = try c.decodeIfPresent(HomeSource.self, forKey: .homeSource)
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
        idleHideSeconds = try c.decodeIfPresent(Double.self, forKey: .idleHideSeconds) ?? d.idleHideSeconds
        nightDimming = try c.decodeIfPresent(Bool.self, forKey: .nightDimming) ?? d.nightDimming
        alertLevel = try c.decodeIfPresent(AlertLevel.self, forKey: .alertLevel) ?? d.alertLevel
        autoFailover = try c.decodeIfPresent(Bool.self, forKey: .autoFailover) ?? d.autoFailover
        flybyCards = try c.decodeIfPresent(Bool.self, forKey: .flybyCards) ?? d.flybyCards
        flybyDistanceNM = try c.decodeIfPresent(Double.self, forKey: .flybyDistanceNM) ?? d.flybyDistanceNM
        flybyMaxAltitudeFt = try c.decodeIfPresent(Int.self, forKey: .flybyMaxAltitudeFt) ?? d.flybyMaxAltitudeFt
        viewerHeadingDeg = try c.decodeIfPresent(Double.self, forKey: .viewerHeadingDeg)
        directionNames = try c.decodeIfPresent(DirectionNames.self, forKey: .directionNames) ?? d.directionNames
        issEnabled = try c.decodeIfPresent(Bool.self, forKey: .issEnabled) ?? d.issEnabled
        tiangongEnabled = try c.decodeIfPresent(Bool.self, forKey: .tiangongEnabled) ?? d.tiangongEnabled
        let lead = try c.decodeIfPresent(Int.self, forKey: .issLeadMinutes) ?? d.issLeadMinutes
        issLeadMinutes = Self.issLeadChoices.contains(lead) ? lead : d.issLeadMinutes
        issChime = try c.decodeIfPresent(Bool.self, forKey: .issChime) ?? d.issChime
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
