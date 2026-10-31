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
        }
    }

    @ObservationIgnored private var feed: any AircraftFeed = DemoFeed()
    @ObservationIgnored private var routes: any RouteProviding = DemoRouteProvider()
    @ObservationIgnored private var photos: any PhotoProviding = NoPhotos()
    @ObservationIgnored private let liveRoutes = StandingDataRouteProvider()
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
    /// A card is dropped this long after its aircraft stops qualifying, and never stays longer than `flybyMaxShow`.
    @ObservationIgnored let flybyLinger: TimeInterval = 6
    @ObservationIgnored let flybyMaxShow: TimeInterval = 90
    @ObservationIgnored let flybyCooldown: TimeInterval = 10 * 60
    /// An emergency squawk must hold this long before it is shown; pilots dialling a code pass through 7700 briefly.
    @ObservationIgnored var emergencyConfirmAfter: TimeInterval = 12
    @ObservationIgnored private let injectedRoutes: (any RouteProviding)?
    @ObservationIgnored private let injectedPhotos: (any PhotoProviding)?

    public init(settings: AppSettings? = nil, persists: Bool = true,
                routes: (any RouteProviding)? = nil, photos: (any PhotoProviding)? = nil) {
        self.persists = persists
        self.injectedRoutes = routes
        self.injectedPhotos = photos
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
    }

    public func stop() {
        pollTask?.cancel(); tickTask?.cancel()
        pollTask = nil; tickTask = nil
    }

    private func restart() {
        stop()
        aircraft = []
        featuredID = nil
        insideIDs = []
        flybyActive = [:]
        flybyDone = [:]
        altimeter = nil
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

            if aircraft[i].route == nil, now.timeIntervalSince(aircraft[i].routeCheckedAt ?? .distantPast) > 20 {
                aircraft[i].routeCheckedAt = now
                let provider = routes
                Task { [weak self] in
                    let route = await provider.route(for: snapshot)
                    guard let route else { return }
                    self?.update(id) { $0.route = route }
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
