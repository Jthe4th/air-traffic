import SwiftUI
import OverheadKit

/// Full-bleed map: raster tiles underneath, a Canvas of rings, trails and aircraft on top.
struct MapStage: View {
    let engine: TrackingEngine
    let camera: MapCamera

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.ink
            TileLayer(camera: camera)
            MapOverlay(engine: engine, camera: camera)
            Text(MapStyle.attribution)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.38))
                .position(x: camera.size.width - 190, y: camera.size.height - 26)
        }
        .frame(width: camera.size.width, height: camera.size.height)
        .clipped()
    }
}

struct TileLayer: View {
    let camera: MapCamera
    /// Tile level from before the last zoom. Its cached tiles stay under the new ones until those load.
    @State private var underlayLevel: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let level = underlayLevel, level != camera.tileZoomLevel {
                ForEach(underlayCamera(level).tiles) { tile in
                    CachedImage(url: MapStyle.url(for: tile), autoload: false)
                        .frame(width: tile.size + 1, height: tile.size + 1)
                        .position(x: tile.origin.x + tile.size / 2, y: tile.origin.y + tile.size / 2)
                }
            }
            ForEach(camera.tiles) { tile in
                CachedImage(url: MapStyle.url(for: tile))
                    .frame(width: tile.size + 1, height: tile.size + 1)
                    .position(x: tile.origin.x + tile.size / 2, y: tile.origin.y + tile.size / 2)
            }
        }
        .onChange(of: camera.tileZoomLevel) { old, _ in underlayLevel = old }
        .task(id: underlayLevel) {
            guard underlayLevel != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            underlayLevel = nil
        }
        .frame(width: camera.size.width, height: camera.size.height, alignment: .topLeading)
        .modifier(DarkTileFilter(enabled: MapStyle.appliesDarkFilter))
    }
}

/// Turns light OpenStreetMap tiles into a dark map: invert, rotate hues back, and mute.
private struct DarkTileFilter: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.colorInvert().hueRotation(.degrees(180)).saturation(0.5).contrast(0.9).brightness(-0.08)
        } else {
            content
        }
    }
}

private extension TileLayer {
    func underlayCamera(_ level: Int) -> MapCamera {
        var c = camera
        c.tileZoomBias = level - Int(camera.zoom.rounded(.down))
        return c
    }
}

struct MapOverlay: View {
    let engine: TrackingEngine
    let camera: MapCamera
    @Environment(\.fixedNow) private var fixedNow

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            let painter = MapPainter(
                camera: camera, now: fixedNow ?? timeline.date, home: engine.home, settings: engine.settings,
                items: engine.aircraft, featuredID: engine.featuredID)
            Canvas { context, _ in painter.paint(&context) }
        }
        .allowsHitTesting(false)
    }
}

struct MapPainter {
    let camera: MapCamera
    let now: Date
    let home: GeoPoint
    let settings: AppSettings
    let items: [TrackedAircraft]
    let featuredID: String?

    /// Markers shrink as the view widens so a crowded sky stays legible.
    private var sizeFactor: CGFloat { CGFloat(min(1, max(0.62, 21.7 / settings.mapRadiusNM))) }
    /// With many aircraft, skip per-marker glow filters to keep the frame rate up on older Apple TVs.
    private var cheapDrawing: Bool { items.count > 40 }

    func paint(_ ctx: inout GraphicsContext) {
        var taken = paintRings(&ctx)

        let farToNear = Array(items.reversed())
        let drawOrder = farToNear.filter { $0.id != featuredID } + farToNear.filter { $0.id == featuredID }
        if settings.showTrails { for t in drawOrder { paintTrail(&ctx, t) } }
        if let f = items.first(where: { $0.id == featuredID }) { paintProjection(&ctx, f) }

        for t in drawOrder { taken += paintGlyph(&ctx, t) }
        paintHome(&ctx)

        // Labels last, featured first then nearest first, each dodging whatever is already placed.
        let priority = items.filter { $0.id == featuredID } + items.filter { $0.id != featuredID }
        var labelled = 0
        for t in priority {
            let featured = t.id == featuredID
            let overhead = Geo.distanceNM(home, t.aircraft.position(at: now)) <= settings.alertRadiusNM
            if !featured && !overhead && labelled >= 14 { continue }   // a label budget keeps wide views readable
            if paintLabel(&ctx, t, taken: &taken) { labelled += 1 }
        }
    }

    // MARK: Rings

    private var unitFactor: (perNM: Double, name: String) {
        switch settings.units {
        case .imperial: (Geo.milesPerNM, "mi")
        case .metric: (Geo.kmPerNM, "km")
        case .aviation: (1, "NM")
        }
    }

    /// Draws the rings and returns the rectangles their labels occupy, so aircraft labels can avoid them.
    private func paintRings(_ ctx: inout GraphicsContext) -> [CGRect] {
        var reserved: [CGRect] = []
        let c = camera.point(for: home)
        let ppn = camera.pointsPerNM
        let outer = settings.mapRadiusNM * ppn

        let alertR = settings.alertRadiusNM * ppn
        let zone = Path(ellipseIn: CGRect(x: c.x - alertR, y: c.y - alertR, width: alertR * 2, height: alertR * 2))
        ctx.fill(zone, with: .color(Theme.accent.opacity(0.055)))
        ctx.stroke(zone, with: .color(Theme.accent.opacity(0.6)), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
        let zoneLabel = CGPoint(x: c.x, y: c.y - alertR - 15)
        ctx.draw(Text("OVERHEAD").font(.system(size: 17, weight: .bold)).foregroundColor(Theme.accent.opacity(0.85)), at: zoneLabel, anchor: .center)
        reserved.append(CGRect(x: zoneLabel.x - 50, y: zoneLabel.y - 12, width: 100, height: 24))

        let (perNM, unit) = unitFactor
        let maxUnits = settings.mapRadiusNM * perNM
        let steps: [Double] = [1, 2, 5, 10, 20, 25, 50, 100]
        let step = steps.last { $0 <= maxUnits / 3 + 0.01 } ?? 1
        let angle = 38.0 * .pi / 180

        func ringLabel(_ text: String, radius r: CGFloat) {
            let at = CGPoint(x: c.x + r * sin(angle) + 8, y: c.y - r * cos(angle))
            ctx.draw(Text(text).font(.system(size: 19, weight: .semibold)).foregroundColor(.white.opacity(0.5)), at: at, anchor: .leading)
            reserved.append(CGRect(x: at.x - 4, y: at.y - 12, width: CGFloat(text.count) * 11 + 10, height: 24))
        }

        var u = step
        var lastRing = 0.0
        while u <= maxUnits + step * 0.05 {
            let r = u / perNM * ppn
            let isOuter = abs(r - outer) < 2
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(.white.opacity(isOuter ? 0.24 : 0.12)),
                       style: StrokeStyle(lineWidth: isOuter ? 2 : 1.5, dash: isOuter ? [] : [3, 9]))
            ringLabel("\(Int(u)) \(unit)", radius: r)
            lastRing = u
            u += step
        }
        if maxUnits - lastRing > step * 0.25 {
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)),
                       with: .color(.white.opacity(0.24)), lineWidth: 2)
            ringLabel("\(Int(maxUnits.rounded())) \(unit)", radius: outer)
        }

        for (i, letter) in ["N", "E", "S", "W"].enumerated() {
            let a = Double(i) * .pi / 2
            ctx.draw(Text(letter).font(.system(size: 23, weight: .bold)).foregroundColor(.white.opacity(i == 0 ? 0.75 : 0.38)),
                     at: CGPoint(x: c.x + (outer + 30) * sin(a), y: c.y - (outer + 30) * cos(a)), anchor: .center)
        }
        return reserved
    }

    private func paintHome(_ ctx: inout GraphicsContext) {
        let c = camera.point(for: home)
        let phase = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
        let pr = 14 + 26 * phase
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)),
                   with: .color(.white.opacity(0.5 * (1 - phase))), lineWidth: 2)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 15, y: c.y - 15, width: 30, height: 30)), with: .color(.black.opacity(0.55)))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 15, y: c.y - 15, width: 30, height: 30)), with: .color(.white.opacity(0.9)), lineWidth: 2.5)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.white))
    }

    // MARK: Aircraft

    private func color(for t: TrackedAircraft) -> Color {
        Theme.altitudeColor(t.aircraft.altitudeFt(at: now), onGround: t.aircraft.onGround)
    }

    private func visible(_ p: CGPoint, margin: CGFloat = 80) -> Bool {
        p.x > -margin && p.y > -margin && p.x < camera.size.width + margin && p.y < camera.size.height + margin
    }

    private func paintTrail(_ ctx: inout GraphicsContext, _ t: TrackedAircraft) {
        guard t.trail.count > 1, visible(camera.point(for: t.aircraft.position(at: now)), margin: 420) else { return }
        var points = t.trail.map { camera.point(for: $0.position) }
        points.append(camera.point(for: t.aircraft.position(at: now)))
        let tint = color(for: t)
        let featured = t.id == featuredID
        let n = points.count
        let cuts = [0, n * 5 / 10, n * 8 / 10, n - 1]
        let alphas: [Double] = featured ? [0.14, 0.32, 0.65] : [0.07, 0.16, 0.34]
        for k in 0..<3 where cuts[k + 1] > cuts[k] {
            var path = Path()
            path.move(to: points[cuts[k]])
            for i in (cuts[k] + 1)...cuts[k + 1] { path.addLine(to: points[i]) }
            ctx.stroke(path, with: .color(tint.opacity(alphas[k])), style: StrokeStyle(lineWidth: featured ? 3.5 : 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func paintProjection(_ ctx: inout GraphicsContext, _ t: TrackedAircraft) {
        let a = t.aircraft
        guard !a.onGround, let track = a.trackDeg, let gs = a.groundSpeedKt, gs > 40 else { return }
        let start = a.position(at: now)
        let tint = color(for: t)
        let end = Geo.destination(from: start, bearing: track, distanceNM: gs * 6 / 60)
        var path = Path()
        path.move(to: camera.point(for: start))
        path.addLine(to: camera.point(for: end))
        ctx.stroke(path, with: .color(tint.opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 11]))
        for minute in 1...6 {
            let p = camera.point(for: Geo.destination(from: start, bearing: track, distanceNM: gs * Double(minute) / 60))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(tint.opacity(0.9)))
            if minute % 2 == 0 {
                ctx.draw(Text("\(minute)\u{2032}").font(.system(size: 17, weight: .semibold)).foregroundColor(tint.opacity(0.85)),
                         at: CGPoint(x: p.x + 11, y: p.y - 9), anchor: .leading)
            }
        }
        let off = Geo.offsetNM(from: home, to: start)
        if let cpa = Geo.closestApproach(east: off.east, north: off.north, trackDeg: track, speedKt: gs), cpa.seconds > 0, cpa.seconds < 900 {
            let p = camera.point(for: Geo.destination(from: start, bearing: track, distanceNM: gs * cpa.seconds / 3600))
            let c = camera.point(for: home)
            var link = Path(); link.move(to: c); link.addLine(to: p)
            ctx.stroke(link, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), with: .color(.white.opacity(0.8)), lineWidth: 2)
        }
    }

    /// Draws the aircraft marker; returns the rectangle it occupies.
    private func paintGlyph(_ ctx: inout GraphicsContext, _ t: TrackedAircraft) -> [CGRect] {
        let a = t.aircraft
        let pos = camera.point(for: a.position(at: now))
        guard visible(pos) else { return [] }
        let featured = t.id == featuredID
        let tint = color(for: t)
        let size = glyphSize(a, featured: featured)
        let glyph = Silhouettes.path(AircraftTypes.silhouette(for: a), center: pos, size: size, headingDeg: a.trackDeg ?? a.trueHeadingDeg ?? 0)

        if featured {
            let phase = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
            let base = size * 0.95
            let r = base + 22 * phase
            ctx.stroke(Path(ellipseIn: CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)),
                       with: .color(Theme.accent.opacity(0.65 * (1 - phase))), lineWidth: 3)
            let disc = Path(ellipseIn: CGRect(x: pos.x - base, y: pos.y - base, width: base * 2, height: base * 2))
            ctx.fill(disc, with: .color(.black.opacity(0.35)))
            ctx.stroke(disc, with: .color(Theme.accent.opacity(0.9)), lineWidth: 2.5)
        }
        if cheapDrawing && !featured {
            ctx.stroke(glyph, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            ctx.fill(glyph, with: .color(tint))
        } else {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: tint.opacity(featured ? 0.6 : 0.35), radius: featured ? 14 : 8))
                layer.stroke(glyph, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
                layer.fill(glyph, with: .color(tint))
            }
        }
        let half = size * (featured ? 1.0 : 0.6)
        return [CGRect(x: pos.x - half, y: pos.y - half, width: half * 2, height: half * 2)]
    }

    private func glyphSize(_ a: Aircraft, featured: Bool) -> CGFloat {
        Silhouettes.size(for: a, featured: featured) * (featured ? max(sizeFactor, 0.85) : sizeFactor)
    }

    @discardableResult
    private func paintLabel(_ ctx: inout GraphicsContext, _ t: TrackedAircraft, taken: inout [CGRect]) -> Bool {
        let a = t.aircraft
        let pos = camera.point(for: a.position(at: now))
        guard visible(pos, margin: 0) else { return false }
        let featured = t.id == featuredID
        let tint = color(for: t)
        let name = t.flightNumber ?? a.title
        let alt: String = {
            if a.onGround { return "On ground" }
            guard let ft = a.altitudeFt(at: now) else { return "" }
            return flightLevelText(altitudeFt: Int(ft)) ?? settings.units.altitude(ft: ft).text
        }()

        let nameSize: CGFloat = featured ? 27 : 20, altSize: CGFloat = featured ? 21 : 17
        let w = max(CGFloat(name.count) * nameSize * 0.64, CGFloat(alt.count) * altSize * 0.6)
        let h = nameSize + altSize + 4
        let glyphHalf = glyphSize(a, featured: featured) * (featured ? 1.0 : 0.62)
        let gap = glyphHalf + 8

        // right, left, below, above
        let candidates: [(origin: CGPoint, alignRight: Bool)] = [
            (CGPoint(x: pos.x + gap, y: pos.y - h / 2), false),
            (CGPoint(x: pos.x - gap - w, y: pos.y - h / 2), true),
            (CGPoint(x: pos.x - w / 2, y: pos.y + gap), false),
            (CGPoint(x: pos.x - w / 2, y: pos.y - gap - h), false),
        ]
        let bounds = CGRect(origin: .zero, size: camera.size).insetBy(dx: 10, dy: 10)
        let chosen = candidates.first { c in
            let r = CGRect(origin: c.origin, size: CGSize(width: w, height: h))
            return bounds.contains(r) && !taken.contains { $0.intersects(r.insetBy(dx: -4, dy: -3)) }
        }
        guard let place = chosen ?? (featured ? candidates[0] : nil) else { return false }
        taken.append(CGRect(origin: place.origin, size: CGSize(width: w, height: h)))

        let x = place.alignRight ? place.origin.x + w : place.origin.x
        let anchor: UnitPoint = place.alignRight ? .topTrailing : .topLeading
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.9), radius: 4, x: 0, y: 1))
            layer.draw(Text(name).font(.system(size: nameSize, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(featured ? 1 : 0.9)),
                       at: CGPoint(x: x, y: place.origin.y), anchor: anchor)
            layer.draw(Text(alt).font(.system(size: altSize, weight: .semibold, design: .rounded)).foregroundColor(tint.opacity(0.96)),
                       at: CGPoint(x: x, y: place.origin.y + nameSize + 2), anchor: anchor)
        }
        return true
    }
}
