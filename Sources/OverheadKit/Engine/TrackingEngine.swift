import Foundation
import Observation

public enum FeedStatus: Equatable, Sendable {
    case starting
    case live(updated: Date)
    case offline(String)
}

/// Polls a feed, keeps per-aircraft history, enriches with routes and photos, and decides which
/// aircraft to feature. All state is main-actor; the views observe it directly.
@MainActor
@Observable
public final class TrackingEngine {
    public private(set) var aircraft: [TrackedAircraft] = []
    public private(set) var status: FeedStatus = .starting
    public private(set) var sightings: [Sighting] = []
    public private(set) var featuredID: String?
    public private(set) var pinned = false
    public private(set) var diagnostics = Diagnostics()

    public var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            if persists { SettingsStore.save(settings) }
            let needsRestart = settings.home != oldValue.home || settings.feed != oldValue.feed
                || settings.demoMode != oldValue.demoMode || settings.refreshSeconds != oldValue.refreshSeconds
                || settings.autoFailover != oldValue.autoFailover
            if needsRestart { restart() }
            else if settings.mapRadiusNM != oldValue.mapRadiusNM { viewRadiusDidChange() }
            if settings.photoContact != oldValue.photoContact { scheduleContactUpdate() }
            if settings.issEnabled != oldValue.issEnabled || settings.tiangongEnabled != oldValue.tiangongEnabled { stationEnabledDidChange() }
        }
    }

    @ObservationIgnored private var feed: any AircraftFeed = DemoFeed()
    @ObservationIgnored private var routes: any RouteProviding = DemoRouteProvider()
    @ObservationIgnored private var photos: any PhotoProviding = NoPhotos()
    @ObservationIgnored private let liveRoutes = LiveRouteProvider()
    @ObservationIgnored private let livePhotos = PlanespottersPhotoProvider()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var pinnedUntil: Date?
    @ObservationIgnored private var lastCycleSlot = -1
    @ObservationIgnored private var insideIDs: Set<String> = []
    @ObservationIgnored private let persists: Bool

    @ObservationIgnored private var contactTask: Task<Void, Never>?
    @ObservationIgnored private var fetchedRadiusNM = 0.0
    @ObservationIgnored private var emergencySince: [String: Date] = [:]
    @ObservationIgnored private var flybyActive: [String: (since: Date, lastQualified: Date)] = [:]
    /// Aircraft that have had their card, until when they are left alone (a plane circling would otherwise keep re-triggering).
    @ObservationIgnored private var flybyDone: [String: Date] = [:]
    @ObservationIgnored private var sampleFlyby: (card: FlybyCard, until: Date)?
    /// The area's pressure setting, kept for a while so a quiet moment doesn't bring the negative altitudes back.
    @ObservationIgnored private var altimeter: (hPa: Double, at: Date)?
    /// Each station's orbit, and the passes worked out from them for the viewer's home (soonest first).
    public private(set) var stationElementSets: [SpaceObject: OrbitalElements] = [:]
    public private(set) var stationPasses: [StationPass] = []
    public private(set) var stationFetchErrors: [SpaceObject: String] = [:]
    /// The latest sound to play; a new value (a higher serial) means play it again.
    public private(set) var stationChime: StationChime?
    @ObservationIgnored private var stationOrbits: [SpaceObject: SatelliteOrbit] = [:]
    @ObservationIgnored private var stationUpdatedAt: [SpaceObject: Date] = [:]
    @ObservationIgnored private var stationPassesComputedAt: [SpaceObject: Date] = [:]
    @ObservationIgnored var stationTask: Task<Void, Never>?
    @ObservationIgnored private var stationAnnounced: [String: StationPassCard.Phase] = [:]
    @ObservationIgnored private var stationChimeSerial = 0
    @ObservationIgnored private var sampleStation: (object: SpaceObject, pass: SatellitePass, until: Date)?
    @ObservationIgnored private let injectedOrbits: (any OrbitalElementsProviding)?
    /// A card stays this long after its pass ends, and elements are downloaded again after this long.
    @ObservationIgnored let stationLinger: TimeInterval = 20
    @ObservationIgnored let stationRefreshInterval: TimeInterval = 8 * 3600
    /// A card is dropped this long after its aircraft stops qualifying, and never stays longer than `flybyMaxShow`.
    @ObservationIgnored let flybyLinger: TimeInterval = 6
    @ObservationIgnored let flybyMaxShow: TimeInterval = 90
    @ObservationIgnored let flybyCooldown: TimeInterval = 10 * 60
    /// An emergency squawk must hold this long before it is shown; pilots dialling a code pass through 7700 briefly.
    @ObservationIgnored var emergencyConfirmAfter: TimeInterval = 12
    @ObservationIgnored private let injectedRoutes: (any RouteProviding)?
    @ObservationIgnored private let injectedPhotos: (any PhotoProviding)?

    public init(settings: AppSettings? = nil, persists: Bool = true,
                routes: (any RouteProviding)? = nil, photos: (any PhotoProviding)? = nil, orbits: (any OrbitalElementsProviding)? = nil) {
        self.persists = persists
        self.injectedRoutes = routes
        self.injectedPhotos = photos
        self.injectedOrbits = orbits
        if let routes { self.routes = routes }
        if let photos { self.photos = photos }
        self.settings = settings ?? (persists ? SettingsStore.load() : AppSettings())
        self.sightings = persists ? SettingsStore.loadSightings() : []
        if persists { ClientIdentity.userContact = self.settings.photoContact }
    }

    // MARK: Derived state

    public var isDemo: Bool { settings.demoMode || settings.home == nil }
    public var needsLocation: Bool { settings.home == nil && !settings.demoMode }
    public var home: GeoPoint { isDemo ? (settings.home ?? DemoFeed.defaultHome) : settings.home! }
    public var locationName: String {
        if settings.demoMode || settings.home == nil { return DemoFeed.defaultHomeName }
        return settings.homeName ?? String(format: "%.2f°, %.2f°", settings.home!.latitude, settings.home!.longitude)
    }
    public var sourceName: String { feed.name }
    /// How far out aircraft are requested: wider than the view so the next zoom step is already covered.
    var fetchRadiusNM: Double { min(250, max(settings.mapRadiusNM * 1.9, 24)) }

    /// Aircraft inside the current map view (the engine also holds some just beyond it).
    public func visibleAircraft(at now: Date = Date()) -> [TrackedAircraft] {
        let limit = settings.mapRadiusNM * 1.08
        let center = home
        return aircraft.filter { Geo.distanceNM(center, $0.aircraft.position(at: now)) <= limit }
    }

    /// Aircraft worth a banner right now, emergencies first, then nearest first.
    public func alerts(at now: Date = Date()) -> [AircraftAlert] {
        guard settings.alertLevel != .off else { return [] }
        let center = home, onMapLimit = settings.mapRadiusNM * 1.08
        let found: [AircraftAlert] = aircraft.compactMap { t in
            guard let kind = Alerts.evaluate(t.aircraft, level: settings.alertLevel) else { return nil }
            if kind.isEmergency {
                guard let since = emergencySince[t.id], now.timeIntervalSince(since) >= emergencyConfirmAfter else { return nil }
            }
            let d = Geo.distanceNM(center, t.aircraft.position(at: now))
            return AircraftAlert(id: t.id, kind: kind, title: t.flightNumber ?? t.aircraft.title, distanceNM: d, onMap: d <= onMapLimit)
        }
        return found.sorted { a, b in
            a.kind.isEmergency != b.kind.isEmergency ? a.kind.isEmergency : a.distanceNM < b.distanceNM
        }
    }

    /// Cards for aircraft passing close right now: the most imminent first. Also the viewer's sample card, while it lasts.
    public func flybyCards(at now: Date = Date()) -> [FlybyCard] {
        if let sample = sampleFlyby {
            if now < sample.until { return [sample.card] }
            sampleFlyby = nil
        }
        guard let config = settings.flybyConfig else { return [] }
        let cards: [FlybyCard] = flybyActive.keys.compactMap { id in
            guard let t = aircraft.first(where: { $0.id == id }),
                  let pass = Flyby.evaluate(t.aircraft, home: home, heading: settings.viewerHeadingDeg, at: now, config: config.relaxed)
            else { return nil }
            let detail = [t.typeName, t.operatorName].compactMap { $0 }.joined(separator: " · ")
            return FlybyCard(id: id, title: t.flightNumber ?? t.aircraft.title, detail: detail.isEmpty ? nil : detail, pass: pass,
                             place: pass.look.place(names: settings.directionNames))
        }
        return cards.sorted { abs($0.pass.secondsToClosest ?? 0) < abs($1.pass.secondsToClosest ?? 0) }
    }

    /// Shows a card for a made-up plane due north, so the viewer can check their direction settings against a compass.
    public func showSampleFlyby(for seconds: TimeInterval = 15, at now: Date = Date()) {
        let look = LookDirection(bearingDeg: 0, elevationDeg: 45, headingDeg: settings.viewerHeadingDeg, motion: .leftToRight, trackDeg: 90)
        let pass = FlybyPass(distanceNM: 1, closestNM: 1, secondsToClosest: 20, altitudeFt: 6_000, look: look)
        sampleFlyby = (FlybyCard(id: "sample", title: "Sample", detail: "Where a plane due north of you would be",
                                 pass: pass, place: look.place(names: settings.directionNames), isSample: true), now.addingTimeInterval(seconds))
    }

    public var canZoomIn: Bool { MapZoom.zoomedIn(from: settings.mapRadiusNM, units: settings.units) != nil }
    public var canZoomOut: Bool { MapZoom.zoomedOut(from: settings.mapRadiusNM, units: settings.units) != nil }

    public func zoomIn() {
        if let r = MapZoom.zoomedIn(from: settings.mapRadiusNM, units: settings.units) { settings.mapRadiusNM = r }
    }

    public func zoomOut() {
        if let r = MapZoom.zoomedOut(from: settings.mapRadiusNM, units: settings.units) { settings.mapRadiusNM = r }
    }

    public var featured: TrackedAircraft? { featuredID.flatMap { id in aircraft.first { $0.id == id } } }
    public var sightingsExcludingNearby: [Sighting] {
        let live = Set(aircraft.filter { Geo.distanceNM(home, $0.aircraft.position) <= settings.alertRadiusNM }.map(\.id))
        return sightings.filter { !live.contains($0.hex) }
    }

    // MARK: Lifecycle

    public func start() {
        guard pollTask == nil else { return }
        configureServices()
        pollTask = Task { [weak self] in await self?.pollLoop() }
        tickTask = Task { [weak self] in await self?.tickLoop() }
        startStationLoop()
    }

    public func stop() {
        pollTask?.cancel(); tickTask?.cancel(); stationTask?.cancel()
        pollTask = nil; tickTask = nil; stationTask = nil
    }

    private func restart() {
        stop()
        aircraft = []
        featuredID = nil
        insideIDs = []
        flybyActive = [:]
        flybyDone = [:]
        altimeter = nil
        stationPasses = []; stationPassesComputedAt = [:]; stationAnnounced = [:]; sampleStation = nil
        status = .starting
        start()
    }

    /// Zooming never clears the map. It only re-picks the featured aircraft and, when the view now reaches
    /// past what was last requested, fetches again straight away instead of waiting for the next poll.
    private func viewRadiusDidChange() {
        updateFeatured(now: Date())
        if pollTask != nil, fetchRadiusNM > fetchedRadiusNM + 0.5 {
            pollTask?.cancel()
            pollTask = Task { [weak self] in await self?.pollLoop() }
        }
    }

    private func configureServices() {
        if isDemo {
            feed = DemoFeed(); routes = injectedRoutes ?? DemoRouteProvider(); photos = injectedPhotos ?? NoPhotos()
        } else {
            feed = settings.autoFailover
                ? FailoverFeed(primary: settings.feed.makeFeed(), secondary: settings.feed.other.makeFeed())
                : settings.feed.makeFeed()
            routes = injectedRoutes ?? liveRoutes; photos = injectedPhotos ?? livePhotos
        }
    }

    private func pollLoop() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                let radius = fetchRadiusNM
                fetchedRadiusNM = radius
                let started = Date()
                let list = try await feed.fetch(around: home, radiusNM: radius)
                if Task.isCancelled { return }
                failures = 0
                let finished = Date()
                ingest(list, at: finished)
                status = .live(updated: finished)
                diagnostics.recordSuccess(at: finished, latency: finished.timeIntervalSince(started), count: list.count, radiusNM: radius)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                failures += 1
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                status = .offline(message)
                diagnostics.recordFailure(at: Date(), message: message)
            }
            let base = max(settings.refreshSeconds, 3)
            let delay = failures == 0 ? base : min(60, base * pow(2, Double(min(failures, 5))))
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func tickLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let now = Date()
            aircraft.removeAll { now.timeIntervalSince($0.aircraft.positionTime) > 75 }
            updateStation(now: now)
            updateFeatured(now: now)
            updateFlybys(now: now)
        }
    }

    // MARK: Photo contact

    /// Applies the contact after typing pauses, so a half-entered address is never sent to Planespotters.
    private func scheduleContactUpdate() {
        contactTask?.cancel()
        contactTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled else { return }
            ClientIdentity.userContact = self.settings.photoContact
            // Photos that were skipped while no contact was set can be fetched now.
            for i in self.aircraft.indices where self.aircraft[i].photo == nil { self.aircraft[i].photoRequested = false }
            self.requestEnrichment(now: Date())
        }
    }

    // MARK: Ingest

    /// Merges a batch of fresh reports. Public so tests and the design preview can drive the engine directly.
    public func ingest(_ reported: [Aircraft], at now: Date) {
        if let local = Altimetry.localSetting(reported) { altimeter = (local, now) }
        let setting = altimeter.flatMap { now.timeIntervalSince($0.at) < 30 * 60 ? $0.hPa : nil }
        let incoming = reported.map { Altimetry.corrected($0, localSetting: setting) }
        let center = home
        let keepWithin = fetchRadiusNM * 1.1
        var previous = Dictionary(uniqueKeysWithValues: aircraft.map { ($0.id, $0) })
        var merged: [TrackedAircraft] = []

        for a in incoming {
            guard Geo.distanceNM(center, a.position(at: now)) <= keepWithin else { continue }
            var t = previous.removeValue(forKey: a.id) ?? TrackedAircraft(aircraft: a, firstSeen: now)
            t.update(with: a)
            merged.append(t)
        }
        // Aircraft missing from one response keep coasting for a while rather than blinking out.
        for (_, old) in previous where now.timeIntervalSince(old.aircraft.positionTime) < 45 { merged.append(old) }

        for t in merged {
            if Alerts.evaluate(t.aircraft, level: .emergency) != nil { emergencySince[t.id] = emergencySince[t.id] ?? now }
            else { emergencySince[t.id] = nil }
        }
        emergencySince = emergencySince.filter { id, _ in merged.contains { $0.id == id } }
        merged.sort { Geo.distanceNM(center, $0.aircraft.position(at: now)) < Geo.distanceNM(center, $1.aircraft.position(at: now)) }
        aircraft = merged
        // The station is never left to coast (it moves 4 NM a second): its orbit says where it is, or that it is gone. The kept
        // entry is only so its trail and first-seen time survive the feed report.
        refreshStationAircraft(now: now)
        recordSightings(now: now)
        updateFeatured(now: now)
        updateFlybys(now: now)
        requestEnrichment(now: now)
    }

    // MARK: Selection

    /// The viewer chose an aircraft; keep it on screen for a minute, then return to automatic.
    public func pin(_ id: String, now: Date = Date()) {
        guard aircraft.contains(where: { $0.id == id }) else { return }
        if featuredID != id { featuredID = id }
        pinnedUntil = now.addingTimeInterval(60)
        if !pinned { pinned = true }
        requestEnrichment(now: now)
    }

    public func unpin() {
        pinnedUntil = nil
        if pinned { pinned = false }
        updateFeatured(now: Date())
    }

    private func updateFeatured(now: Date) {
        let center = home
        let viewRadius = settings.mapRadiusNM * 1.08   // same edge as visibleAircraft, so the card and the strip agree
        func inView(_ t: TrackedAircraft) -> Bool { Geo.distanceNM(center, t.aircraft.position(at: now)) <= viewRadius }
        if let until = pinnedUntil {
            if now < until, let id = featuredID, let t = aircraft.first(where: { $0.id == id }), inView(t) { return }
            pinnedUntil = nil
            if pinned { pinned = false }
        }

        // Only aircraft on the map are candidates; ones fetched just beyond the edge are not.
        let airborne = aircraft.filter { !$0.aircraft.onGround && inView($0) }

        // An aircraft in distress on the map takes the card straight away (unless the viewer picked one).
        if let urgent = airborne.first(where: { Alerts.evaluate($0.aircraft, level: .emergency) != nil
            && now.timeIntervalSince(emergencySince[$0.id] ?? now) >= emergencyConfirmAfter }) {
            if featuredID != urgent.id { featuredID = urgent.id }
            return
        }
        // A station crosses the whole map in seconds and is not something to miss: it takes the card while it is in view.
        if let station = airborne.first(where: { $0.aircraft.isSpacecraft }) {
            if featuredID != station.id { featuredID = station.id }
            return
        }
        let inside = airborne.filter { Geo.distanceNM(center, $0.aircraft.position(at: now)) <= settings.alertRadiusNM }
        let insideSet = Set(inside.map(\.id))
        let newcomers = insideSet.subtracting(insideIDs)
        insideIDs = insideSet

        let pool = inside.isEmpty ? Array(airborne.prefix(1)) : inside
        guard !pool.isEmpty else {
            if featuredID != nil { featuredID = nil }
            return
        }

        // Something just flew into the zone: show it now.
        if let newcomer = pool.first(where: { newcomers.contains($0.id) }) {
            featuredID = newcomer.id
            lastCycleSlot = Int(now.timeIntervalSinceReferenceDate / max(settings.cycleSeconds, 5))
            return
        }

        let slot = Int(now.timeIntervalSinceReferenceDate / max(settings.cycleSeconds, 5))
        if let current = featuredID, let index = pool.firstIndex(where: { $0.id == current }) {
            if settings.autoCycle, pool.count > 1, slot != lastCycleSlot {
                featuredID = pool[(index + 1) % pool.count].id
                lastCycleSlot = slot
            }
        } else {
            featuredID = pool[0].id
            lastCycleSlot = slot
        }
    }

    // MARK: Flybys

    /// Decides which aircraft are on show as flybys: one card per pass, kept while the aircraft qualifies, then left alone.
    func updateFlybys(now: Date) {
        guard let config = settings.flybyConfig else {
            if !flybyActive.isEmpty { flybyActive = [:] }
            return
        }
        let center = home
        flybyDone = flybyDone.filter { $0.value > now }
        for t in aircraft where flybyDone[t.id] == nil {
            let active = flybyActive[t.id] != nil
            guard Flyby.evaluate(t.aircraft, home: center, heading: nil, at: now, config: active ? config.relaxed : config) != nil else { continue }
            flybyActive[t.id] = (since: flybyActive[t.id]?.since ?? now, lastQualified: now)
        }
        for (id, track) in flybyActive {
            let gone = !aircraft.contains { $0.id == id }
            if gone || now.timeIntervalSince(track.lastQualified) > flybyLinger || now.timeIntervalSince(track.since) > flybyMaxShow {
                flybyActive[id] = nil
                flybyDone[id] = now.addingTimeInterval(flybyCooldown)
            }
        }
    }

    // MARK: Sightings

    private func recordSightings(now: Date) {
        let center = home
        var changed = false
        for t in aircraft where !t.aircraft.onGround {
            let d = Geo.distanceNM(center, t.aircraft.position(at: now))
            guard d <= settings.alertRadiusNM else { continue }
            if let i = sightings.firstIndex(where: { $0.hex == t.id && now.timeIntervalSince($0.lastSeen) < 20 * 60 }) {
                sightings[i].lastSeen = now
                if d < sightings[i].closestNM { sightings[i].closestNM = d; sightings[i].altitudeFt = t.aircraft.altitudeFt }
                if let r = t.route { sightings[i].routeText = "\(r.origin.code) → \(r.destination.code)" }
                if sightings[i].typeName == nil { sightings[i].typeName = t.typeName }
            } else {
                sightings.insert(Sighting(
                    hex: t.id, title: t.flightNumber ?? t.aircraft.title, airline: t.operatorName, typeName: t.typeName,
                    routeText: t.route.map { "\($0.origin.code) → \($0.destination.code)" },
                    firstSeen: now, lastSeen: now, closestNM: d, altitudeFt: t.aircraft.altitudeFt), at: 0)
                if sightings.count > 30 { sightings.removeLast(sightings.count - 30) }
                changed = true
            }
        }
        if changed && persists && !isDemo { SettingsStore.saveSightings(sightings) }
    }

    // MARK: Enrichment

    private func requestEnrichment(now: Date) {
        var wanted: [String] = []
        if let f = featuredID { wanted.append(f) }
        wanted += aircraft.prefix(8).map(\.id).filter { $0 != featuredID }

        for id in wanted {
            guard let i = aircraft.firstIndex(where: { $0.id == id }) else { continue }
            let snapshot = aircraft[i].aircraft
            if snapshot.isSpacecraft { continue }

            if aircraft[i].route == nil, now.timeIntervalSince(aircraft[i].routeCheckedAt ?? .distantPast) > 20 {
                aircraft[i].routeCheckedAt = now
                let provider = routes
                Task { [weak self] in
                    let result = await provider.lookup(for: snapshot)
                    self?.update(id) { t in
                        switch result {
                        case .found(let route): t.route = route; t.routeStatus = .found
                        case .unconfirmed: t.routeStatus = .unconfirmed
                        case .unavailable: t.routeStatus = .unavailable
                        // Couldn't ask this time: keep any earlier answer, and don't claim to be still checking.
                        case .failed: if t.routeStatus == .checking { t.routeStatus = .unavailable }
                        }
                    }
                }
            }
            if aircraft[i].photo == nil, !aircraft[i].photoRequested {
                aircraft[i].photoRequested = true
                let provider = photos
                Task { [weak self] in
                    guard let photo = await provider.photo(for: snapshot) else { return }
                    self?.update(id) { $0.photo = photo }
                }
            }
        }
    }

    private func update(_ id: String, _ change: (inout TrackedAircraft) -> Void) {
        guard let i = aircraft.firstIndex(where: { $0.id == id }) else { return }
        change(&aircraft[i])
    }
}

// MARK: - Space stations

extension TrackingEngine {
    private func wanted(_ object: SpaceObject) -> Bool { settings.watches(object) && !isDemo }

    private func usableOrbit(_ object: SpaceObject, at now: Date) -> SatelliteOrbit? {
        guard wanted(object), let orbit = stationOrbits[object], orbit.elements.age(at: now) <= SpaceObject.maximumElementAge else { return nil }
        return orbit
    }

    public func stationStatus(for object: SpaceObject = .iss, at now: Date = Date()) -> StationStatus {
        if !settings.watches(object) { return .off }
        if isDemo { return .demo }
        if let e = stationElementSets[object] { return e.age(at: now) > SpaceObject.maximumElementAge ? .outdated(epoch: e.epoch) : .ready(epoch: e.epoch) }
        if let error = stationFetchErrors[object] { return .failed(error) }
        return .waiting
    }

    /// The next pass worth going outside for, from any station being watched, if one is coming in the next ten days.
    public func nextStationPass(after now: Date = Date()) -> StationPass? {
        stationPasses.first { $0.pass.end.date > now && usableOrbit($0.object, at: now) != nil }
    }

    /// Cards for passes inside the warning time, or under way: soonest first. Also the viewer's sample card, while it lasts.
    public func stationCards(at now: Date = Date()) -> [StationPassCard] {
        if let sample = sampleStation {
            if now < sample.until { return [StationPassCard(pass: sample.pass, asOf: now, object: sample.object, isSample: true)] }
            sampleStation = nil
        }
        let lead = Double(settings.issLeadMinutes) * 60
        return stationPasses
            .filter { usableOrbit($0.object, at: now) != nil && $0.pass.start.date.timeIntervalSince(now) <= lead
                && now <= $0.pass.end.date.addingTimeInterval(stationLinger) }
            .map { StationPassCard($0, asOf: now) }
    }

    /// Shows a made-up pass starting in forty seconds, with its sounds, so the viewer can see and hear what a warning is like.
    public func showSampleStationPass(for object: SpaceObject = .iss, at now: Date = Date()) {
        let start = now.addingTimeInterval(40)
        let path: [SatellitePass.Point] = (0...12).map { i in
            let f = Double(i) / 12
            return .init(date: start.addingTimeInterval(20 * Double(i)), azimuthDeg: 225 - 145 * f, elevationDeg: 10 + 52 * sin(.pi * f))
        }
        let pass = SatellitePass(start: path[0], peak: path[6], end: path[12], path: path, brightestMagnitude: -3.4,
                                 startsOutOfShadow: false, endsInShadow: false)
        sampleStation = (object, pass, start.addingTimeInterval(20))
        announceStation(now: now)
    }

    /// Makes the engine use this orbit, as if it had just been downloaded. How tests and the design preview supply one without the network.
    public func useStationElements(_ elements: OrbitalElements, at now: Date = Date()) {
        guard let object = SpaceObject(catalogNumber: elements.catalogNumber) else { return }
        stationElementSets[object] = elements
        stationOrbits[object] = SatelliteOrbit(elements, standardMagnitude: object.standardMagnitude)
        stationUpdatedAt[object] = now
        stationFetchErrors[object] = nil
        stationPassesComputedAt[object] = nil
        updateStation(now: now)
    }

    /// Once a second: keeps each station's place in the aircraft list, the list of passes, and the sounds up to date.
    func updateStation(now: Date) {
        for object in SpaceObject.allCases {
            if let orbit = usableOrbit(object, at: now) {
                if stationPassesComputedAt[object].map({ now.timeIntervalSince($0) > 3600 }) ?? true { recomputeStationPasses(object, orbit, now: now) }
                updateStationAircraft(object, orbit, now: now)
            } else {
                removeStationAircraft(object)
                if stationPasses.contains(where: { $0.object == object }) { stationPasses.removeAll { $0.object == object } }
                stationPassesComputedAt[object] = nil
            }
        }
        announceStation(now: now)
    }

    /// Just the aircraft list, for a feed report: each station is placed from its orbit, or removed.
    func refreshStationAircraft(now: Date) {
        for object in SpaceObject.allCases {
            if let orbit = usableOrbit(object, at: now) { updateStationAircraft(object, orbit, now: now) } else { removeStationAircraft(object) }
        }
    }

    private func recomputeStationPasses(_ object: SpaceObject, _ orbit: SatelliteOrbit, now: Date) {
        let found = PassFinder.visiblePasses(of: orbit, from: home, between: now.addingTimeInterval(-600), and: now.addingTimeInterval(10 * 86_400))
            .filter { $0.brightestMagnitude <= object.announceBrighterThan }
            .map { StationPass(object: object, pass: $0) }
        stationPasses = (stationPasses.filter { $0.object != object } + found).sorted { $0.pass.start.date < $1.pass.start.date }
        stationPassesComputedAt[object] = now
    }

    private func removeStationAircraft(_ object: SpaceObject) {
        if aircraft.contains(where: { $0.id == object.id }) { aircraft.removeAll { $0.id == object.id } }
    }

    /// A station is in the aircraft list only while it is within range of home, exactly as an aircraft would be.
    private func updateStationAircraft(_ object: SpaceObject, _ orbit: SatelliteOrbit, now: Date) {
        let center = home
        guard let sample = orbit.sample(at: now), Geo.distanceNM(center, sample.subpoint) <= fetchRadiusNM * 1.1 else {
            removeStationAircraft(object)
            return
        }
        let station = object.aircraft(from: sample, periodMinutes: orbit.elements.periodMinutes)
        var tracked: TrackedAircraft
        if let i = aircraft.firstIndex(where: { $0.id == object.id }) {
            tracked = aircraft.remove(at: i)
        } else {
            tracked = TrackedAircraft(aircraft: station, firstSeen: now)
            tracked.photoRequested = true
            tracked.routeCheckedAt = .distantFuture
        }
        tracked.update(with: station)
        let distance = Geo.distanceNM(center, station.position)
        aircraft.insert(tracked, at: aircraft.firstIndex { Geo.distanceNM(center, $0.aircraft.position(at: now)) > distance } ?? aircraft.count)
        if distance <= settings.alertRadiusNM { recordSightings(now: now) }
    }

    /// A heads-up sound when a card first appears, and another as the pass begins.
    private func announceStation(now: Date) {
        var seen: Set<String> = []
        for card in stationCards(at: now) {
            let key = card.isSample ? "sample" : card.id
            seen.insert(key)
            let phase = card.phase, before = stationAnnounced[key]
            if before == nil, phase != .ended { sound(phase == .underway ? .rising : .headsUp) }
            else if let before, before != .underway, phase == .underway { sound(.rising) }
            stationAnnounced[key] = phase
        }
        if stationAnnounced.keys.contains(where: { !seen.contains($0) }) { stationAnnounced = stationAnnounced.filter { seen.contains($0.key) } }
    }

    private func sound(_ kind: StationChime.Kind) {
        stationChimeSerial += 1
        stationChime = StationChime(kind: kind, serial: stationChimeSerial)
    }

    private func stationEnabledDidChange() {
        // Start again so a station switched on is fetched at once, and one switched off is left alone.
        stationTask?.cancel(); stationTask = nil
        if pollTask != nil { startStationLoop() }
        updateStation(now: Date())
    }

    func startStationLoop() {
        // Tests and previews stay off the network unless they bring their own source.
        guard stationTask == nil, !isDemo, settings.watchesAnyStation, persists || injectedOrbits != nil else { return }
        stationTask = Task { [weak self] in await self?.stationLoop() }
    }

    private func stationLoop() async {
        let provider = injectedOrbits ?? CelesTrakProvider()
        if persists {
            for object in SpaceObject.allCases where settings.watches(object) && stationElementSets[object] == nil {
                guard let cached = StationElementsCache.load(object) else { continue }
                stationElementSets[object] = cached.elements
                stationOrbits[object] = SatelliteOrbit(cached.elements, standardMagnitude: object.standardMagnitude)
                stationUpdatedAt[object] = cached.fetchedAt
            }
            updateStation(now: Date())
        }
        var failures = 0
        while !Task.isCancelled {
            var anyFailed = false
            for object in SpaceObject.allCases where settings.watches(object) {
                guard stationUpdatedAt[object].map({ Date().timeIntervalSince($0) > stationRefreshInterval }) ?? true else { continue }
                do {
                    let elements = try await provider.elements(for: object)
                    if Task.isCancelled { return }
                    guard elements.catalogNumber == object.catalogNumber else { throw FeedError.malformed }
                    let fetched = Date()
                    useStationElements(elements, at: fetched)
                    if persists { StationElementsCache.save(elements, fetchedAt: fetched, for: object) }
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    anyFailed = true
                    stationFetchErrors[object] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                // The orbit host is a free service: leave a pause between one station's request and the next.
                if injectedOrbits == nil { try? await Task.sleep(for: .seconds(1)) }
            }
            failures = anyFailed ? failures + 1 : 0
            // Orbits change a few times a day, so there is no hurry; after a failure, try again sooner but not hammering.
            let wait = failures == 0 ? 15 * 60 : min(3600, 300 * pow(2, Double(min(failures, 4))))
            try? await Task.sleep(for: .seconds(wait))
        }
    }
}
