import Foundation
import Testing
@testable import OverheadKit

/// The ISS element set published by CelesTrak on 2026-11-01.
let issLine1 = "1 25544U 98067A   26305.40213002  .00006924  00000+0  13304-3 0  9992"
let issLine2 = "2 25544  51.6333 341.0833 0007085 335.3698  24.6951 15.49140766593021"
let issElements = OrbitalElements(name: "ISS (ZARYA)", line1: issLine1, line2: issLine2)!

/// Spacetrack Report #3's near-Earth test satellite.
private let testLine1 = "1 88888U          80275.98708465  .00073094  13844-3  66816-4 0    87"
private let testLine2 = "2 88888  72.8435 115.9689 0086731  52.6988 110.5714 16.05824518  1058"

private func close(_ v: Vec3, _ x: Double, _ y: Double, _ z: Double, within tolerance: Double) -> Bool {
    abs(v.x - x) < tolerance && abs(v.y - y) < tolerance && abs(v.z - z) < tolerance
}

@Suite struct OrbitalElementsTests {
    @Test func readsTheFieldsOfAnElementSet() throws {
        let e = try #require(OrbitalElements.parse("ISS (ZARYA)             \n\(issLine1)\n\(issLine2)\n"))
        #expect(e.name == "ISS (ZARYA)")
        #expect(e.catalogNumber == 25544)
        #expect(abs(e.inclinationRad * 180 / .pi - 51.6333) < 1e-9)
        #expect(abs(e.eccentricity - 0.0007085) < 1e-12)
        #expect(abs(e.bstar - 0.13304e-3) < 1e-12)
        #expect(abs(e.meanMotion * 1440 / (2 * .pi) - 15.49140766) < 1e-8)
    }

    @Test func theEpochIsTheDayOfYearInUTC() throws {
        // Day 305.40213002 of 2026 is 1 November, 09:39:06 UTC.
        let e = try #require(OrbitalElements(line1: issLine1, line2: issLine2))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: e.epoch)
        #expect(c.year == 2026 && c.month == 11 && c.day == 1 && c.hour == 9 && c.minute == 39)
    }

    @Test func twoDigitYearsPivotAtFiftySeven() throws {
        let e = try #require(OrbitalElements(line1: testLine1, line2: testLine2))      // year 80
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.component(.year, from: e.epoch) == 1980)
    }

    @Test func aMinusSignInTheExponentAndANegativeBstarAreBothRead() throws {
        // Flip the sign of B* and fix the checksum, which counts a minus sign as 1.
        var l1 = Array(issLine1)
        l1[53] = "-"
        l1[68] = Character(String((Int(String(l1[68]))! + 1) % 10))
        let e = try #require(OrbitalElements(line1: String(l1), line2: issLine2))
        #expect(abs(e.bstar + 0.13304e-3) < 1e-12)
    }

    @Test func rejectsDamagedOrMismatchedLines() {
        #expect(OrbitalElements(line1: issLine1, line2: String(issLine2.dropLast()) + "0") == nil)                // bad checksum
        #expect(OrbitalElements(line1: String(issLine1.dropLast(3)), line2: issLine2) == nil)                      // short
        #expect(OrbitalElements(line1: issLine2, line2: issLine1) == nil)                                          // swapped
        #expect(OrbitalElements.parse("") == nil)
        #expect(OrbitalElements.parse("<html>Too many requests</html>") == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(issElements)
        let back = try JSONDecoder().decode(OrbitalElements.self, from: data)
        #expect(back == issElements)
        #expect(back.epoch == issElements.epoch)
    }
}

@Suite struct SGP4Tests {
    // Reference values come from the python-sgp4 package (the Vallado 2006 reference implementation), run on the same element sets.
    @Test func matchesTheReferenceForTheStandardTestSatellite() throws {
        let elements = try #require(OrbitalElements(line1: testLine1, line2: testLine2))
        let sgp4 = try #require(SGP4(elements))
        let t0 = try #require(sgp4.propagate(minutesSinceEpoch: 0))
        #expect(close(t0.position, 2328.96975262, -5995.22051338, 1719.97297192, within: 1e-4))
        #expect(close(t0.velocity, 2.91207328, -0.98341796, -7.09081621, within: 1e-6))
        let t360 = try #require(sgp4.propagate(minutesSinceEpoch: 360))
        #expect(close(t360.position, 2456.10706533, -6071.93855503, 1222.89768554, within: 1e-4))
        let t1440 = try #require(sgp4.propagate(minutesSinceEpoch: 1440))
        #expect(close(t1440.position, 2742.55398832, -6079.67009123, -326.39012649, within: 1e-4))
        #expect(close(t1440.velocity, 1.94849765, 1.21107268, -7.35619313, within: 1e-6))
    }

    @Test func matchesTheReferenceForTheSpaceStation() throws {
        let sgp4 = try #require(SGP4(issElements))
        let cases: [(Double, Vec3, Vec3)] = [
            (0, Vec3(x: 6426.81687727, y: -2202.48545565, z: -0.00144019), Vec3(x: 1.53768784, y: 4.50034366, z: 6.01178145)),
            (45, Vec3(x: -6267.89111799, y: 2592.99974133, z: 508.28057740), Vec3(x: -2.23956000, y: -4.22828794, z: -5.97661727)),
            (600, Vec3(x: -5764.07876655, y: 3350.55617341, z: 1343.97461822), Vec3(x: -3.45375286, y: -3.59772915, z: -5.80952563)),
            (2880, Vec3(x: 5996.07052595, y: -3190.97774185, z: 119.29700385), Vec3(x: 2.13712063, y: 4.25110194, z: 6.01050099)),
            (10080, Vec3(x: -4352.58604650, y: 5202.51409308, z: -521.32900197), Vec3(x: -3.36219683, y: -3.40418921, z: -5.97495771)),
        ]
        for (minutes, r, v) in cases {
            let s = try #require(sgp4.propagate(minutesSinceEpoch: minutes))
            #expect(close(s.position, r.x, r.y, r.z, within: 1e-4), "position at \(minutes) min")
            #expect(close(s.velocity, v.x, v.y, v.z, within: 1e-6), "velocity at \(minutes) min")
        }
    }

    @Test func aDateAndMinutesSinceEpochAgree() throws {
        let sgp4 = try #require(SGP4(issElements))
        let byDate = try #require(sgp4.propagate(at: issElements.epoch.addingTimeInterval(45 * 60)))
        let byMinutes = try #require(sgp4.propagate(minutesSinceEpoch: 45))
        #expect(byDate.position == byMinutes.position)
    }

    @Test func theStationFliesAtAboutFourHundredKilometres() throws {
        let sgp4 = try #require(SGP4(issElements))
        for minutes in stride(from: 0.0, through: 200, by: 10) {
            let s = try #require(sgp4.propagate(minutesSinceEpoch: minutes))
            #expect((6_750...6_820).contains(s.position.length), "radius at \(minutes) min")
            #expect((7.6...7.7).contains(s.velocity.length))
        }
    }

    @Test func refusesOrbitsItCannotModel() throws {
        // The same elements with a one-revolution-a-day mean motion: a deep-space (geosynchronous) orbit.
        var l2 = Array(issLine2)
        let geo = Array(" 1.00270000")
        for (i, ch) in geo.enumerated() { l2[52 + i] = ch }
        var sum = 0
        for ch in l2.prefix(68) { if let d = ch.wholeNumberValue { sum += d } else if ch == "-" { sum += 1 } }
        l2[68] = Character(String(sum % 10))
        let e = try #require(OrbitalElements(line1: issLine1, line2: String(l2)))
        #expect(SGP4(e) == nil)
    }
}

private let appleParkLike = GeoPoint(latitude: 37.3349, longitude: -122.0090)
private func at(_ unix: Double) -> Date { Date(timeIntervalSince1970: unix) }

@Suite struct SkyGeometryTests {
    // Reference values: Skyfield with NASA's DE421 ephemeris, same elements, observer at 37.3349, -122.0090.
    @Test func siderealTimeAtJ2000IsTheTextbookValue() {
        // 2000-01-01 12:00 UT: GMST = 18h 41m 50.55s = 280.46061837°
        let degrees = Sky.gmst(at(946_728_000)) * 180 / .pi
        #expect(abs(degrees - 280.46061837) < 1e-5)
    }

    @Test func geodeticCoordinatesRoundTrip() {
        for (lat, lon, alt) in [(37.3349, -122.0090, 0.0), (-33.9, 151.2, 0.5), (51.5, -0.12, 0.02), (0.0, 179.9, 0.0)] {
            let p = Sky.Observer(GeoPoint(latitude: lat, longitude: lon), altitudeKm: alt).position
            let g = Sky.geodetic(p)
            #expect(abs(g.latitudeDeg - lat) < 1e-7 && abs(g.longitudeDeg - lon) < 1e-7 && abs(g.altitudeKm - alt) < 1e-6)
        }
    }

    @Test func lookAnglesMatchTheReference() throws {
        let orbit = try #require(SatelliteOrbit(issElements))
        let observer = Sky.Observer(appleParkLike)
        let cases: [(Double, az: Double, el: Double, range: Double)] = [
            (1_793_534_400, 109.0489, -34.6049, 7941.955),     // far below the horizon
            (1_793_539_045, 37.6638, 54.5046, 515.975),         // high in the sky
            (1_793_539_244, 116.4870, 10.0574, 1503.413),       // just above the horizon
            (1_794_535_502, 321.2531, 79.4234, 424.446),        // nearly overhead
        ]
        for c in cases {
            let v = try #require(orbit.view(from: observer, at: at(c.0)))
            #expect(abs(v.azimuthDeg - c.az) < 0.05, "azimuth at \(c.0)")
            #expect(abs(v.elevationDeg - c.el) < 0.02, "elevation at \(c.0)")
            #expect(abs(v.rangeKm - c.range) < 0.2, "range at \(c.0)")
        }
    }

    @Test func theGroundPointBelowMatchesTheReference() throws {
        let orbit = try #require(SatelliteOrbit(issElements))
        let s = try #require(orbit.sample(at: at(1_793_539_045)))
        #expect(abs(s.subpoint.latitude - 39.3212) < 0.001 && abs(s.subpoint.longitude + 120.0187) < 0.001)
        #expect(abs(s.altitudeKm - 426.694) < 0.01)
    }

    @Test func theSunsHeightMatchesTheReference() throws {
        let observer = Sky.Observer(appleParkLike)
        let cases: [(unix: Double, height: Double)] = [(1_793_534_400, -30.8166), (1_793_552_400, 24.2604), (1_793_539_045, -15.4666), (1_793_622_622, -24.9694)]
        for c in cases {
            let date = at(c.unix)
            let height = observer.elevation(ofDirection: Sky.rotateToEarthFixed(Sky.sunDirection(date), at: date))
            #expect(abs(height - c.height) < 0.05, "sun height at \(c.unix)")
        }
    }

    @Test func theSunIsOnTheEquatorAtTheEquinoxAndFarNorthAtTheJuneSolstice() {
        // Equinox 2026-03-20 14:46 UTC and solstice 2026-06-21 08:24 UTC, from the published almanac.
        func direction(_ iso: String) -> Vec3 { Sky.sunDirection(ISO8601DateFormatter().date(from: iso)!) }
        let equinox = direction("2026-03-20T14:46:00Z")
        #expect(abs(asin(equinox.z) * 180 / .pi) < 0.05)
        #expect(abs(atan2(equinox.y, equinox.x) * 180 / .pi) < 0.1)
        let solstice = direction("2026-06-21T08:24:00Z")
        #expect(abs(asin(solstice.z) * 180 / .pi - 23.44) < 0.03)
    }

    @Test func earthsShadowIsACylinderOnTheNightSide() {
        let sun = Vec3(x: 1, y: 0, z: 0)
        #expect(Sky.isSunlit(Vec3(x: 7000, y: 0, z: 0), sunDirection: sun))               // day side
        #expect(!Sky.isSunlit(Vec3(x: -7000, y: 0, z: 0), sunDirection: sun))             // straight behind the Earth
        #expect(!Sky.isSunlit(Vec3(x: -7000, y: 6000, z: 0), sunDirection: sun))          // behind, inside the 6,378 km radius
        #expect(Sky.isSunlit(Vec3(x: -7000, y: 6600, z: 0), sunDirection: sun))           // behind but clear of the shadow
        #expect(Sky.isSunlit(Vec3(x: 0, y: 6500, z: 0), sunDirection: sun))               // on the terminator
    }

    @Test func theStationEntersSunlightWhenTheReferenceSaysItDoes() throws {
        // Skyfield has the Station leaving Earth's shadow at 1793538938 and entering it at 1793536866 (its Sun is a disc, ours a point).
        let orbit = try #require(SatelliteOrbit(issElements))
        let leaves = 1_793_538_938.0, enters = 1_793_536_866.0
        let cases: [(unix: Double, lit: Bool)] = [(leaves - 12, false), (leaves + 12, true), (enters - 12, true), (enters + 12, false)]
        for c in cases {
            let sample = try #require(orbit.sample(at: at(c.unix)))
            #expect(sample.isSunlit == c.lit, "lit at \(c.unix)")
        }
    }

    @Test func groundSpeedAgreesWithHowFarThePointBelowMoves() throws {
        let orbit = try #require(SatelliteOrbit(issElements))
        let a = try #require(orbit.sample(at: at(1_793_539_045))), b = try #require(orbit.sample(at: at(1_793_539_046)))
        let moved = Geo.distanceNM(a.subpoint, b.subpoint) * 3600       // knots over one second
        #expect(abs(moved - a.groundSpeedKt) / a.groundSpeedKt < 0.01)
        #expect(Geo.angleDifference(Geo.bearing(from: a.subpoint, to: b.subpoint), a.trackDeg) < 1)
        #expect((7.6...7.7).contains(a.orbitalSpeedKmS))
    }

    @Test func aRoundOfTheOrbitComesBackWhereItStartedAcrossTheEarthsTurn() throws {
        // One revolution is about 92.9 minutes, so the point below is back at the same latitude, a little west.
        let orbit = try #require(SatelliteOrbit(issElements))
        let a = try #require(orbit.sample(at: at(1_793_539_045))), b = try #require(orbit.sample(at: at(1_793_539_045 + 92.9 * 60)))
        #expect(abs(a.subpoint.latitude - b.subpoint.latitude) < 1)
        #expect(Geo.distanceNM(a.subpoint, b.subpoint) > 600)          // Earth turned about 23°
    }
}

@Suite struct PassFinderTests {
    /// Visible passes for 12 days from 2026-11-01 12:00 UTC at the observer above, with the same rules, from Skyfield + DE421:
    /// start, peak and end (unix seconds) and the height at the peak. Passes peaking under 20° or lasting under 30 s are left out.
    private struct Ref { let start: Double, peak: Double, end: Double, peakEl: Double
        init(_ s: Double, _ p: Double, _ e: Double, _ h: Double) { start = s; peak = p; end = e; peakEl = h } }
    private static let reference: [Ref] = [
        Ref(1_793_538_938.0, 1_793_539_045.0, 1_793_539_244.0, 54.5),
        Ref(1_793_622_622.0, 1_793_622_622.0, 1_793_622_771.0, 30.2),
        Ref(1_793_628_220.0, 1_793_628_387.0, 1_793_628_410.0, 24.0),
        Ref(1_793_711_892.0, 1_793_711_938.0, 1_793_712_131.0, 43.4),
        Ref(1_793_795_586.0, 1_793_795_586.0, 1_793_795_687.0, 27.3),
        Ref(1_794_278_891.0, 1_794_279_022.0, 1_794_279_022.0, 35.7),
        Ref(1_794_362_454.0, 1_794_362_629.0, 1_794_362_703.0, 29.2),
        Ref(1_794_451_775.0, 1_794_451_956.0, 1_794_451_956.0, 43.3),
        Ref(1_794_535_303.0, 1_794_535_502.0, 1_794_535_624.0, 79.4),
    ]
    private static let windowStart = at(1_793_534_400)
    private func twelveDays(minimumPeakDeg: Double = 20, step: TimeInterval = 20) throws -> [SatellitePass] {
        let orbit = try #require(SatelliteOrbit(issElements))
        return PassFinder.visiblePasses(of: orbit, from: appleParkLike, between: Self.windowStart, and: Self.windowStart.addingTimeInterval(12 * 86_400),
                                        minimumPeakDeg: minimumPeakDeg, step: step)
    }

    @Test func findsTheSamePassesAsTheReference() throws {
        let passes = try twelveDays()
        #expect(passes.count == Self.reference.count)
        for (pass, expected) in zip(passes, Self.reference) {
            #expect(abs(pass.start.date.timeIntervalSince1970 - expected.start) < 2.5, "start of \(expected.start)")
            #expect(abs(pass.peak.date.timeIntervalSince1970 - expected.peak) < 2.5, "peak of \(expected.start)")
            #expect(abs(pass.end.date.timeIntervalSince1970 - expected.end) < 2.5, "end of \(expected.start)")
            #expect(abs(pass.peak.elevationDeg - expected.peakEl) < 0.3, "peak height of \(expected.start)")
        }
    }

    @Test func reportsWhereItAppearsAndDisappears() throws {
        let first = try #require(try twelveDays().first)
        // Skyfield: appears at azimuth 327.9° and 24.2° up (leaving Earth's shadow), sets at 116.5° on the horizon limit.
        #expect(abs(first.start.azimuthDeg - 327.9) < 1 && abs(first.start.elevationDeg - 24.2) < 0.5)
        #expect(abs(first.end.azimuthDeg - 116.5) < 1 && abs(first.end.elevationDeg - 10.1) < 0.3)
        #expect(first.startsOutOfShadow && !first.endsInShadow)
    }

    @Test func brightnessIsRealisticAndBestWhenNearlyOverhead() throws {
        let passes = try twelveDays()
        for pass in passes { #expect((-4.8 ... -0.5).contains(pass.brightestMagnitude), "magnitude \(pass.brightestMagnitude)") }
        let overhead = try #require(passes.max { $0.peak.elevationDeg < $1.peak.elevationDeg })
        let low = try #require(passes.min { $0.peak.elevationDeg < $1.peak.elevationDeg })
        #expect(overhead.brightestMagnitude < low.brightestMagnitude)
        #expect(overhead.brightestMagnitude < -3.5)
    }

    @Test func theMinimumPeakKeepsOnlyPassesWorthGoingOutsideFor() throws {
        let everything = try twelveDays(minimumPeakDeg: 0)
        #expect(everything.count == Self.reference.count + 1)        // plus the 12.7° pass (the 20-second one is under 30 s)
        #expect(everything.contains { $0.peak.elevationDeg < 20 })
        #expect(try twelveDays(minimumPeakDeg: 60).count == 1)        // only the 79° pass
    }

    @Test func aPassUnderWayWhenTheSearchBeginsStartsThere() throws {
        let orbit = try #require(SatelliteOrbit(issElements))
        let underway = at(1_793_539_100)
        let pass = try #require(PassFinder.visiblePasses(of: orbit, from: appleParkLike, between: underway, and: underway.addingTimeInterval(3600)).first)
        #expect(pass.start.date == underway)
        #expect(abs(pass.end.date.timeIntervalSince1970 - 1_793_539_244) < 2.5)
    }

    @Test func nothingIsVisibleInDaylight() throws {
        // 2026-11-02 18:00 to 2026-11-03 01:00 UTC is 10:00 to 17:00 in California.
        let orbit = try #require(SatelliteOrbit(issElements))
        let start = ISO8601DateFormatter().date(from: "2026-11-02T18:00:00Z")!
        #expect(PassFinder.visiblePasses(of: orbit, from: appleParkLike, between: start, and: start.addingTimeInterval(7 * 3600), minimumPeakDeg: 0).isEmpty)
    }

    @Test func aFinerSearchStepGivesTheSamePasses() throws {
        let coarse = try twelveDays(step: 30), fine = try twelveDays(step: 10)
        #expect(coarse.count == fine.count)
        for (a, b) in zip(coarse, fine) { #expect(abs(a.start.date.timeIntervalSince(b.start.date)) < 1 && abs(a.end.date.timeIntervalSince(b.end.date)) < 1) }
    }

    @Test func everyMomentOfAPassReallyIsVisible() throws {
        let orbit = try #require(SatelliteOrbit(issElements))
        let observer = Sky.Observer(appleParkLike)
        for pass in try twelveDays() {
            #expect(pass.start.date <= pass.peak.date && pass.peak.date <= pass.end.date)
            #expect(pass.path.first?.date == pass.start.date && pass.path.last?.date == pass.end.date)
            #expect(zip(pass.path, pass.path.dropFirst()).allSatisfy { $0.date < $1.date })
            for point in pass.path {
                let v = try #require(orbit.view(from: observer, at: point.date.addingTimeInterval(point.date == pass.end.date ? -0.5 : (point.date == pass.start.date ? 0.5 : 0))))
                #expect(v.elevationDeg >= PassFinder.horizonDeg - 0.1 && v.isSunlit && v.sunElevationDeg < PassFinder.darkSkyDeg + 0.1)
            }
        }
    }
}

@Suite struct SpaceSettingsTests {
    @Test func defaultsAreOnWithAFifteenMinuteWarning() {
        let s = AppSettings()
        #expect(s.issEnabled && s.issChime && s.issLeadMinutes == 15)
        #expect(AppSettings.issLeadChoices == [5, 10, 15, 30])
    }

    @Test func settingsRoundTripAndTolerateOlderSavedFiles() throws {
        var s = AppSettings()
        s.issEnabled = false; s.issLeadMinutes = 30; s.issChime = false
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        // A settings file saved before this feature existed gets the defaults and keeps the home.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"home":{"latitude":40,"longitude":-105},"units":"metric"}"#.utf8))
        #expect(old.issEnabled && old.issLeadMinutes == 15 && old.units == .metric && old.home?.latitude == 40)
    }

    @Test func anOddWarningTimeFallsBackToTheDefault() throws {
        let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"issLeadMinutes":7}"#.utf8))
        #expect(odd.issLeadMinutes == 15)
    }
}

@Suite struct StationCardTests {
    private func pass(startingIn seconds: Double, asOf now: Date, startEl: Double = 12, shadowEnd: Bool = false) -> SatellitePass {
        let start = now.addingTimeInterval(seconds)
        func p(_ s: Double, _ az: Double, _ el: Double) -> SatellitePass.Point { .init(date: start.addingTimeInterval(s), azimuthDeg: az, elevationDeg: el) }
        return SatellitePass(start: p(0, 225, startEl), peak: p(120, 180, 64), end: p(240, 90, 15),
                             path: [p(0, 225, startEl), p(120, 180, 64), p(240, 90, 15)], brightestMagnitude: -3.6,
                             startsOutOfShadow: false, endsInShadow: shadowEnd)
    }

    @Test func theCardMovesThroughItsPhases() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func phase(_ s: Double) -> StationPassCard.Phase { StationPassCard(pass: pass(startingIn: s, asOf: now), asOf: now).phase }
        #expect(phase(900) == .upcoming && phase(121) == .upcoming)
        #expect(phase(120) == .imminent && phase(1) == .imminent)
        #expect(phase(-10) == .underway)
        #expect(phase(-241) == .ended)
    }

    @Test func headlinesCountDown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func headline(_ s: Double) -> String { StationPassCard(pass: pass(startingIn: s, asOf: now), asOf: now).headline }
        #expect(headline(14 * 60 - 20) == "Visible in 14 minutes")
        #expect(headline(179) == "Visible in 3 minutes")
        #expect(headline(61) == "Appears in about 60 seconds")
        #expect(headline(100) == "Appears in 2 minutes")
        #expect(headline(7) == "Appears in about 5 seconds")
        #expect(headline(-30) == "Visible now")
        #expect(headline(-300) == "Just passed")
    }

    @Test func sayingWhereToLook() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let card = StationPassCard(pass: pass(startingIn: 300, asOf: now), asOf: now)
        #expect(card.appearsPlace == "southwest, low")
        #expect(card.highestPlace == "south, high")
        #expect(card.endPlace == "east, low")
        #expect(card.route == "SW to E")
        #expect(card.moments.map(\.label) == ["Rises", "Highest", "Sets"])
        #expect(card.brightnessText == "Brilliant" && card.peakDegrees == 64)
    }

    @Test func aPassHighUpAtTheStartAppearsRatherThanRisesAndShadowEndsAreSaid() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let card = StationPassCard(pass: pass(startingIn: 300, asOf: now, startEl: 35, shadowEnd: true), asOf: now)
        #expect(card.moments.first?.label == "Appears")
        #expect(card.moments.last?.label == "Fades" && card.moments.last?.place.hasSuffix("into Earth's shadow") == true)
    }

    @Test func sayingWhenIsRelativeToToday() {
        // Noon local time, so the offsets below land on the days named whatever the time zone.
        let noon = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000)).addingTimeInterval(12 * 3600)
        func text(startingIn hours: Double) -> String {
            StationPassCard.whenText(for: pass(startingIn: hours * 3600, asOf: noon), now: noon)
        }
        #expect(text(startingIn: 2).hasPrefix("Today at "))
        #expect(text(startingIn: 20).hasPrefix("Tomorrow at "))
        #expect(!text(startingIn: 72).hasPrefix("Today") && !text(startingIn: 72).hasPrefix("Tomorrow") && text(startingIn: 72).contains(" at "))
    }

    @Test func brightnessWordsFollowTheMagnitude() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func word(_ m: Double) -> String { var p = pass(startingIn: 60, asOf: now); p.brightestMagnitude = m; return StationPassCard(pass: p, asOf: now).brightnessText }
        #expect(word(-4.1) == "Brilliant" && word(-3.0) == "Very bright" && word(-2.0) == "Bright" && word(-1.0) == "Moderate" && word(0.5) == "Faint")
    }
}

@MainActor
@Suite struct EngineStationTests {
    /// An engine whose home is `offsetNM` from the point under the station at `time`.
    private func engine(at time: Date, offsetNM: Double = 5, change: (inout AppSettings) -> Void = { _ in }) throws -> TrackingEngine {
        let station = try #require(SatelliteOrbit(issElements)).sample(at: time)!
        var s = AppSettings()
        s.demoMode = false
        s.home = Geo.destination(from: station.subpoint, bearing: 250, distanceNM: offsetNM)
        change(&s)
        return TrackingEngine(settings: s, persists: false)
    }

    /// An engine at the observer used for the reference passes, with the station's orbit loaded `secondsBefore` before the first pass.
    private func engineForPasses(secondsBefore: Double, change: (inout AppSettings) -> Void = { _ in }) -> (engine: TrackingEngine, start: Date) {
        var s = AppSettings()
        s.demoMode = false
        s.home = appleParkLike
        change(&s)
        let e = TrackingEngine(settings: s, persists: false)
        let start = at(1_793_538_937)
        e.useStationElements(issElements, at: start.addingTimeInterval(-secondsBefore))
        return (e, start)
    }

    // MARK: On the map

    @Test func theStationIsInTheAircraftListWhileItFliesOverAndGoneWhenItHasPassed() throws {
        let t0 = at(1_793_539_045)
        let e = try engine(at: t0)
        e.useStationElements(issElements, at: t0)
        let station = try #require(e.aircraft.first)
        #expect(station.id == "ISS" && station.aircraft.isSpacecraft && station.aircraft.title == "ISS")
        #expect(station.typeName == "International Space Station")
        #expect(Geo.distanceNM(e.home, station.aircraft.position) < 6)
        #expect(e.visibleAircraft(at: t0).map(\.id) == ["ISS"])

        e.ingest([], at: t0.addingTimeInterval(60))                    // a minute later it is 250 NM away
        #expect(e.aircraft.isEmpty)
    }

    @Test func itTakesTheFeaturedCardWhileInViewAndLetsGoAfterwards() throws {
        let t0 = at(1_793_539_045)
        let e = try engine(at: t0)
        let plane = Aircraft(hex: "abc123", callsign: "UAL1", position: Geo.destination(from: e.home, bearing: 0, distanceNM: 1.5), positionTime: t0,
                             barometricAltitudeFt: 5_000, groundSpeedKt: 200, trackDeg: 90)
        e.ingest([plane], at: t0)
        #expect(e.featuredID == "abc123")                              // nearest, before the station arrives
        e.useStationElements(issElements, at: t0)
        e.ingest([plane], at: t0)
        #expect(e.featuredID == "ISS")                                 // takes the card though a plane is closer
        let later = t0.addingTimeInterval(40)
        e.ingest([plane.withTime(later)], at: later)
        #expect(e.featuredID == "abc123")
    }

    @Test func itIsListedBesideAircraftNearestFirst() throws {
        let t0 = at(1_793_539_045)
        let e = try engine(at: t0, offsetNM: 12)
        let near = Aircraft(hex: "near01", position: Geo.destination(from: e.home, bearing: 0, distanceNM: 2), positionTime: t0, barometricAltitudeFt: 5_000)
        let far = Aircraft(hex: "far001", position: Geo.destination(from: e.home, bearing: 0, distanceNM: 30), positionTime: t0, barometricAltitudeFt: 5_000)
        e.ingest([far, near], at: t0)
        e.useStationElements(issElements, at: t0)
        #expect(e.aircraft.map(\.id) == ["near01", "ISS", "far001"])
    }

    @Test func itIsNeverGivenARouteOrPhotoLookupOrAFlybyCard() throws {
        let t0 = at(1_793_539_045)
        let e = try engine(at: t0, offsetNM: 0.3)                      // as close to straight overhead as a flyby could be
        e.useStationElements(issElements, at: t0)
        let station = try #require(e.aircraft.first)
        #expect(station.photoRequested && station.route == nil)
        #expect(e.flybyCards(at: t0).isEmpty)
        #expect(Flyby.evaluate(station.aircraft, home: e.home, heading: nil, at: t0, config: FlybyConfig(distanceNM: 5, maxAltitudeFt: 0)) == nil)
    }

    @Test func aStationSightingIsRecordedWhenItPassesOverhead() throws {
        let t0 = at(1_793_539_045)
        let e = try engine(at: t0, offsetNM: 2)
        e.useStationElements(issElements, at: t0)
        let s = try #require(e.sightings.first)
        #expect(s.title == "ISS" && s.typeName == "International Space Station")
    }

    @Test func itDoesNotCoastOffTheMapBetweenFeedReports() throws {
        let t0 = at(1_793_539_045)
        let e = try engine(at: t0)
        e.useStationElements(issElements, at: t0)
        // A feed report arrives 30 s later. The station is 125 NM away by then and must not linger from the old entry.
        let later = t0.addingTimeInterval(30)
        e.ingest([], at: later)
        #expect(e.aircraft.isEmpty)
    }

    @Test func itsTrailAndFirstSightingSurviveAFeedReport() throws {
        let t0 = at(1_793_539_045)
        let e = try engine(at: t0)
        e.useStationElements(issElements, at: t0)
        e.updateStation(now: t0.addingTimeInterval(2))
        e.updateStation(now: t0.addingTimeInterval(4))
        let before = try #require(e.aircraft.first)
        #expect(before.trail.count >= 3 && before.firstSeen == t0)
        e.ingest([], at: t0.addingTimeInterval(5))                     // a feed report arrives mid-pass
        let after = try #require(e.aircraft.first)
        #expect(after.trail.count >= before.trail.count && after.firstSeen == t0)
    }

    @Test func switchingTheFeatureOffRemovesItEvenBeforeTheNextSecond() throws {
        let t0 = at(1_793_539_045)
        let e = try engine(at: t0)
        e.useStationElements(issElements, at: t0)
        #expect(e.aircraft.count == 1)
        e.settings.issEnabled = false
        #expect(e.aircraft.isEmpty)
        e.ingest([], at: t0.addingTimeInterval(1))
        #expect(e.aircraft.isEmpty)
    }

    @Test func theElevationUsesTheRoundEarth() throws {
        let t0 = at(1_793_539_045)
        let orbit = try #require(SatelliteOrbit(issElements))
        for offset in [5.0, 60, 150] {
            let e = try engine(at: t0, offsetNM: offset) { $0.mapRadiusNM = 100 }      // wide enough to track it that far out
            e.useStationElements(issElements, at: t0)
            let station = try #require(e.aircraft.first)
            let elevation = try #require(station.aircraft.relative(to: e.home, at: t0).elevationDeg)
            let truth = try #require(orbit.view(from: Sky.Observer(e.home), at: t0)).elevationDeg
            #expect(abs(elevation - truth) < 0.6, "elevation at \(offset) NM: \(elevation) vs \(truth)")
        }
    }

    @Test func sphericalElevationMatchesGeometryAtTheHorizonAndOverhead() {
        #expect(abs(Geo.sphericalElevation(heightKm: 420, groundDistanceNM: 0) - 90) < 1e-9)
        let earth = Geo.earthRadiusNM * Geo.kmPerNM
        let horizonNM = earth * acos(earth / (earth + 420)) / Geo.kmPerNM          // where the station touches the horizon
        #expect(abs(Geo.sphericalElevation(heightKm: 420, groundDistanceNM: horizonNM)) < 0.01)
        // Against the full coordinate maths: a point 420 km up and 600 NM away along the ground.
        let origin = GeoPoint(latitude: 30, longitude: -100)
        let overhead = Geo.destination(from: origin, bearing: 0, distanceNM: 600)
        let truth = Sky.Observer(origin).look(at: Sky.Observer(overhead, altitudeKm: 420).position).elevationDeg
        let curved = Geo.sphericalElevation(heightKm: 420, groundDistanceNM: 600)
        #expect(abs(curved - truth) < 0.3)
        // The estimate used for aircraft, which only allows for curvature roughly, runs about a degree high out here.
        let estimate = Geo.elevationAngle(heightFt: 420_000 / 0.3048, groundDistanceNM: 600)
        #expect(estimate - curved > 0.5 && estimate - curved < 2)
    }

    // MARK: Pass cards

    @Test func aCardAppearsOnlyInsideTheWarningTime() throws {
        let (e, start) = engineForPasses(secondsBefore: 20 * 60)
        #expect(e.stationCards(at: start.addingTimeInterval(-16 * 60)).isEmpty)               // 15-minute default: not yet
        let card = try #require(e.stationCards(at: start.addingTimeInterval(-14 * 60)).first)
        #expect(card.phase == .upcoming && card.headline == "Visible in 14 minutes")
        #expect(try #require(e.stationCards(at: start.addingTimeInterval(-100)).first).phase == .imminent)
        #expect(try #require(e.stationCards(at: start.addingTimeInterval(30)).first).phase == .underway)
    }

    @Test func theWarningTimeIsASetting() throws {
        let (e, start) = engineForPasses(secondsBefore: 40 * 60)
        for (minutes, early, late) in [(5, 6.0, 4.0), (10, 11.0, 9.0), (15, 16.0, 14.0), (30, 31.0, 29.0)] {
            e.settings.issLeadMinutes = minutes
            #expect(e.stationCards(at: start.addingTimeInterval(-early * 60)).isEmpty, "\(minutes)-minute warning, \(early) min out")
            #expect(e.stationCards(at: start.addingTimeInterval(-late * 60)).count == 1, "\(minutes)-minute warning, \(late) min out")
        }
    }

    @Test func theCardLingersBrieflyThenGoes() throws {
        let (e, start) = engineForPasses(secondsBefore: 600)
        let end = try #require(e.nextStationPass(after: start)).pass.end.date
        #expect(e.stationCards(at: end.addingTimeInterval(10)).count == 1)
        #expect(e.stationCards(at: end.addingTimeInterval(30)).isEmpty)
    }

    @Test func thePassesAreTheOnesTheFinderFindsForTheViewersHome() throws {
        let (e, start) = engineForPasses(secondsBefore: 600)
        let orbit = try #require(SatelliteOrbit(issElements))
        let direct = PassFinder.visiblePasses(of: orbit, from: appleParkLike, between: start.addingTimeInterval(-1200), and: start.addingTimeInterval(10 * 86_400))
        let issPasses = e.stationPasses.filter { $0.object == .iss }.map(\.pass)
        #expect(issPasses == direct && !direct.isEmpty)
        #expect(e.nextStationPass(after: start)?.pass.id == direct.first?.id)
        #expect(e.nextStationPass(after: start.addingTimeInterval(86_400))?.pass.id == direct.first { $0.end.date > start.addingTimeInterval(86_400) }?.id)
    }

    @Test func nothingShowsWhenTheFeatureIsOffOrInDemoMode() {
        let (off, start) = engineForPasses(secondsBefore: 600) { $0.issEnabled = false }
        #expect(off.stationCards(at: start).isEmpty && off.nextStationPass(after: start) == nil && off.stationStatus(at: start) == .off)
        let (demo, _) = engineForPasses(secondsBefore: 600) { $0.demoMode = true }
        #expect(demo.stationCards(at: start).isEmpty && demo.stationStatus(at: start) == .demo)
    }

    @Test func switchingItOffClearsEverythingAndOnAgainBringsItBack() throws {
        let (e, start) = engineForPasses(secondsBefore: 600)
        #expect(!e.stationCards(at: start).isEmpty)
        e.settings.issEnabled = false
        #expect(e.stationCards(at: start).isEmpty && e.stationPasses.isEmpty)
        e.settings.issEnabled = true
        e.useStationElements(issElements, at: start.addingTimeInterval(-600))
        #expect(!e.stationCards(at: start).isEmpty)
    }

    @Test func oldElementsAreNotTrusted() {
        let (e, start) = engineForPasses(secondsBefore: 600)
        let stale = issElements.epoch.addingTimeInterval(SpaceObject.maximumElementAge + 3600)
        if case .outdated = e.stationStatus(at: stale) {} else { Issue.record("expected outdated at \(stale)") }
        #expect(e.stationCards(at: stale).isEmpty && e.nextStationPass(after: stale) == nil)
        if case .ready = e.stationStatus(at: start) {} else { Issue.record("expected ready at \(start)") }
    }

    // MARK: Sounds

    @Test func aHeadsUpSoundWhenTheCardAppearsAndAnotherAsThePassBegins() throws {
        let (e, start) = engineForPasses(secondsBefore: 20 * 60)
        e.updateStation(now: start.addingTimeInterval(-16 * 60))
        #expect(e.stationChime == nil)
        e.updateStation(now: start.addingTimeInterval(-14 * 60))
        #expect(e.stationChime == StationChime(kind: .headsUp, serial: 1))
        e.updateStation(now: start.addingTimeInterval(-10 * 60))
        e.updateStation(now: start.addingTimeInterval(-60))
        #expect(e.stationChime?.serial == 1)                           // no repeats while waiting
        e.updateStation(now: start.addingTimeInterval(5))
        #expect(e.stationChime == StationChime(kind: .rising, serial: 2))
        e.updateStation(now: start.addingTimeInterval(60))
        #expect(e.stationChime?.serial == 2)
    }

    @Test func joiningAPassAlreadyUnderWayOnlySoundsOnce() {
        let (e, start) = engineForPasses(secondsBefore: 20 * 60)
        e.updateStation(now: start.addingTimeInterval(30))
        #expect(e.stationChime == StationChime(kind: .rising, serial: 1))
    }

    @Test func theSampleCardShowsAndSoundsBothChimesThenGoes() {
        var s = AppSettings(); s.demoMode = false; s.home = appleParkLike
        let e = TrackingEngine(settings: s, persists: false)
        let t0 = at(1_800_000_000)
        e.showSampleStationPass(at: t0)
        #expect(e.stationChime == StationChime(kind: .headsUp, serial: 1))
        let card = e.stationCards(at: t0.addingTimeInterval(1)).first
        #expect(card?.isSample == true && card?.phase == .imminent && card?.headline == "Sample · Space Station pass")
        e.updateStation(now: t0.addingTimeInterval(41))
        #expect(e.stationChime == StationChime(kind: .rising, serial: 2))
        #expect(e.stationCards(at: t0.addingTimeInterval(41)).first?.headline == "Visible now")
        #expect(e.stationCards(at: t0.addingTimeInterval(70)).isEmpty)
        e.updateStation(now: t0.addingTimeInterval(70))
        e.showSampleStationPass(at: t0.addingTimeInterval(100))        // a second sample sounds again
        #expect(e.stationChime == StationChime(kind: .headsUp, serial: 3))
    }

    // MARK: Fetching

    private struct Provider: OrbitalElementsProviding {
        var result: Result<OrbitalElements, Error>
        func elements(for object: SpaceObject) async throws -> OrbitalElements {
            // Only the Space Station has data here; the other station is reported as unavailable.
            if object == .iss { return try result.get() }
            throw FeedError.http(404)
        }
    }

    private func settled(_ e: TrackingEngine, until done: () -> Bool) async {
        for _ in 0..<100 where !done() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func downloadedElementsAreUsedAndPassesWorkedOut() async throws {
        var s = AppSettings(); s.demoMode = false; s.home = appleParkLike
        let e = TrackingEngine(settings: s, persists: false, orbits: Provider(result: .success(issElements)))
        e.startStationLoop()
        await settled(e) { e.stationElementSets[.iss] != nil }
        defer { e.stop() }
        #expect(e.stationElementSets[.iss] == issElements)
        if case .ready(let epoch) = e.stationStatus(at: issElements.epoch.addingTimeInterval(3600)) { #expect(epoch == issElements.epoch) } else { Issue.record("not ready") }
    }

    @Test func aFailedDownloadIsReportedNotHidden() async {
        var s = AppSettings(); s.demoMode = false; s.home = appleParkLike
        let e = TrackingEngine(settings: s, persists: false, orbits: Provider(result: .failure(FeedError.http(503))))
        e.startStationLoop()
        await settled(e) { e.stationFetchErrors[.iss] != nil }
        defer { e.stop() }
        #expect(e.stationFetchErrors[.iss] == "Data provider returned HTTP 503")
        #expect(e.stationStatus(for: .iss, at: Date()) == .failed("Data provider returned HTTP 503"))
    }

    @Test func noNetworkIsTouchedWithoutASourceInTestsOrPreviews() {
        var s = AppSettings(); s.demoMode = false; s.home = appleParkLike
        let e = TrackingEngine(settings: s, persists: false)
        e.startStationLoop()
        #expect(e.stationTask == nil)
    }

    @Test func theDownloadAddressCarriesNoLocation() {
        let iss = CelesTrakProvider.url(for: .iss).absoluteString, tiangong = CelesTrakProvider.url(for: .tiangong).absoluteString
        #expect(iss == "https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=TLE")
        #expect(tiangong == "https://celestrak.org/NORAD/elements/gp.php?CATNR=48274&FORMAT=TLE")
        #expect(!iss.contains("lat") && !iss.contains("lon") && !tiangong.contains("lat") && !tiangong.contains("lon"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_TESTS"] != nil))
    func liveElementsPutTheStationWhereAPublicTrackerSaysItIs() async throws {
        let elements = try await CelesTrakProvider().elements(for: .iss)
        #expect(elements.catalogNumber == 25544 && abs(elements.age(at: Date())) < 5 * 86_400)
        let now = Date()
        let mine = try #require(SatelliteOrbit(elements)?.sample(at: now))
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.wheretheiss.at/v1/satellites/25544")!)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let theirs = GeoPoint(latitude: try #require(json["latitude"] as? Double), longitude: try #require(json["longitude"] as? Double))
        // Both are predictions from nearly the same orbit; the data is a few seconds old, which is 30 km at orbital speed.
        #expect(Geo.distanceNM(mine.subpoint, theirs) < 60)
    }
}

private extension Aircraft {
    func withTime(_ date: Date) -> Aircraft { var a = self; a.positionTime = date; a.position = Geo.destination(from: position, bearing: trackDeg ?? 0, distanceNM: (groundSpeedKt ?? 0) * date.timeIntervalSince(positionTime) / 3600); return a }
}

/// The Tiangong (Tianhe core module) element set published by CelesTrak on 2026-11-01.
let tiangongElements = OrbitalElements(
    name: "CSS (TIANHE)",
    line1: "1 48274U 21035A   26305.38936679  .00008747  00000+0  10390-3 0  9994",
    line2: "2 48274  41.4675 208.4160 0004086 243.9286 116.1132 15.61278896314597")!

@Suite struct TiangongOrbitTests {
    // Reference values: python-sgp4 for positions; Skyfield with DE421 for passes and sky angles, observer at 37.3349, -122.0090.
    @Test func theCatalogueKnowsBothStations() {
        #expect(SpaceObject.allCases == [.iss, .tiangong])
        #expect(SpaceObject(catalogNumber: 25544) == .iss && SpaceObject(catalogNumber: 48274) == .tiangong && SpaceObject(catalogNumber: 1) == nil)
        #expect(tiangongElements.catalogNumber == SpaceObject.tiangong.catalogNumber)
        #expect(abs(tiangongElements.periodMinutes - 92.2) < 0.1)
    }

    @Test func positionsMatchTheReference() throws {
        let sgp4 = try #require(SGP4(tiangongElements))
        let cases: [(Double, Vec3, Vec3)] = [
            (0, Vec3(x: -5948.09241773, y: -3218.26281153, z: -0.00443701), Vec3(x: 2.74030745, y: -5.05883820, z: 5.08799710)),
            (45, Vec3(x: 6110.68269969, y: 2874.33515671, z: 315.66536094), Vec3(x: -2.23508180, y: 5.31611288, z: -5.07711786)),
            (600, Vec3(x: 5863.76160412, y: 3341.93795780, z: -395.27264705), Vec3(x: -3.11033141, y: 4.86289591, z: -5.06980739)),
            (2880, Vec3(x: 2092.61447054, y: -4637.14256454, z: 4448.25703629), Vec3(x: 7.16422338, y: 2.71795620, z: -0.53693750)),
            (10080, Vec3(x: 5565.68126027, y: -3428.86066675, z: 1726.44374279), Vec3(x: 4.18105173, y: 4.41494211, z: -4.69368289)),
        ]
        for (minutes, r, v) in cases {
            let s = try #require(sgp4.propagate(minutesSinceEpoch: minutes))
            #expect(abs(s.position.x - r.x) < 1e-4 && abs(s.position.y - r.y) < 1e-4 && abs(s.position.z - r.z) < 1e-4, "position at \(minutes) min")
            #expect(abs(s.velocity.x - v.x) < 1e-6 && abs(s.velocity.y - v.y) < 1e-6 && abs(s.velocity.z - v.z) < 1e-6, "velocity at \(minutes) min")
        }
    }

    @Test func skyAnglesAndGroundPointMatchTheReferenceAtAHighPass() throws {
        let orbit = try #require(SatelliteOrbit(tiangongElements, standardMagnitude: SpaceObject.tiangong.standardMagnitude))
        let date = at(1_793_587_329)
        let v = try #require(orbit.view(from: Sky.Observer(appleParkLike), at: date))
        #expect(abs(v.azimuthDeg - 17.2099) < 0.05 && abs(v.elevationDeg - 69.2060) < 0.02 && abs(v.rangeKm - 413.293) < 0.2)
        let s = try #require(orbit.sample(at: date))
        #expect(abs(s.subpoint.latitude - 38.5242) < 0.001 && abs(s.subpoint.longitude + 121.5397) < 0.001 && abs(s.altitudeKm - 387.967) < 0.01)
    }

    private struct Ref { let start: Double, peak: Double, end: Double, peakEl: Double
        init(_ s: Double, _ p: Double, _ e: Double, _ h: Double) { start = s; peak = p; end = e; peakEl = h } }
    private static let reference: [Ref] = [
        Ref(1_793_587_139.0, 1_793_587_329.0, 1_793_587_329.0, 69.2),
        Ref(1_793_669_946.0, 1_793_670_131.0, 1_793_670_316.0, 48.5),
        Ref(1_793_675_759.0, 1_793_675_849.0, 1_793_675_849.0, 23.3),
        Ref(1_793_758_559.0, 1_793_758_749.0, 1_793_758_841.0, 73.9),
        Ref(1_793_847_194.0, 1_793_847_350.0, 1_793_847_376.0, 23.0),
        Ref(1_793_929_979.0, 1_793_930_160.0, 1_793_930_340.0, 41.0),
        Ref(1_794_101_476.0, 1_794_101_563.0, 1_794_101_717.0, 22.9),
    ]

    private func twelveDays() throws -> [SatellitePass] {
        let orbit = try #require(SatelliteOrbit(tiangongElements, standardMagnitude: SpaceObject.tiangong.standardMagnitude))
        let start = at(1_793_534_400)
        return PassFinder.visiblePasses(of: orbit, from: appleParkLike, between: start, and: start.addingTimeInterval(12 * 86_400))
    }

    @Test func findsTheSamePassesAsTheReference() throws {
        let passes = try twelveDays()
        #expect(passes.count == Self.reference.count)
        for (pass, expected) in zip(passes, Self.reference) {
            #expect(abs(pass.start.date.timeIntervalSince1970 - expected.start) < 2.5, "start of \(expected.start)")
            #expect(abs(pass.peak.date.timeIntervalSince1970 - expected.peak) < 2.5, "peak of \(expected.start)")
            #expect(abs(pass.end.date.timeIntervalSince1970 - expected.end) < 2.5, "end of \(expected.start)")
            #expect(abs(pass.peak.elevationDeg - expected.peakEl) < 0.3, "peak height of \(expected.start)")
        }
    }

    @Test func itsPassesAreFaintButStillBrightWhenHighUp() throws {
        let passes = try twelveDays()
        for pass in passes { #expect((-3.6 ... 1.5).contains(pass.brightestMagnitude), "magnitude \(pass.brightestMagnitude)") }
        #expect(passes.contains { $0.brightestMagnitude > 0 })       // some low passes are faint: that is what the floor is for
        let high = try #require(passes.max { $0.peak.elevationDeg < $1.peak.elevationDeg })
        #expect(high.brightestMagnitude < -2 && high.brightestMagnitude > -3.6)     // about -2.6 for a good pass, as published
    }

    @Test func aFainterStandardMagnitudeShiftsBrightnessByExactlyThatMuch() {
        let sat = Vec3(x: 6_790, y: 0, z: 0), observer = Vec3(x: 6_378, y: 0, z: 0), sun = Vec3(x: 0.2, y: 0.9, z: 0.4).unit
        let iss = SatelliteOrbit.magnitude(satellite: sat, observer: observer, sun: sun, rangeKm: 412, standard: SpaceObject.iss.standardMagnitude)
        let tiangong = SatelliteOrbit.magnitude(satellite: sat, observer: observer, sun: sun, rangeKm: 412, standard: SpaceObject.tiangong.standardMagnitude)
        #expect(abs((tiangong - iss) - 1.3) < 1e-9)
    }
}

@MainActor
@Suite struct TwoStationEngineTests {
    private func engine(change: (inout AppSettings) -> Void = { _ in }) -> TrackingEngine {
        var s = AppSettings(); s.demoMode = false; s.home = appleParkLike
        change(&s)
        return TrackingEngine(settings: s, persists: false)
    }

    /// Home 5 NM from the point under Tiangong at the high pass at 1793587329.
    private func engineUnderTiangong(change: (inout AppSettings) -> Void = { _ in }) throws -> (TrackingEngine, Date) {
        let t0 = at(1_793_587_329)
        let under = try #require(SatelliteOrbit(tiangongElements)).sample(at: t0)!
        var s = AppSettings(); s.demoMode = false
        s.home = Geo.destination(from: under.subpoint, bearing: 250, distanceNM: 5)
        change(&s)
        return (TrackingEngine(settings: s, persists: false), t0)
    }

    @Test func tiangongIsTrackedLikeAnAircraftWithItsOwnIdentity() throws {
        let (e, t0) = try engineUnderTiangong()
        e.useStationElements(tiangongElements, at: t0)
        e.ingest([], at: t0)
        let station = try #require(e.aircraft.first)
        #expect(station.id == "CSS" && station.aircraft.title == "Tiangong" && station.aircraft.isSpacecraft)
        #expect(station.typeName == "Tiangong Space Station")
        #expect(AircraftTypes.silhouette(for: station.aircraft) == .tiangong)
        #expect(abs((station.aircraft.spacecraft?.altitudeKm ?? 0) - 388) < 3 && station.aircraft.spacecraft?.name == "Tiangong Space Station")
        #expect(e.featuredID == "CSS")
        #expect(SpaceObject.iss.silhouette == .station && SpaceObject.tiangong.silhouette == .tiangong)
    }

    @Test func tiangongKeepsItsTrailWhileTheOtherStationIsBeingUpdatedToo() throws {
        let (e, t0) = try engineUnderTiangong()
        e.useStationElements(issElements, at: t0)
        e.useStationElements(tiangongElements, at: t0)
        e.updateStation(now: t0.addingTimeInterval(2))
        e.updateStation(now: t0.addingTimeInterval(4))
        let station = try #require(e.aircraft.first { $0.id == "CSS" })
        #expect(station.firstSeen == t0 && station.trail.count >= 3)
    }

    @Test func theSpaceStationDoesNotAppearJustBecauseTiangongIsOverhead() throws {
        let (e, t0) = try engineUnderTiangong()
        e.useStationElements(issElements, at: t0)
        e.useStationElements(tiangongElements, at: t0)
        #expect(e.aircraft.map(\.id) == ["CSS"])           // the ISS is on the other side of the world
    }

    @Test func passesFromBothStationsAreListedSoonestFirstEachWithItsOwnName() throws {
        let e = engine()
        let start = at(1_793_538_937)
        e.useStationElements(issElements, at: start.addingTimeInterval(-600))
        e.useStationElements(tiangongElements, at: start.addingTimeInterval(-600))
        let objects = Set(e.stationPasses.map(\.object))
        #expect(objects == [.iss, .tiangong])
        #expect(zip(e.stationPasses, e.stationPasses.dropFirst()).allSatisfy { $0.pass.start.date <= $1.pass.start.date })
        #expect(Set(e.stationPasses.map(\.id)).count == e.stationPasses.count)
        // The ISS pass at 1793538937 comes first; once it is over, Tiangong's at 1793587139 is next, then the ISS's at 1793622622.
        #expect(e.nextStationPass(after: start)?.object == .iss)
        #expect(e.nextStationPass(after: at(1_793_540_000))?.object == .tiangong)
        #expect(e.nextStationPass(after: at(1_793_588_000))?.object == .iss)            // the ISS's second comes before Tiangong's
        #expect(e.nextStationPass(after: at(1_793_629_000))?.object == .tiangong)       // then Tiangong's second, before the ISS's fourth
        let cards = e.stationCards(at: at(1_793_587_139 - 600))
        #expect(cards.map(\.object) == [.tiangong] && cards.first?.name == "Tiangong Space Station")
    }

    @Test func tiangongsFaintPassesAreNotAnnouncedButTheSpaceStationsAre() {
        let e = engine()
        e.useStationElements(tiangongElements, at: at(1_793_534_400))
        let tiangong = e.stationPasses.filter { $0.object == .tiangong }
        #expect(!tiangong.isEmpty && tiangong.allSatisfy { $0.pass.brightestMagnitude <= -1.0 })
        // The reference list has Tiangong passes of magnitude +0.9, -0.4 and -0.1 (starting 1793675759, 1793847194 and 1794101476): none is announced.
        let starts = Set(tiangong.map { Int($0.pass.start.date.timeIntervalSince1970) })
        #expect(starts.isDisjoint(with: [1_793_675_759, 1_793_847_194, 1_794_101_476].flatMap { [$0 - 2, $0 - 1, $0, $0 + 1, $0 + 2] }))
        #expect(starts.count == 4)
        // The Space Station has no floor: every pass the finder finds in the same ten-day window is listed, even its faintest (-1.1).
        let now = at(1_793_534_400)
        e.useStationElements(issElements, at: now)
        let direct = PassFinder.visiblePasses(of: SatelliteOrbit(issElements)!, from: appleParkLike, between: now.addingTimeInterval(-600), and: now.addingTimeInterval(10 * 86_400))
        #expect(e.stationPasses.filter { $0.object == .iss }.map(\.pass) == direct && direct.count >= 6)
    }

    @Test func eachStationHasItsOwnSwitch() throws {
        let e = engine()
        let start = at(1_793_538_937)
        e.useStationElements(issElements, at: start.addingTimeInterval(-600))
        e.useStationElements(tiangongElements, at: start.addingTimeInterval(-600))
        e.settings.tiangongEnabled = false
        #expect(!e.stationPasses.contains { $0.object == .tiangong } && e.stationPasses.contains { $0.object == .iss })
        #expect(e.stationStatus(for: .tiangong) == .off)
        if case .ready = e.stationStatus(for: .iss, at: start) {} else { Issue.record("the ISS should still be ready") }
        e.settings.issEnabled = false
        #expect(e.stationPasses.isEmpty && e.nextStationPass(after: start) == nil && !e.settings.watchesAnyStation)
    }

    @Test func switchingTiangongOffRemovesItFromTheMapButNotTheOtherStation() throws {
        let (e, t0) = try engineUnderTiangong()
        e.useStationElements(tiangongElements, at: t0)
        #expect(e.aircraft.map(\.id) == ["CSS"])
        e.settings.tiangongEnabled = false
        #expect(e.aircraft.isEmpty)
        e.ingest([], at: t0.addingTimeInterval(1))
        #expect(e.aircraft.isEmpty)
    }

    @Test func eachStationsPassGetsItsOwnHeadsUpSound() throws {
        let e = engine()
        let issStart = at(1_793_538_937), tiangongStart = at(1_793_587_139)
        e.useStationElements(issElements, at: issStart.addingTimeInterval(-20 * 60))
        e.useStationElements(tiangongElements, at: issStart.addingTimeInterval(-20 * 60))
        e.updateStation(now: issStart.addingTimeInterval(-14 * 60))
        #expect(e.stationChime == StationChime(kind: .headsUp, serial: 1))
        e.updateStation(now: tiangongStart.addingTimeInterval(-14 * 60))
        #expect(e.stationChime == StationChime(kind: .headsUp, serial: 2))
    }

    @Test func theSampleCanBeEitherStation() {
        let e = engine()
        let t0 = at(1_800_000_000)
        e.showSampleStationPass(for: .tiangong, at: t0)
        let card = e.stationCards(at: t0.addingTimeInterval(1)).first
        #expect(card?.object == .tiangong && card?.headline == "Sample · Tiangong pass" && card?.isSample == true)
    }

    @Test func cardIdsDifferBetweenStationsEvenForTheSameMoment() {
        let pass = StationPassCardTestPass.make()
        #expect(StationPassCard(pass: pass, asOf: pass.start.date, object: .iss).id != StationPassCard(pass: pass, asOf: pass.start.date, object: .tiangong).id)
    }

    @Test func settingsRememberBothSwitchesAndOlderFilesKeepTiangongOn() throws {
        var s = AppSettings(); s.tiangongEnabled = false
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)) == s)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"issEnabled":false,"issLeadMinutes":10}"#.utf8))
        #expect(!old.issEnabled && old.tiangongEnabled && old.issLeadMinutes == 10 && old.watchesAnyStation)
    }

    private struct PerObjectProvider: OrbitalElementsProviding {
        var results: [SpaceObject: Result<OrbitalElements, Error>]
        func elements(for object: SpaceObject) async throws -> OrbitalElements { try (results[object] ?? .failure(FeedError.malformed)).get() }
    }

    @Test func eachStationsOrbitIsDownloadedIndependently() async {
        var s = AppSettings(); s.demoMode = false; s.home = appleParkLike
        let e = TrackingEngine(settings: s, persists: false,
                               orbits: PerObjectProvider(results: [.iss: .success(issElements), .tiangong: .failure(FeedError.http(503))]))
        e.startStationLoop()
        for _ in 0..<100 where e.stationElementSets[.iss] == nil || e.stationFetchErrors[.tiangong] == nil { try? await Task.sleep(for: .milliseconds(20)) }
        defer { e.stop() }
        #expect(e.stationElementSets[.iss] == issElements && e.stationElementSets[.tiangong] == nil)
        #expect(e.stationFetchErrors[.tiangong] == "Data provider returned HTTP 503" && e.stationFetchErrors[.iss] == nil)
        #expect(e.stationStatus(for: .tiangong) == .failed("Data provider returned HTTP 503"))
    }
}

private enum StationPassCardTestPass {
    static func make() -> SatellitePass {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let p = SatellitePass.Point(date: start, azimuthDeg: 225, elevationDeg: 20)
        return SatellitePass(start: p, peak: p, end: p, path: [p], brightestMagnitude: -2, startsOutOfShadow: false, endsInShadow: false)
    }
}
