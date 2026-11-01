import Foundation
import Testing
@testable import OverheadKit

private func ap(_ icao: String, _ iata: String, _ lat: Double, _ lon: Double) -> Airport {
    Airport(icao: icao, iata: iata, name: iata, city: iata, countryCode: "US", location: GeoPoint(latitude: lat, longitude: lon))
}
private let cun = ap("MMUN", "CUN", 21.0365, -86.8771)
private let ewr = ap("KEWR", "EWR", 40.6925, -74.1687)
private let bwi = ap("KBWI", "BWI", 39.1754, -76.6683)
private let oak = ap("KOAK", "OAK", 37.7213, -122.2208)
private let den = ap("KDEN", "DEN", 39.8561, -104.6737)

/// An airline flight on its way from Cancún to Newark, 150 NM short of Newark and pointing at it.
private func cancunToNewark(callsign: String = "UAL1051") -> Aircraft {
    let p = Geo.destination(from: ewr.location, bearing: Geo.bearing(from: ewr.location, to: cun.location), distanceNM: 150)
    return Aircraft(hex: "a1b2c3", callsign: callsign, position: p, positionTime: Date(), barometricAltitudeFt: 36_000,
                    groundSpeedKt: 450, trackDeg: Geo.bearing(from: p, to: ewr.location))
}

/// A route database that answers from a fixed table and remembers what it was asked.
private actor StubSource: CallsignSource {
    private let answer: CallsignAnswer
    private(set) var asked: [String] = []
    init(_ answer: CallsignAnswer) { self.answer = answer }
    func airports(forCallsign callsign: String) async -> CallsignAnswer { asked.append(callsign); return answer }
}

@Suite struct AdsbdbParsingTests {
    private let real = """
    {"response":{"flightroute":{"callsign":"UAL1051","callsign_icao":"UAL1051","callsign_iata":"UA1051",
     "airline":{"name":"United Airlines","icao":"UAL","iata":"UA","country":"United States","country_iso":"US","callsign":"UNITED"},
     "origin":{"country_iso_name":"MX","country_name":"Mexico","elevation":22,"iata_code":"CUN","icao_code":"MMUN","latitude":21.0365,"longitude":-86.8771,"municipality":"Canc\\u00fan","name":"Canc\\u00fan International Airport"},
     "destination":{"country_iso_name":"US","country_name":"United States","elevation":18,"iata_code":"EWR","icao_code":"KEWR","latitude":40.6925,"longitude":-74.1687,"municipality":"New York","name":"Newark Liberty International Airport"}}}}
    """

    @Test func readsAnOriginAndADestination() throws {
        let airports = try #require(AdsbdbSource.parse(Data(real.utf8)))
        #expect(airports.map(\.code) == ["CUN", "EWR"])
        #expect(airports[0].icao == "MMUN" && airports[0].city == "Cancún" && airports[0].countryCode == "MX")
        #expect(abs(airports[1].location.latitude - 40.6925) < 1e-9 && airports[1].elevationFt == 18)
    }

    @Test func anUnknownCallsignHasNoRoute() {
        #expect(AdsbdbSource.parse(Data(#"{"response":"unknown callsign"}"#.utf8)) == nil)
    }

    @Test func anAirportWithoutACoordinateMakesTheRouteUnusable() {
        let broken = real.replacingOccurrences(of: #""latitude":40.6925,"#, with: "")
        #expect(AdsbdbSource.parse(Data(broken.utf8)) == nil)
    }

    @Test func garbageAndEmptyAnswersAreNotRoutes() {
        #expect(AdsbdbSource.parse(Data("<html>Too many requests</html>".utf8)) == nil)
        #expect(AdsbdbSource.parse(Data()) == nil)
        #expect(AdsbdbSource.parse(Data(#"{"response":{"flightroute":null}}"#.utf8)) == nil)
    }
}

@Suite struct LiveRouteProviderTests {
    @Test func theFirstDatabaseWinsAndTheSecondIsNotBothered() async throws {
        let first = StubSource(.airports([cun, ewr])), second = StubSource(.airports([cun, ewr]))
        let result = await LiveRouteProvider(sources: [first, second]).lookup(for: cancunToNewark())
        guard case .found(let route) = result else { Issue.record("expected a route, got \(result)"); return }
        #expect(route.origin.code == "CUN" && route.destination.code == "EWR" && route.flightNumber == "UA 1051")
        #expect(await second.asked.isEmpty)
    }

    @Test func theSecondDatabaseFillsInWhenTheFirstIsForAnotherTrip() async throws {
        let first = StubSource(.airports([oak, den])), second = StubSource(.airports([cun, ewr]))
        let result = await LiveRouteProvider(sources: [first, second]).lookup(for: cancunToNewark())
        guard case .found(let route) = result else { Issue.record("expected a route, got \(result)"); return }
        #expect(route.origin.code == "CUN")
        let askedFirst = await first.asked, askedSecond = await second.asked
        #expect(askedFirst == ["UAL1051"] && askedSecond == ["UAL1051"])
    }

    @Test func aRouteListedForADifferentTripIsUnconfirmedNotShown() async {
        let result = await LiveRouteProvider(sources: [StubSource(.airports([oak, den])), StubSource(.airports([oak, den]))]).lookup(for: cancunToNewark())
        #expect(result == .unconfirmed)
    }

    @Test func noDatabaseKnowingTheCallsignMeansUnavailable() async {
        let result = await LiveRouteProvider(sources: [StubSource(.unknown), StubSource(.unknown)]).lookup(for: cancunToNewark())
        #expect(result == .unavailable)
    }

    @Test func notBeingAbleToAskIsDifferentFromNotKnowing() async {
        #expect(await LiveRouteProvider(sources: [StubSource(.failed), StubSource(.unknown)]).lookup(for: cancunToNewark()) == .failed)
        #expect(await LiveRouteProvider(sources: [StubSource(.unknown), StubSource(.failed)]).lookup(for: cancunToNewark()) == .failed)
        // A route that was listed but didn't fit still counts as seen, even if the other database could not be asked.
        #expect(await LiveRouteProvider(sources: [StubSource(.airports([oak, den])), StubSource(.failed)]).lookup(for: cancunToNewark()) == .unconfirmed)
    }

    @Test func aFailedFirstDatabaseDoesNotStopTheSecondFindingTheRoute() async {
        let result = await LiveRouteProvider(sources: [StubSource(.failed), StubSource(.airports([cun, ewr]))]).lookup(for: cancunToNewark())
        if case .found(let route) = result { #expect(route.destination.code == "EWR") } else { Issue.record("expected a route, got \(result)") }
    }

    @Test func privateCallsignsAreNeverLookedUp() async {
        let source = StubSource(.airports([cun, ewr]))
        var plane = cancunToNewark(); plane.callsign = "N123AB"
        #expect(await LiveRouteProvider(sources: [source]).lookup(for: plane) == .unavailable)
        plane.callsign = nil
        #expect(await LiveRouteProvider(sources: [source]).lookup(for: plane) == .unavailable)
        #expect(await source.asked.isEmpty)
    }

    @Test func otherStopsOfAMultiStopCallsignAreKept() async throws {
        // CUN → EWR → BWI: the flight is on the first leg, and BWI is a later stop.
        let result = await LiveRouteProvider(sources: [StubSource(.airports([cun, ewr, bwi]))]).lookup(for: cancunToNewark())
        guard case .found(let route) = result else { Issue.record("expected a route, got \(result)"); return }
        #expect(route.origin.code == "CUN" && route.destination.code == "EWR" && route.otherStops.map(\.code) == ["BWI"])
    }
}

@MainActor
@Suite struct EngineRouteStatusTests {
    private struct Routes: RouteProviding {
        let result: RouteLookup?        // nil: never answers
        func lookup(for aircraft: Aircraft) async -> RouteLookup {
            if let result { return result }
            try? await Task.sleep(for: .seconds(3600))
            return .failed
        }
    }

    /// Fails the first time it is asked and finds a route the second time.
    private actor Flaky: RouteProviding {
        private var calls = 0
        func lookup(for aircraft: Aircraft) async -> RouteLookup {
            calls += 1
            return calls == 1 ? .failed : .found(FlightRoute(origin: cun, destination: ewr))
        }
    }

    private func status(_ result: RouteLookup?) async -> (RouteStatus, FlightRoute?) {
        let e = TrackingEngine(settings: AppSettings(), persists: false, routes: Routes(result: result))
        let plane = Aircraft(hex: "abc123", callsign: "UAL100", position: Geo.destination(from: e.home, bearing: 0, distanceNM: 3),
                             positionTime: Date(), barometricAltitudeFt: 5_000, groundSpeedKt: 200, trackDeg: 90)
        e.ingest([plane], at: Date())
        for _ in 0..<100 where e.aircraft.first?.routeStatus == .checking && result != nil { try? await Task.sleep(for: .milliseconds(10)) }
        return (e.aircraft[0].routeStatus, e.aircraft[0].route)
    }

    @Test func itIsCheckingUntilTheLookupAnswers() async {
        let (state, route) = await status(nil)
        #expect(state == .checking && route == nil)
    }

    @Test func aFoundRouteIsShown() async {
        let (state, route) = await status(.found(FlightRoute(origin: cun, destination: ewr)))
        #expect(state == .found && route?.destination.code == "EWR")
    }

    @Test func anUnconfirmedRouteIsNotShownButIsSaid() async {
        let (state, route) = await status(.unconfirmed)
        #expect(state == .unconfirmed && route == nil)
    }

    @Test func noRouteAnywhereIsUnavailable() async {
        let (state, route) = await status(.unavailable)
        #expect(state == .unavailable && route == nil)
    }

    @Test func aLookupThatCouldNotBeMadeStopsClaimingToCheckAndIsTriedAgain() async {
        let e = TrackingEngine(settings: AppSettings(), persists: false, routes: Flaky())
        let plane = Aircraft(hex: "abc123", callsign: "UAL100", position: Geo.destination(from: e.home, bearing: 0, distanceNM: 3),
                             positionTime: Date(), barometricAltitudeFt: 5_000, groundSpeedKt: 200, trackDeg: 90)
        let t0 = Date()
        e.ingest([plane], at: t0)
        for _ in 0..<100 where e.aircraft.first?.routeStatus == .checking { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(e.aircraft[0].routeStatus == .unavailable)
        e.ingest([plane], at: t0.addingTimeInterval(25))                  // the next poll, past the 20-second retry
        for _ in 0..<100 where e.aircraft.first?.route == nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(e.aircraft[0].routeStatus == .found && e.aircraft[0].route?.origin.code == "CUN")
    }
}
