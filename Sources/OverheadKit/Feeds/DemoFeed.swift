import Foundation

/// Synthetic traffic around a point. Used on first launch, offline, and for design previews.
/// Flights are fictional; routes and positions are only loosely plausible.
public struct DemoFeed: AircraftFeed {
    public let name = "Demo traffic"

    public init() {}

    public static let defaultHome = GeoPoint(latitude: 37.5630, longitude: -122.3255)
    public static let defaultHomeName = "Demo · San Francisco Bay"

    /// Demo flights fly a fixed-size loop, so zooming the map never makes them jump.
    public static let loopRadiusNM = 22.0

    public func fetch(around center: GeoPoint, radiusNM: Double) async throws -> [Aircraft] {
        Self.snapshot(center: center, radiusNM: Self.loopRadiusNM, at: Date())
    }

    struct Flight {
        var hex: String, callsign: String, registration: String
        var type: String, desc: String, op: String, year: Int
        var wake: WakeClass, squawk: String
        var track: Double, crossOffsetNM: Double, speedKt: Double
        var altStart: Double, altEnd: Double, phase: Double
        var mach: Double? = nil, ias: Double? = nil
        var wind: (dir: Double, kt: Double)? = nil, oat: Double? = nil
        var selectedAlt: Int? = nil, modes: [String] = []
    }

    static let flights: [Flight] = [
        Flight(hex: "a8b001", callsign: "UAL892", registration: "N29981", type: "B789", desc: "BOEING 787-9", op: "UNITED AIRLINES INC", year: 2017,
               wake: .heavy, squawk: "3412", track: 301, crossOffsetNM: 1.3, speedKt: 285, altStart: 2600, altEnd: 9800, phase: 0.42,
               ias: 262, selectedAlt: 17000, modes: ["autopilot", "vnav", "tcas"]),
        Flight(hex: "a2c4d7", callsign: "DAL421", registration: "N350DN", type: "A21N", desc: "AIRBUS A321NEO", op: "DELTA AIR LINES INC", year: 2021,
               wake: .large, squawk: "5151", track: 152, crossOffsetNM: -8.5, speedKt: 255, altStart: 8200, altEnd: 3400, phase: 0.18,
               ias: 248, selectedAlt: 3000, modes: ["autopilot", "approach", "tcas"]),
        Flight(hex: "a4e910", callsign: "SWA2210", registration: "N8907R", type: "B38M", desc: "BOEING 737 MAX 8", op: "SOUTHWEST AIRLINES CO", year: 2019,
               wake: .large, squawk: "2263", track: 163, crossOffsetNM: 5.0, speedKt: 372, altStart: 15800, altEnd: 19800, phase: 0.63,
               mach: 0.58, ias: 305, wind: (270, 41), oat: -18, selectedAlt: 36000, modes: ["autopilot", "vnav", "tcas"]),
        Flight(hex: "a0f272", callsign: "ASA337", registration: "N189SY", type: "E75L", desc: "EMBRAER ERJ-170-200 (LONG WING)", op: "HORIZON AIR", year: 2015,
               wake: .large, squawk: "4420", track: 168, crossOffsetNM: 3.2, speedKt: 292, altStart: 11800, altEnd: 4800, phase: 0.86,
               ias: 270, selectedAlt: 4000, modes: ["autopilot", "vnav", "tcas"]),
        Flight(hex: "a6b318", callsign: "FDX1187", registration: "N868FD", type: "B77L", desc: "BOEING 777-F", op: "FEDEX EXPRESS", year: 2014,
               wake: .heavy, squawk: "1636", track: 247, crossOffsetNM: -3.0, speedKt: 276, altStart: 9400, altEnd: 2800, phase: 0.05,
               ias: 255, selectedAlt: 3000, modes: ["autopilot", "approach", "tcas"]),
        Flight(hex: "a9d2e4", callsign: "N738SP", registration: "N738SP", type: "C172", desc: "CESSNA 172S SKYHAWK", op: "BAY AREA FLYING CLUB LLC", year: 2004,
               wake: .light, squawk: "1200", track: 48, crossOffsetNM: 2.4, speedKt: 104, altStart: 1900, altEnd: 2100, phase: 0.31),
        Flight(hex: "a3a7f0", callsign: "N407LF", registration: "N407LF", type: "B407", desc: "BELL 407", op: "AIR MEDICAL SERVICES", year: 2012,
               wake: .rotorcraft, squawk: "4521", track: 201, crossOffsetNM: -1.1, speedKt: 118, altStart: 900, altEnd: 700, phase: 0.74),
        Flight(hex: "896420", callsign: "UAE226", registration: "A6-EUA", type: "A388", desc: "AIRBUS A380-861", op: "EMIRATES", year: 2013,
               wake: .heavy, squawk: "2476", track: 138, crossOffsetNM: 9.0, speedKt: 238, altStart: 10800, altEnd: 5400, phase: 0.55,
               ias: 232, wind: (305, 22), oat: 6, selectedAlt: 4000, modes: ["autopilot", "vnav", "tcas"]),
        Flight(hex: "a5c8b9", callsign: "DAL1199", registration: "N826DX", type: "B739", desc: "BOEING 737-900ER", op: "DELTA AIR LINES INC", year: 2016,
               wake: .large, squawk: "6240", track: 153, crossOffsetNM: -11.0, speedKt: 486, altStart: 36000, altEnd: 36000, phase: 0.12,
               mach: 0.81, ias: 268, wind: (284, 78), oat: -56, selectedAlt: 36000, modes: ["autopilot", "althold", "tcas"]),
    ]

    public static func snapshot(center: GeoPoint, radiusNM: Double, at date: Date) -> [Aircraft] {
        let pathLength = radiusNM * 1.96
        let t = date.timeIntervalSinceReferenceDate
        return flights.map { f in
            let period = pathLength / f.speedKt * 3600
            let fraction = ((t / period) + f.phase).truncatingRemainder(dividingBy: 1)
            let mid = Geo.destination(from: center, bearing: f.track + 90, distanceNM: f.crossOffsetNM)
            let start = Geo.destination(from: mid, bearing: f.track + 180, distanceNM: pathLength / 2)
            let position = Geo.destination(from: start, bearing: f.track, distanceNM: fraction * pathLength)
            let alt = f.altStart + (f.altEnd - f.altStart) * fraction
            let minutes = pathLength / f.speedKt * 60
            let vs = (f.altEnd - f.altStart) / minutes
            return Aircraft(
                hex: f.hex, callsign: f.callsign, registration: f.registration, typeCode: f.type,
                typeDescription: f.desc, operatorName: f.op, yearBuilt: f.year,
                position: position, positionTime: date, onGround: false,
                barometricAltitudeFt: Int(alt.rounded()), geometricAltitudeFt: Int((alt + 150).rounded()),
                groundSpeedKt: f.speedKt, trackDeg: f.track, verticalRateFpm: Int(vs.rounded()),
                squawk: f.squawk, wakeClass: f.wake, mach: f.mach, indicatedAirspeedKt: f.ias,
                trueAirspeedKt: f.ias.map { $0 * (1 + alt / 60_000) },
                trueHeadingDeg: f.track, magneticHeadingDeg: f.track + 13,
                selectedAltitudeFt: f.selectedAlt, selectedHeadingDeg: f.track,
                autopilotModes: f.modes, windDirectionDeg: f.wind?.dir, windSpeedKt: f.wind?.kt,
                outsideAirTempC: f.oat, sourceType: "adsb_icao")
        }
    }
}

public struct DemoRouteProvider: RouteProviding {
    public init() {}

    public func lookup(for aircraft: Aircraft) async -> RouteLookup {
        guard let cs = aircraft.displayCallsign, let pair = Self.pairs[cs] else { return .unavailable }
        return .found(FlightRoute(origin: Self.airports[pair.0]!, destination: Self.airports[pair.1]!,
                                  flightNumber: Airlines.flightNumber(forCallsign: cs)))
    }

    static let pairs: [String: (String, String)] = [
        "UAL892": ("SFO", "LHR"), "DAL421": ("SEA", "SFO"), "SWA2210": ("OAK", "LAX"),
        "ASA337": ("PDX", "SFO"), "FDX1187": ("MEM", "OAK"), "UAE226": ("DXB", "SFO"),
        "DAL1199": ("SEA", "LAX"),
    ]

    static let airports: [String: Airport] = {
        func ap(_ icao: String, _ iata: String, _ name: String, _ city: String, _ cc: String, _ lat: Double, _ lon: Double) -> (String, Airport) {
            (iata, Airport(icao: icao, iata: iata, name: name, city: city, countryCode: cc, location: GeoPoint(latitude: lat, longitude: lon)))
        }
        return Dictionary(uniqueKeysWithValues: [
            ap("KSFO", "SFO", "San Francisco International Airport", "San Francisco", "US", 37.6188, -122.3754),
            ap("EGLL", "LHR", "London Heathrow Airport", "London", "GB", 51.4706, -0.4619),
            ap("KSEA", "SEA", "Seattle–Tacoma International Airport", "Seattle", "US", 47.4502, -122.3088),
            ap("KOAK", "OAK", "Oakland International Airport", "Oakland", "US", 37.7213, -122.2208),
            ap("KLAX", "LAX", "Los Angeles International Airport", "Los Angeles", "US", 33.9425, -118.4081),
            ap("KPDX", "PDX", "Portland International Airport", "Portland", "US", 45.5887, -122.5975),
            ap("KMEM", "MEM", "Memphis International Airport", "Memphis", "US", 35.0424, -89.9767),
            ap("OMDB", "DXB", "Dubai International Airport", "Dubai", "AE", 25.2528, 55.3644),
        ])
    }()
}
