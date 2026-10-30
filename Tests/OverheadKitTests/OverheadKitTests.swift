import Foundation
import Testing
@testable import OverheadKit

private let iad = GeoPoint(latitude: 38.9445, longitude: -77.4558)
private let sfo = GeoPoint(latitude: 37.6188, longitude: -122.3754)

private func airport(_ icao: String, _ iata: String, _ lat: Double, _ lon: Double) -> Airport {
    Airport(icao: icao, iata: iata, name: iata, city: iata, countryCode: "US", location: GeoPoint(latitude: lat, longitude: lon))
}

private func aircraft(at p: GeoPoint, track: Double, gs: Double = 400, alt: Int = 30_000, ground: Bool = false) -> Aircraft {
    Aircraft(hex: "abc123", callsign: "TST100", position: p, positionTime: Date(), onGround: ground,
             barometricAltitudeFt: alt, groundSpeedKt: gs, trackDeg: track)
}

@Suite struct GeometryTests {
    @Test func greatCircleDistance() {
        #expect(abs(Geo.distanceNM(iad, sfo) - 2_102) < 25)
    }

    @Test func bearings() {
        #expect(abs(Geo.bearing(from: GeoPoint(latitude: 0, longitude: 0), to: GeoPoint(latitude: 0, longitude: 1)) - 90) < 0.01)
        #expect(abs(Geo.bearing(from: GeoPoint(latitude: 0, longitude: 0), to: GeoPoint(latitude: 1, longitude: 0))) < 0.01)
    }

    @Test func destinationRoundTrip() {
        let p = Geo.destination(from: iad, bearing: 73, distanceNM: 120)
        #expect(abs(Geo.distanceNM(iad, p) - 120) < 0.05)
        #expect(abs(Geo.bearing(from: iad, to: p) - 73) < 0.3)
    }

    @Test func overheadPassIsPredicted() throws {
        // 10 NM due north, flying due south at 360 kt: directly overhead in 100 s.
        let cpa = try #require(Geo.closestApproach(east: 0, north: 10, trackDeg: 180, speedKt: 360))
        #expect(abs(cpa.seconds - 100) < 0.5)
        #expect(cpa.distanceNM < 0.01)
        #expect(!cpa.movingAway)
        let leaving = try #require(Geo.closestApproach(east: 0, north: 10, trackDeg: 0, speedKt: 360))
        #expect(leaving.movingAway)
    }

    @Test func compassPoints() {
        #expect(Geo.compass(0) == "N")
        #expect(Geo.compass(359) == "N")
        #expect(Geo.compass(45) == "NE")
        #expect(Geo.compass(202.5) == "SSW")
    }

    @Test func elevationAngleOverhead() {
        #expect(Geo.elevationAngle(heightFt: 36_000, groundDistanceNM: 0.001) > 85)
        #expect(Geo.elevationAngle(heightFt: 1_000, groundDistanceNM: 20) < 1)
    }

    @Test func deadReckoning() {
        var a = aircraft(at: iad, track: 90, gs: 360)
        a.positionTime = Date(timeIntervalSince1970: 1_000)
        let later = a.position(at: Date(timeIntervalSince1970: 1_010))   // 10 s at 360 kt = 1 NM
        #expect(abs(Geo.distanceNM(iad, later) - 1.0) < 0.02)
    }
}

@Suite struct MapCameraTests {
    @Test func centerLandsOnAnchor() {
        let cam = MapCamera(center: iad, zoom: 10.4, size: CGSize(width: 1920, height: 1080), anchor: CGPoint(x: 1300, y: 500))
        let p = cam.point(for: iad)
        #expect(abs(p.x - 1300) < 0.001 && abs(p.y - 500) < 0.001)
    }

    @Test func ringRadiusMatchesScale() {
        let cam = MapCamera.fitting(radiusNM: 20, radiusPoints: 400, center: iad, size: CGSize(width: 1920, height: 1080))
        let edge = cam.point(for: Geo.destination(from: iad, bearing: 90, distanceNM: 20))
        let c = cam.point(for: iad)
        #expect(abs((edge.x - c.x) - 400) < 4)
    }

    @Test func tilesCoverViewport() {
        let size = CGSize(width: 1920, height: 1080)
        let cam = MapCamera(center: iad, zoom: 10.3, size: size)
        let tiles = cam.tiles
        #expect(tiles.map(\.origin.x).min()! <= 0)
        #expect(tiles.map { $0.origin.x + $0.size }.max()! >= size.width)
        #expect(tiles.map(\.origin.y).min()! <= 0)
        #expect(tiles.map { $0.origin.y + $0.size }.max()! >= size.height)
        #expect(Set(tiles.map(\.id)).count == tiles.count)
    }
}

@Suite struct FeedTests {
    @Test func decodesRealAdsbFiCapture() throws {
        let url = try #require(Bundle.module.url(forResource: "adsbfi-sample", withExtension: "json", subdirectory: "Fixtures"))
        let list = try ReadsbDecoder.decode(Data(contentsOf: url), fallbackNow: Date())
        #expect(list.count == 7)

        let ground = try #require(list.first { $0.displayCallsign == "UAL1348" })
        #expect(ground.onGround)

        let heli = try #require(list.first { $0.wakeClass == .rotorcraft })
        #expect(heli.typeCode == "EC20")
        #expect(AircraftTypes.silhouette(for: heli) == .helicopter)

        let high = try #require(list.first { $0.displayCallsign == "DAL2479" })
        #expect(high.altitudeFt == 36_025)
        #expect(high.operatorName != nil)
        #expect(flightLevelText(altitudeFt: high.altitudeFt!) == "FL360")
        // Position time is the feed time minus the position's age.
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let feedTime = Date(timeIntervalSince1970: try #require(raw?["now"] as? Double))
        #expect(high.positionTime <= feedTime)
        #expect(feedTime.timeIntervalSince(high.positionTime) < 90)
    }

    @Test func toleratesBadRecordsAndMissingPositions() throws {
        let json = """
        {"now": 1700000000000, "ac": [
          {"hex":"aaaaaa","lat":10,"lon":20,"alt_baro":"ground","flight":"  ABC1  "},
          {"hex":"bbbbbb"},
          {"hex":"cccccc","lat":"bogus","lon":20},
          {"hex":"dddddd","lat":11,"lon":21,"alt_baro":5000,"year":"2008","seen_pos":3.5}
        ]}
        """
        let list = try ReadsbDecoder.decode(Data(json.utf8), fallbackNow: Date())
        #expect(list.map(\.hex) == ["aaaaaa", "dddddd"])
        #expect(list[0].displayCallsign == "ABC1")
        #expect(list[1].yearBuilt == 2008)
        // Millisecond epochs are normalised.
        #expect(Int(list[1].positionTime.timeIntervalSince1970) == 1_699_999_996)
    }

    @Test func garbageThrows() {
        #expect(throws: FeedError.self) { try ReadsbDecoder.decode(Data("<html>".utf8), fallbackNow: Date()) }
    }

    @Test func demoFlightsStayWithinTheEnginesKeepRadius() {
        // The engine keeps aircraft within 1.15x the map radius. Sample a full loop so every flight
        // is checked at the far ends of its path, not just wherever the clock happens to put it.
        let radius = 20.0
        for step in stride(from: 0.0, to: 3_000, by: 7) {
            let snapshot = DemoFeed.snapshot(center: DemoFeed.defaultHome, radiusNM: radius, at: Date(timeIntervalSinceReferenceDate: 800_000_000 + step))
            #expect(snapshot.count == DemoFeed.flights.count)
            for a in snapshot { #expect(Geo.distanceNM(DemoFeed.defaultHome, a.position) < radius * 1.15) }
        }
    }
}

@Suite struct RouteValidatorTests {
    let sfoAp = airport("KSFO", "SFO", 37.619, -122.375)
    let ont = airport("KONT", "ONT", 34.056, -117.601)
    let ord = airport("KORD", "ORD", 41.9786, -87.9048)
    let bna = airport("KBNA", "BNA", 36.1245, -86.6782)

    @Test func rejectsCallsignReusedOnTheOtherSideOfTheCountry() {
        // The real UAL2850 near Dulles, with a route record saying SFO→ONT.
        let a = aircraft(at: GeoPoint(latitude: 38.93, longitude: -77.54), track: 235, gs: 220, alt: 2_875)
        #expect(RouteValidator.plausibleLeg(airports: [sfoAp, ont], for: a) == nil)
    }

    @Test func acceptsFlightOnItsLeg() {
        // Midway ORD→BNA, tracking toward Nashville.
        let mid = GeoPoint(latitude: 39.0, longitude: -87.3)
        let track = Geo.bearing(from: mid, to: bna.location)
        #expect(RouteValidator.isPlausible(origin: ord, destination: bna, aircraft: aircraft(at: mid, track: track)))
    }

    @Test func rejectsFlightHeadingTheWrongWay() {
        let mid = GeoPoint(latitude: 39.0, longitude: -87.3)
        let away = Geo.bearing(from: mid, to: ord.location)
        #expect(!RouteValidator.isPlausible(origin: ord, destination: bna, aircraft: aircraft(at: mid, track: away)))
    }

    @Test func rejectsFlightOffToTheSide() {
        let off = GeoPoint(latitude: 39.0, longitude: -82.0)   // far east of the ORD→BNA corridor
        #expect(!RouteValidator.isPlausible(origin: ord, destination: bna, aircraft: aircraft(at: off, track: 190)))
    }

    @Test func picksCorrectLegOfMultiStopCallsign() throws {
        // ORD → BNA → SFO callsign; aircraft is on the BNA→SFO leg.
        let p = Geo.destination(from: bna.location, bearing: Geo.bearing(from: bna.location, to: sfoAp.location), distanceNM: 300)
        let a = aircraft(at: p, track: Geo.bearing(from: p, to: sfoAp.location))
        let leg = try #require(RouteValidator.plausibleLeg(airports: [ord, bna, sfoAp], for: a))
        #expect(leg.origin.iata == "BNA" && leg.destination.iata == "SFO")
    }

    @Test func groundTrafficMatchesEitherEnd() {
        let taxi = aircraft(at: GeoPoint(latitude: 41.98, longitude: -87.90), track: 0, gs: 15, alt: 0, ground: true)
        #expect(RouteValidator.isPlausible(origin: ord, destination: bna, aircraft: taxi))
    }

    @Test func parsesStandingDataRoute() throws {
        let json = """
        {"callsign":"RPA3632","airport_codes":"KORD-KBNA","_airports":[
         {"name":"Chicago O'Hare International Airport","icao":"KORD","iata":"ORD","location":"Chicago","countryiso2":"US","lat":41.9786,"lon":-87.9048,"alt_feet":672.0},
         {"name":"Nashville International Airport","icao":"KBNA","iata":"BNA","location":"Nashville","countryiso2":"US","lat":36.1245,"lon":-86.6782,"alt_feet":599.0}]}
        """
        let airports = try #require(StandingDataRouteProvider.parse(Data(json.utf8)))
        #expect(airports.map(\.code) == ["ORD", "BNA"])
        #expect(airports[0].city == "Chicago")
    }
}

@Suite struct ReferenceTests {
    @Test func callsignParsing() {
        #expect(Airlines.split(callsign: "UAL2850")?.designator == "UAL")
        #expect(Airlines.split(callsign: "N100HX") == nil)          // registration, not an airline flight
        #expect(Airlines.flightNumber(forCallsign: "UAL2850") == "UA 2850")
        #expect(Airlines.flightNumber(forCallsign: "ZZZ12") == "ZZZ 12")
        #expect(Airlines.airline(forCallsign: "DAL2479")?.name == "Delta Air Lines")
    }

    @Test func typeNames() {
        #expect(AircraftTypes.info(for: "b38m")?.name == "Boeing 737 MAX 8")
        #expect(AircraftTypes.info(for: "C172")?.kind == .lightPiston)
        #expect(AircraftTypes.info(for: "XXXX") == nil)
    }

    @Test func unitFormatting() {
        #expect(UnitSystem.imperial.speed(kt: 100).text == "115 mph")
        #expect(UnitSystem.metric.altitude(ft: 10_000).text == "3,048 m")
        #expect(UnitSystem.aviation.distance(nm: 12.4).text == "12 NM")
        #expect(UnitSystem.imperial.distance(nm: 1).text == "1.2 mi")
    }

    @Test func squawks() {
        #expect(Squawk.info(for: "7700")?.isEmergency == true)
        #expect(Squawk.info(for: "1200")?.isEmergency == false)
        #expect(Squawk.info(for: "4321") == nil)
    }

    @Test func capitalization() {
        #expect("UNITED AIRLINES INC".capitalizedWords == "United Airlines Inc")
        #expect("BOEING 737-800".capitalizedWords == "Boeing 737-800")
        #expect("BAY AREA FLYING CLUB LLC".capitalizedWords == "Bay Area Flying Club LLC")
    }
}

@MainActor
@Suite struct EngineTests {
    @Test func featuresNearestAndRecordsSighting() {
        let engine = TrackingEngine(settings: AppSettings(), persists: false)
        let now = Date()
        let home = engine.home
        let near = Aircraft(hex: "n1", callsign: "UAL1", position: Geo.destination(from: home, bearing: 10, distanceNM: 2), positionTime: now,
                            barometricAltitudeFt: 3000, groundSpeedKt: 200, trackDeg: 0)
        let far = Aircraft(hex: "f1", callsign: "DAL2", position: Geo.destination(from: home, bearing: 200, distanceNM: 15), positionTime: now,
                           barometricAltitudeFt: 30000, groundSpeedKt: 450, trackDeg: 0)
        engine.ingest([far, near], at: now)
        #expect(engine.aircraft.map(\.id) == ["n1", "f1"])
        #expect(engine.featuredID == "n1")
        #expect(engine.sightings.count == 1)
        #expect(engine.sightings.first?.hex == "n1")
    }

    @Test func dropsAircraftBeyondTheMap() {
        let engine = TrackingEngine(settings: AppSettings(), persists: false)
        let now = Date()
        let way = Aircraft(hex: "w1", position: Geo.destination(from: engine.home, bearing: 0, distanceNM: 90), positionTime: now, barometricAltitudeFt: 30000)
        engine.ingest([way], at: now)
        #expect(engine.aircraft.isEmpty)
        #expect(engine.featuredID == nil)
    }

    @Test func pinningHoldsSelection() {
        let engine = TrackingEngine(settings: AppSettings(), persists: false)
        let now = Date()
        let a = Aircraft(hex: "a1", position: Geo.destination(from: engine.home, bearing: 0, distanceNM: 2), positionTime: now, barometricAltitudeFt: 3000, groundSpeedKt: 200, trackDeg: 0)
        let b = Aircraft(hex: "b1", position: Geo.destination(from: engine.home, bearing: 90, distanceNM: 4), positionTime: now, barometricAltitudeFt: 5000, groundSpeedKt: 200, trackDeg: 0)
        engine.ingest([a, b], at: now)
        engine.pin("b1", now: now)
        engine.ingest([a, b], at: now.addingTimeInterval(5))
        #expect(engine.featuredID == "b1")
        #expect(engine.pinned)
    }
}

@Suite struct PlaceSearchTests {
    private func place(_ name: String, _ region: String, _ country: String = "United States", _ code: String = "US") -> Place {
        Place(name: name, region: region, country: country, countryCode: code, location: GeoPoint(latitude: 0, longitude: 0))
    }

    @Test func interpretsCommonFormats() {
        #expect(PlaceSearch.interpret("Silver Spring, MD") == ("Silver Spring", "MD"))
        #expect(PlaceSearch.interpret("silver spring md") == ("silver spring", "md"))
        #expect(PlaceSearch.interpret("Silver Spring, Maryland") == ("Silver Spring", "Maryland"))
        #expect(PlaceSearch.interpret("Washington, DC, USA") == ("Washington", "DC"))
        #expect(PlaceSearch.interpret("Paris, France") == ("Paris", "France"))
        #expect(PlaceSearch.interpret("Springfield").region == nil)
        #expect(PlaceSearch.interpret("20910").region == nil)
        #expect(PlaceSearch.interpret("Toronto ON") == ("Toronto", "ON"))
    }

    @Test func rankingKeepsOnlyTheRequestedRegion() {
        let all = [place("Springfield", "Missouri"), place("Springfield", "Illinois"), place("Springfield", "Massachusetts")]
        #expect(PlaceSearch.rank(all, region: "IL").map(\.region) == ["Illinois"])
        #expect(PlaceSearch.rank(all, region: "illinois").map(\.region) == ["Illinois"])
        #expect(PlaceSearch.rank(all, region: "Mass").map(\.region) == ["Massachusetts"])
        #expect(PlaceSearch.rank(all, region: "USA").count == 3)
        #expect(PlaceSearch.rank(all, region: "Texas").isEmpty)
    }

    @Test func countriesMatchByNameOrCode() {
        let all = [place("Paris", "Texas"), place("Paris", "Île-de-France Region", "France", "FR")]
        #expect(PlaceSearch.rank(all, region: "France").map(\.countryCode) == ["FR"])
        #expect(PlaceSearch.rank(all, region: "FR").map(\.countryCode) == ["FR"])
    }

    @Test func decodesGeocoderResponse() throws {
        let json = """
        {"results":[{"id":1,"name":"Silver Spring","latitude":38.99067,"longitude":-77.02609,"admin1":"Maryland","country":"United States","country_code":"US"}]}
        """
        let places = try PlaceSearch.decode(Data(json.utf8))
        #expect(places.first?.fullName == "Silver Spring, Maryland")
        #expect(places.first?.countryCode == "US")
        #expect(try PlaceSearch.decode(Data("{}".utf8)).isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_TESTS"] != nil))
    func liveCityStateSearch() async throws {
        let md = try await PlaceSearch.search("Silver Spring, MD")
        #expect(md.first?.region == "Maryland")
        let il = try await PlaceSearch.search("springfield il")
        #expect(il.first?.region == "Illinois")
        let dc = try await PlaceSearch.search("Washington, DC")
        #expect(dc.first?.region == "District of Columbia")
    }
}

@Suite struct AppVersionTests {
    @Test func prereleaseLabelIsAppendedToTheNumber() {
        #expect(AppVersion.format(number: "1.0.1", channel: "beta") == "1.0.1-beta")
        #expect(AppVersion.format(number: "1.0.1", channel: nil) == "1.0.1")
        #expect(AppVersion.format(number: "1.0.1", channel: "  ") == "1.0.1")
    }
}

@Suite(.serialized) struct ClientIdentityTests {
    init() { ClientIdentity.defaultContact = nil; ClientIdentity.userContact = nil }

    @Test func genericAgentNeverCarriesAContact() {
        ClientIdentity.userContact = "me@example.com"
        #expect(!ClientIdentity.userAgent.contains("example.com"))
        #expect(ClientIdentity.photoUserAgent.contains("+me@example.com"))
        ClientIdentity.userContact = nil
    }

    @Test func viewerContactBeatsTheBuiltInOne() {
        ClientIdentity.defaultContact = "https://app.example.org/contact"
        #expect(ClientIdentity.contact == "https://app.example.org/contact")
        ClientIdentity.userContact = "me@example.com"
        #expect(ClientIdentity.contact == "me@example.com")
        ClientIdentity.userContact = ""
        #expect(ClientIdentity.contact == "https://app.example.org/contact")
        ClientIdentity.defaultContact = nil
        #expect(!ClientIdentity.hasContact)
    }

    @Test func rejectsHalfTypedAndUnsafeValues() {
        #expect(ClientIdentity.sanitize("me@example") == nil)
        #expect(ClientIdentity.sanitize("me@") == nil)
        #expect(ClientIdentity.sanitize("example.com") == nil)
        #expect(ClientIdentity.sanitize("me@example.com\r\nX-Evil: 1") == nil)
        #expect(ClientIdentity.sanitize("  me@example.com  ") == "me@example.com")
        #expect(ClientIdentity.sanitize("https://example.org/about") == "https://example.org/about")
        #expect(ClientIdentity.sanitize(String(repeating: "a", count: 120) + "@example.com") == nil)
        #expect(ClientIdentity.sanitize("me(at)@example.com") == "me" + "at@example.com")
    }

    @Test func photosStayOffWithoutAContact() async {
        let provider = PlanespottersPhotoProvider()
        let a = Aircraft(hex: "abc123", position: GeoPoint(latitude: 0, longitude: 0), positionTime: Date())
        #expect(await provider.photo(for: a) == nil)   // returns before any network request
    }
}

@Suite struct ZoomTests {
    @Test func presetsAreRoundNumbersInTheViewersUnits() {
        #expect(MapZoom.presets(for: .imperial) == [5, 10, 25, 40, 60])
        #expect(MapZoom.label(radiusNM: 25 / Geo.milesPerNM, units: .imperial).text == "25 mi")
        #expect(MapZoom.label(radiusNM: 40 / Geo.kmPerNM, units: .metric).text == "40 km")
        #expect(MapZoom.label(radiusNM: 5 / Geo.milesPerNM, units: .imperial).text == "5 mi")   // not "5.0"
    }

    @Test func steppingWalksThePresetsAndStopsAtTheEnds() throws {
        let u = UnitSystem.imperial
        let start = AppSettings().mapRadiusNM                                 // 25 mi
        let out = try #require(MapZoom.zoomedOut(from: start, units: u))
        #expect(MapZoom.label(radiusNM: out, units: u).text == "40 mi")
        let in1 = try #require(MapZoom.zoomedIn(from: start, units: u))
        #expect(MapZoom.label(radiusNM: in1, units: u).text == "10 mi")
        let closest = try #require(MapZoom.zoomedIn(from: in1, units: u))
        #expect(MapZoom.label(radiusNM: closest, units: u).text == "5 mi")
        #expect(MapZoom.zoomedIn(from: closest, units: u) == nil)
        #expect(MapZoom.zoomedOut(from: 60 / Geo.milesPerNM, units: u) == nil)
    }

    @Test func switchingUnitsStillSteps() {
        // 25 mi isn't a preset in km, but there is still a sensible next step in each direction.
        #expect(MapZoom.zoomedOut(from: AppSettings().mapRadiusNM, units: .metric) != nil)
        #expect(MapZoom.zoomedIn(from: AppSettings().mapRadiusNM, units: .metric) != nil)
    }

}

@MainActor
@Suite struct EngineZoomTests {
    @Test func everyZoomStepIsAlreadyCoveredByTheCurrentFetch() {
        // Zooming out one step should reveal aircraft immediately, without waiting for a new request.
        for units in UnitSystem.allCases {
            let presets = MapZoom.presetsNM(for: units)
            for (small, large) in zip(presets, presets.dropFirst()) {
                let engine = TrackingEngine(settings: AppSettings(), persists: false)
                engine.settings.mapRadiusNM = small
                #expect(engine.fetchRadiusNM >= large * 1.08, "\(units) \(small) NM -> \(large) NM")
            }
        }
    }

    private func plane(_ id: String, atNM d: Double, bearing: Double = 40, home: GeoPoint, now: Date) -> Aircraft {
        Aircraft(hex: id, callsign: id.uppercased(), position: Geo.destination(from: home, bearing: bearing, distanceNM: d), positionTime: now,
                 barometricAltitudeFt: 20_000, groundSpeedKt: 300, trackDeg: 0)
    }

    @Test func zoomingChangesTheViewWithoutClearingAircraft() {
        let engine = TrackingEngine(settings: AppSettings(), persists: false)
        let now = Date(), home = engine.home
        // 5 NM and 30 NM: both inside what the engine fetches, but only the first is on the default map (21.7 NM).
        engine.ingest([plane("near", atNM: 5, home: home, now: now), plane("mid", atNM: 30, home: home, now: now)], at: now)
        #expect(engine.aircraft.count == 2)
        #expect(engine.visibleAircraft(at: now).map(\.id) == ["near"])

        engine.zoomOut()                                              // 25 mi -> 40 mi (34.8 NM)
        #expect(engine.aircraft.count == 2)                           // nothing was cleared
        #expect(engine.visibleAircraft(at: now).map(\.id) == ["near", "mid"])

        engine.zoomIn(); engine.zoomIn()                              // 40 -> 25 -> 10 mi (8.7 NM)
        #expect(engine.visibleAircraft(at: now).map(\.id) == ["near"])
        #expect(engine.aircraft.count == 2)
    }

    @Test func zoomButtonsReportTheirLimits() {
        let engine = TrackingEngine(settings: AppSettings(), persists: false)
        #expect(engine.canZoomIn && engine.canZoomOut)
        for _ in 0..<10 { engine.zoomOut() }
        #expect(!engine.canZoomOut && engine.canZoomIn)
        #expect(MapZoom.label(radiusNM: engine.settings.mapRadiusNM, units: .imperial).text == "60 mi")
        for _ in 0..<10 { engine.zoomIn() }
        #expect(!engine.canZoomIn)
        #expect(MapZoom.label(radiusNM: engine.settings.mapRadiusNM, units: .imperial).text == "5 mi")
    }

    @Test func aircraftBeyondTheViewAreNeverFeatured() {
        let engine = TrackingEngine(settings: AppSettings(), persists: false)
        let now = Date(), home = engine.home
        engine.ingest([plane("far", atNM: 30, home: home, now: now)], at: now)   // fetched, but off the default map
        #expect(engine.featuredID == nil)
        engine.zoomOut()                                                          // now on the map
        #expect(engine.featuredID == "far")
        engine.zoomIn()
        #expect(engine.featuredID == nil)
    }
}

// MARK: - Alerts, failover, diagnostics
private func squawking(_ code: String?, emergency: String? = nil, flags: DatabaseFlags = [], ground: Bool = false, hex: String = "e1") -> Aircraft {
    Aircraft(hex: hex, callsign: "TST\(hex)", position: GeoPoint(latitude: 39, longitude: -77), positionTime: Date(), onGround: ground,
             barometricAltitudeFt: ground ? nil : 20_000, groundSpeedKt: 300, trackDeg: 0, squawk: code, emergency: emergency, flags: flags)
}

@Suite struct AlertTests {
    @Test func emergencySquawksAreEmergencies() {
        for code in ["7500", "7600", "7700"] {
            #expect(Alerts.evaluate(squawking(code), level: .emergency)?.isEmergency == true)
        }
        #expect(Alerts.evaluate(squawking("1200"), level: .emergencyAndNotable) == nil)
    }

    @Test func theEmergencyFieldCountsButMedicalFlightsDoNot() {
        #expect(Alerts.evaluate(squawking(nil, emergency: "nordo"), level: .emergency)?.isEmergency == true)
        #expect(Alerts.evaluate(squawking(nil, emergency: "minfuel"), level: .emergency)?.isEmergency == true)
        #expect(Alerts.evaluate(squawking(nil, emergency: "lifeguard"), level: .emergencyAndNotable) == nil)
    }

    @Test func levelsFilterWhatIsShown() {
        let notable = squawking("1200", flags: [.interesting])
        #expect(Alerts.evaluate(notable, level: .emergencyAndNotable) == .notable)
        #expect(Alerts.evaluate(notable, level: .emergency) == nil)
        #expect(Alerts.evaluate(squawking("7700"), level: .off) == nil)
        // Plain military aircraft are common near bases and are not alerts by themselves.
        #expect(Alerts.evaluate(squawking("1200", flags: [.military]), level: .emergencyAndNotable) == nil)
    }

    @Test func groundTrafficIsIgnored() {
        #expect(Alerts.evaluate(squawking("7700", ground: true), level: .emergency) == nil)
    }
}

/// A feed that follows a script and counts how often it is asked.
private final class ScriptedFeed: AircraftFeed, @unchecked Sendable {
    let name: String
    private let lock = NSLock()
    private var outcomes: [Result<[Aircraft], Error>]
    private var calls = 0
    init(_ name: String, _ outcomes: [Result<[Aircraft], Error>]) { self.name = name; self.outcomes = outcomes }
    var callCount: Int { lock.withLock { calls } }
    func fetch(around center: GeoPoint, radiusNM: Double) async throws -> [Aircraft] {
        let outcome: Result<[Aircraft], Error> = lock.withLock { calls += 1; return outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0] }
        return try outcome.get()
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private struct Outage: Error, LocalizedError { var errorDescription: String? { "provider down" } }

@Suite struct FailoverTests {
    private let one = [squawking(nil, hex: "a1")]
    private let two = [squawking(nil, hex: "b1"), squawking(nil, hex: "b2")]
    private let here = GeoPoint(latitude: 39, longitude: -77)

    @Test func usesThePreferredProviderWhileItWorks() async throws {
        let p = ScriptedFeed("primary", [.success(one)]), b = ScriptedFeed("backup", [.success(two)])
        let feed = FailoverFeed(primary: p, secondary: b)
        #expect(try await feed.fetch(around: here, radiusNM: 20).count == 1)
        #expect(feed.name == "primary" && b.callCount == 0)
    }

    @Test func fallsBackWithinTheSamePollSoThereIsNoGap() async throws {
        let p = ScriptedFeed("primary", [.failure(Outage())]), b = ScriptedFeed("backup", [.success(two)])
        let feed = FailoverFeed(primary: p, secondary: b)
        #expect(try await feed.fetch(around: here, radiusNM: 20).count == 2)
        #expect(feed.name == "backup (backup)" && p.callCount == 1 && b.callCount == 1)
    }

    @Test func staysOnTheBackupForTheRetryWindowThenReturns() async throws {
        let clock = TestClock()
        let p = ScriptedFeed("primary", [.failure(Outage()), .success(one)]), b = ScriptedFeed("backup", [.success(two)])
        let feed = FailoverFeed(primary: p, secondary: b, retryAfter: 120, now: { clock.now })
        _ = try await feed.fetch(around: here, radiusNM: 20)             // primary fails, backup serves
        clock.advance(60)
        _ = try await feed.fetch(around: here, radiusNM: 20)             // still inside the window
        #expect(p.callCount == 1 && b.callCount == 2)
        clock.advance(61)
        #expect(try await feed.fetch(around: here, radiusNM: 20).count == 1)   // window over: primary again, and it works
        #expect(p.callCount == 2 && feed.name == "primary")
    }

    @Test func reportsThePreferredProvidersErrorWhenBothFail() async {
        let p = ScriptedFeed("primary", [.failure(Outage())]), b = ScriptedFeed("backup", [.failure(FeedError.http(503))])
        let feed = FailoverFeed(primary: p, secondary: b)
        await #expect(throws: Outage.self) { try await feed.fetch(around: here, radiusNM: 20) }
    }

    @Test func cancellationIsNeverTreatedAsAnOutage() async {
        let p = ScriptedFeed("primary", [.failure(CancellationError())]), b = ScriptedFeed("backup", [.success(two)])
        let feed = FailoverFeed(primary: p, secondary: b)
        await #expect(throws: CancellationError.self) { try await feed.fetch(around: here, radiusNM: 20) }
        #expect(b.callCount == 0)
    }

    @Test func providersPairWithEachOther() {
        #expect(FeedProvider.adsbFi.other == .adsbLol && FeedProvider.adsbLol.other == .adsbFi)
    }
}

@MainActor
@Suite struct EngineAlertTests {
    private func plane(_ id: String, atNM d: Double, squawk: String? = nil, home: GeoPoint, now: Date) -> Aircraft {
        Aircraft(hex: id, callsign: id.uppercased(), position: Geo.destination(from: home, bearing: 30, distanceNM: d), positionTime: now,
                 barometricAltitudeFt: 20_000, groundSpeedKt: 300, trackDeg: 0, squawk: squawk)
    }

    @Test func anEmergencyIsHeldBackUntilItHasPersisted() {
        let engine = TrackingEngine(settings: AppSettings(), persists: false)
        let t0 = Date(), home = engine.home
        engine.ingest([plane("sos", atNM: 10, squawk: "7700", home: home, now: t0)], at: t0)
        #expect(engine.alerts(at: t0).isEmpty)                                   // could be a code passing through 7700
        #expect(engine.alerts(at: t0.addingTimeInterval(13)).map(\.id) == ["sos"])
    }

    @Test func aBrieflyDialledCodeNeverBecomesAnAlert() {
        let engine = TrackingEngine(settings: AppSettings(), persists: false)
        let t0 = Date(), home = engine.home
        engine.ingest([plane("blip", atNM: 10, squawk: "7700", home: home, now: t0)], at: t0)
        engine.ingest([plane("blip", atNM: 10, squawk: "7000", home: home, now: t0.addingTimeInterval(5))], at: t0.addingTimeInterval(5))
        #expect(engine.alerts(at: t0.addingTimeInterval(30)).isEmpty)
    }

    @Test func anEmergencyOnTheMapTakesTheCardButAPinWins() {
        let engine = TrackingEngine(settings: AppSettings(), persists: false)
        engine.emergencyConfirmAfter = 0
        let t0 = Date(), home = engine.home
        engine.ingest([plane("near", atNM: 2, home: home, now: t0), plane("sos", atNM: 15, squawk: "7700", home: home, now: t0)], at: t0)
        #expect(engine.featuredID == "sos")                                       // nearer plane is overridden
        engine.pin("near", now: t0)
        engine.ingest([plane("near", atNM: 2, home: home, now: t0), plane("sos", atNM: 15, squawk: "7700", home: home, now: t0)], at: t0.addingTimeInterval(2))
        #expect(engine.featuredID == "near")
    }

    @Test func alertsCanBeTurnedOff() {
        var s = AppSettings(); s.alertLevel = .off
        let engine = TrackingEngine(settings: s, persists: false)
        engine.emergencyConfirmAfter = 0
        let t0 = Date()
        engine.ingest([plane("sos", atNM: 10, squawk: "7700", home: engine.home, now: t0)], at: t0)
        #expect(engine.alerts(at: t0.addingTimeInterval(60)).isEmpty)
    }
}

@Suite struct DiagnosticsAndSettingsTests {
    @Test func tallyRecordsSuccessesAndFailures() {
        var d = Diagnostics()
        let t = Date()
        d.recordSuccess(at: t, latency: 0.2346, count: 17, radiusNM: 40)
        d.recordFailure(at: t.addingTimeInterval(5), message: "boom")
        #expect(d.successes == 1 && d.failures == 1)
        #expect(d.lastLatencyMs == 235 && d.lastAircraftCount == 17 && d.lastError == "boom")
    }

    @Test func oldSavedSettingsStillLoadWithNewDefaults() throws {
        let old = #"{"home":{"latitude":39,"longitude":-77},"homeName":"Somewhere","units":"metric"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(s.homeName == "Somewhere" && s.units == .metric)
        #expect(s.autoFailover && s.alertLevel == .emergencyAndNotable)
    }
}
