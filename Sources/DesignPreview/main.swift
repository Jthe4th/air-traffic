import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import OverheadKit
import OverheadUI

// Renders the TV layout to PNG so the design can be reviewed without a tvOS simulator.
//   design-preview <output-dir> [scene ...]      scenes: busy, quiet, welcome, ground, nophoto, photoloading, alert (append 2 or 3 for later telemetry pages)
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

@MainActor
func makeEngine(scene: String, photoURL: URL, at date: Date) async -> TrackingEngine {
    var settings = AppSettings()
    settings.demoMode = scene != "welcome"
    if scene == "welcome" { settings.home = nil }
    if scene == "zoomin" { settings.mapRadiusNM = 5 / Geo.milesPerNM }
    if scene == "zoomout" || scene == "crowded" { settings.mapRadiusNM = 60 / Geo.milesPerNM }
    // "photoloading": the photo's address is known but the image hasn't arrived (this file never exists).
    let imageURL = scene == "photoloading" ? URL(fileURLWithPath: "/nonexistent/photo.png") : photoURL
    let photo = AircraftPhoto(imageURL: imageURL, pageURL: nil, photographer: "Alex Example")
    struct Photos: PhotoProviding {
        let photo: AircraftPhoto
        func photo(for aircraft: Aircraft) async -> AircraftPhoto? { aircraft.hex == "a5c8b9" ? nil : photo }
    }
    let engine = TrackingEngine(settings: settings, persists: false, photos: Photos(photo: photo))
    var flights = DemoFeed.snapshot(center: engine.home, radiusNM: DemoFeed.loopRadiusNM, at: date)
    if scene == "crowded" { flights += crowd(around: engine.home, count: 110, at: date) }
    if scene == "quiet" { flights = [] }
    if scene == "ground" {
        flights = [Aircraft(hex: "g1", callsign: "UAL1348", registration: "N77295", typeCode: "B739", position: engine.home,
                            positionTime: date, onGround: true, groundSpeedKt: 12, trackDeg: 90, wakeClass: .large)]
    }
    if scene == "alert" {
        // A squawk of 7700 must hold for a few seconds before it is shown, so report it twice.
        flights[0].squawk = "7700"
        engine.ingest(flights, at: date.addingTimeInterval(-20))
    }
    engine.ingest(flights, at: date)
    if scene == "busy" || scene == "nophoto" || scene == "photoloading" { engine.pin(scene == "nophoto" ? "a5c8b9" : "a8b001", now: date) }
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

@MainActor
func run() async {
    let args = Array(CommandLine.arguments.dropFirst())
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
        let engine = await makeEngine(scene: name, photoURL: photoURL, at: date)
        let camera = TVDashboardView.camera(for: engine)
        await ImageStore.shared.prefetch(camera.tiles.map { MapStyle.url(for: $0) })
        render(TVDashboardView(engine: engine).fixedClock(date.addingTimeInterval(pageOffset)), to: out.appendingPathComponent("\(scene).png"))
    }
}

await run()
