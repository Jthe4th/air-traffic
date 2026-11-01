import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import OverheadKit
import OverheadUI

// Renders the TV layout to PNG so the design can be reviewed without a tvOS simulator.
//   design-preview --icons <dir>                  app icon and Top Shelf images for the asset catalog
//   design-preview --chimes <dir>                 the Space Station sounds as WAV files
//   design-preview <output-dir> [scene ...]      scenes: busy, quiet, welcome, ground, nophoto, photoloading, alert, flyby, ambient (append 2 or 3 for later telemetry pages),
//                                                 issupcoming, issimminent, issnow, issover, issquiet (the Space Station, from its real orbit)
//                                                 routechecking, routeunconfirmed, routenone (the route line when there is no route)
//                                                 tiangongnow, tiangongover (Tiangong, from its real orbit)
// Needs network access for map tiles on first run (cached afterwards by URLCache).

@MainActor
func makePhoto(at url: URL) {
    let w = 840, h = 460
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    let colors = [CGColor(red: 0.27, green: 0.52, blue: 0.86, alpha: 1), CGColor(red: 0.78, green: 0.86, blue: 0.95, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: 0, y: 0), options: [])
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: 120, y: 120, width: 560, height: 70))        // stand-in fuselage
    ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1))
    ctx.fill(CGRect(x: 620, y: 150, width: 90, height: 150))                     // stand-in tail
    guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

/// The Space Station's orbit as published by CelesTrak on 2026-11-01. The scenes below are drawn from it, so they show a real pass.
let previewStation = OrbitalElements(
    name: "ISS (ZARYA)",
    line1: "1 25544U 98067A   26305.40213002  .00006924  00000+0  13304-3 0  9992",
    line2: "2 25544  51.6333 341.0833 0007085 335.3698  24.6951 15.49140766593021")!

/// Tiangong's orbit as published by CelesTrak on 2026-11-01.
let previewTiangong = OrbitalElements(
    name: "CSS (TIANHE)",
    line1: "1 48274U 21035A   26305.38936679  .00008747  00000+0  10390-3 0  9994",
    line2: "2 48274  41.4675 208.4160 0004086 243.9286 116.1132 15.61278896314597")!

/// The station a scene is about, and its orbit.
func stationOrbitElements(_ scene: String) -> OrbitalElements { scene.hasPrefix("tiangong") ? previewTiangong : previewStation }

/// Where the station is a quarter of an hour after its orbit was measured, so "overhead" scenes have it near the preview home.
func stationOverheadDate(_ elements: OrbitalElements) -> Date { elements.epoch.addingTimeInterval(3600) }

/// The moment a Space Station scene is drawn at: relative to a real visible pass over the preview home.
func stationSceneDate(_ scene: String) -> Date {
    let elements = stationOrbitElements(scene)
    guard let orbit = SatelliteOrbit(elements) else { return elements.epoch }
    if scene == "issover" || scene == "tiangongover" { return stationOverheadDate(elements) }
    let from = elements.epoch
    guard let pass = PassFinder.visiblePasses(of: orbit, from: DemoFeed.defaultHome, between: from, and: from.addingTimeInterval(10 * 86_400)).first(where: { $0.brightestMagnitude <= -1 }) else { return from }
    switch scene {
    case "issupcoming": return pass.start.date.addingTimeInterval(-14 * 60)
    case "issimminent": return pass.start.date.addingTimeInterval(-70)
    case "issquiet": return pass.start.date.addingTimeInterval(-3 * 3600)
    default: return pass.start.date.addingTimeInterval(95)        // issnow: under way
    }
}

@MainActor
func makeEngine(scene: String, photoURL: URL, at date: Date) async -> TrackingEngine {
    var settings = AppSettings()
    settings.demoMode = scene != "welcome"
    if scene == "welcome" { settings.home = nil }
    if scene == "zoomin" { settings.mapRadiusNM = 5 / Geo.milesPerNM }
    if scene == "zoomout" || scene == "crowded" { settings.mapRadiusNM = 60 / Geo.milesPerNM }
    if scene.hasPrefix("iss") || scene.hasPrefix("tiangong") {
        // The station feature is off in demo mode, so these scenes use a real (but fixed) home.
        settings.demoMode = false
        settings.home = DemoFeed.defaultHome
        if scene == "issover" || scene == "tiangongover", let here = SatelliteOrbit(stationOrbitElements(scene))?.sample(at: date) {
            settings.home = Geo.destination(from: here.subpoint, bearing: 250, distanceNM: 6)
        }
    }
    if scene == "flyby" {
        // Watching TV while facing south-southwest; the viewer calls the right-hand side "Side door".
        settings.viewerHeadingDeg = 202.5
        settings.directionNames.right = "Side door"
    }
    // "photoloading": the photo's address is known but the image hasn't arrived (this file never exists).
    let imageURL = scene == "photoloading" ? URL(fileURLWithPath: "/nonexistent/photo.png") : photoURL
    let photo = AircraftPhoto(imageURL: imageURL, pageURL: nil, photographer: "Alex Example")
    struct Photos: PhotoProviding {
        let photo: AircraftPhoto
        func photo(for aircraft: Aircraft) async -> AircraftPhoto? { aircraft.hex == "a5c8b9" ? nil : photo }
    }
    /// What the route lookup says in the route scenes: nil never answers, so the card stays on "Checking route…".
    struct FixedRoutes: RouteProviding {
        let result: RouteLookup?
        func lookup(for aircraft: Aircraft) async -> RouteLookup {
            if let result { return result }
            try? await Task.sleep(for: .seconds(3600))
            return .failed
        }
    }
    let routes: FixedRoutes? = switch scene {
    case "routechecking": FixedRoutes(result: nil)
    case "routeunconfirmed": FixedRoutes(result: .unconfirmed)
    case "routenone": FixedRoutes(result: .unavailable)
    default: nil
    }
    let engine = TrackingEngine(settings: settings, persists: false, routes: routes, photos: Photos(photo: photo))
    var flights = DemoFeed.snapshot(center: engine.home, radiusNM: DemoFeed.loopRadiusNM, at: date)
    if scene == "crowded" { flights += crowd(around: engine.home, count: 110, at: date) }
    if scene == "quiet" || scene == "issquiet" { flights = [] }
    if scene.hasPrefix("iss") || scene.hasPrefix("tiangong") { engine.useStationElements(stationOrbitElements(scene), at: date) }
    if scene == "ground" {
        flights = [Aircraft(hex: "g1", callsign: "UAL1348", registration: "N77295", typeCode: "B739", position: engine.home,
                            positionTime: date, onGround: true, groundSpeedKt: 12, trackDeg: 90, wakeClass: .large)]
    }
    if scene == "flyby" {
        // 3 NM west and 1.2 NM north of home, flying east at 300 kt: passes 1.2 NM to the north in about 36 seconds.
        let p = Geo.destination(from: engine.home, bearing: Geo.normalize(atan2(-3, 1.2) * 180 / .pi), distanceNM: hypot(-3, 1.2))
        flights.append(Aircraft(hex: "f1b001", callsign: "UAL1348", registration: "N77295", typeCode: "B739", position: p, positionTime: date,
                                barometricAltitudeFt: 4_500, groundSpeedKt: 300, trackDeg: 90, verticalRateFpm: -700, wakeClass: .large))
    }
    if scene == "alert" {
        // A squawk of 7700 must hold for a few seconds before it is shown, so report it twice.
        flights[0].squawk = "7700"
        engine.ingest(flights, at: date.addingTimeInterval(-20))
    }
    engine.ingest(flights, at: date)
    if scene == "busy" || scene == "nophoto" || scene == "photoloading" || scene.hasPrefix("route") { engine.pin(scene == "nophoto" ? "a5c8b9" : "a8b001", now: date) }
    try? await Task.sleep(for: .milliseconds(400))   // let route/photo lookups land
    if let id = engine.featuredID, let t = engine.aircraft.first(where: { $0.id == id }), let url = t.photo?.imageURL {
        await ImageStore.shared.load(url)
    }
    return engine
}

/// A deterministic swarm of fictional aircraft, for checking how a busy sky reads when zoomed out.
func crowd(around home: GeoPoint, count: Int, at date: Date) -> [Aircraft] {
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func next() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 33) / Double(1 << 31)
    }
    let airlines = ["UAL", "DAL", "AAL", "SWA", "JBU", "ASA", "FDX", "UPS", "SKW", "RPA", "ENY"]
    let types = ["B738", "A320", "A321", "B739", "E75L", "CRJ9", "B38M", "A20N", "B752", "C172"]
    return (0..<count).map { i in
        let position = Geo.destination(from: home, bearing: next() * 360, distanceNM: 4 + next() * 44)
        let alt = Int(1_500 + next() * 36_000)
        let isGA = i % 11 == 0
        return Aircraft(
            hex: String(format: "c%05x", i), callsign: isGA ? "N\(100 + i)AB" : "\(airlines[i % airlines.count])\(100 + Int(next() * 8_900))",
            typeCode: isGA ? "C172" : types[i % types.count], position: position, positionTime: date,
            barometricAltitudeFt: isGA ? Int(1_000 + next() * 3_000) : alt, groundSpeedKt: isGA ? 105 : 220 + next() * 260,
            trackDeg: next() * 360, verticalRateFpm: Int((next() - 0.5) * 3_000), wakeClass: isGA ? .light : .large)
    }
}

@MainActor
func render(_ view: some View, to url: URL) {
    let renderer = ImageRenderer(content: view.frame(width: 1920, height: 1080))
    renderer.scale = 1
    renderer.isOpaque = true
    guard let image = renderer.cgImage, let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("render failed: \(url.lastPathComponent)"); return
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

/// Renders every image the tvOS asset catalog needs. `--icons <dir>` writes them; scripts/ builds the catalog from them.
@MainActor
func renderIcons(to dir: URL) {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    func write(_ view: some View, size: CGSize, scale: CGFloat, opaque: Bool, name: String) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.isOpaque = opaque
        guard let image = renderer.cgImage,
              let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            print("failed: \(name)"); return
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        print("\(name).png  \(image.width)x\(image.height)")
    }
    let layers: [(String, AppIconArtwork.Layer)] = [("back", .back), ("middle", .middle), ("front", .front)]
    for (name, layer) in layers {
        write(AppIconArtwork(layer: layer), size: CGSize(width: 1280, height: 768), scale: 1, opaque: layer == .back, name: "appstore-\(name)")
        for scale in [1, 2] {
            write(AppIconArtwork(layer: layer), size: CGSize(width: 400, height: 240), scale: CGFloat(scale), opaque: layer == .back, name: "home-\(name)@\(scale)x")
        }
    }
    write(AppIconArtwork(), size: CGSize(width: 1280, height: 768), scale: 1, opaque: true, name: "preview-icon-flat")   // for eyeballing; not in the catalog
    for scale in [1, 2] {
        write(AppIconArtwork(format: .banner), size: CGSize(width: 1920, height: 720), scale: CGFloat(scale), opaque: true, name: "topshelf@\(scale)x")
        write(AppIconArtwork(format: .banner), size: CGSize(width: 2320, height: 720), scale: CGFloat(scale), opaque: true, name: "topshelfwide@\(scale)x")
    }
}

@MainActor
func run() async {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "--icons" {
        _ = NSApplication.shared
        renderIcons(to: URL(fileURLWithPath: args.count > 1 ? args[1] : "icons"))
        return
    }
    if args.first == "--chimes" {
        let dir = URL(fileURLWithPath: args.count > 1 ? args[1] : "chimes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, kind) in [("heads-up", StationChime.Kind.headsUp), ("rising", .rising)] {
            let url = dir.appendingPathComponent("\(name).wav")
            try? ChimeTone.wav(for: kind).write(to: url)
            print("wrote \(url.path)")
        }
        return
    }
    let out = URL(fileURLWithPath: args.first ?? ".")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let scenes = args.count > 1 ? Array(args.dropFirst()) : ["busy"]
    let photoURL = out.appendingPathComponent("stand-in-photo.png")
    makePhoto(at: photoURL)
    _ = NSApplication.shared

    // A fixed moment so every render is reproducible. Scenes ending in 2 / 3 show the later telemetry pages.
    let date = Date(timeIntervalSinceReferenceDate: 815_080_980)   // a multiple of 42 s, so the facts panel starts on page 0
    for scene in scenes {
        let name = scene.hasSuffix("2") || scene.hasSuffix("3") ? String(scene.dropLast()) : scene
        let pageOffset = scene.hasSuffix("2") ? 7.0 : scene.hasSuffix("3") ? 14.0 : 0.0
        let date = name.hasPrefix("iss") || name.hasPrefix("tiangong") ? stationSceneDate(name) : date
        let engine = await makeEngine(scene: name, photoURL: photoURL, at: date)
        let camera = TVDashboardView.camera(for: engine)
        await ImageStore.shared.prefetch(camera.tiles.map { MapStyle.url(for: $0) })
        let ambient = Ambient()
        if name == "ambient" { ambient.isFrozen = true; ambient.controlsHidden = true; ambient.isNight = true; ambient.shift = CGSize(width: 5, height: -4) }
        else { ambient.isFrozen = true }
        render(TVDashboardView(engine: engine, ambient: ambient).fixedClock(date.addingTimeInterval(pageOffset)), to: out.appendingPathComponent("\(scene).png"))
    }
}

await run()
