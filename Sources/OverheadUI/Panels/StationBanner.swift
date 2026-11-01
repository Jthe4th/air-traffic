import SwiftUI
import OverheadKit

/// Announces a visible pass of the Space Station: when, where to look, and how bright. A slim reminder while the pass is far
/// off, then the full card with a sky chart for the last two minutes and the pass itself.
struct StationBanner: View {
    let card: StationPassCard
    var compact = false

    var body: some View {
        Group {
            if compact { compactBody } else { fullBody }
        }
        .frame(width: 870, alignment: .leading)     // stops short of the zoom buttons at the right edge
        .glassCard(radius: compact ? 38 : 44, tint: Theme.station.opacity(0.13))
    }

    private var fullBody: some View {
        HStack(spacing: 32) {
            PassDial(card: card).frame(width: 196, height: 196)

            VStack(alignment: .leading, spacing: 8) {
                Text(card.headline).labelStyle(Theme.station)
                Text(card.object.shortName).font(Theme.serif(54, weight: .semibold)).foregroundStyle(Theme.text)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(card.moments, id: \.label) { moment in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(moment.label).labelStyle(Theme.secondary).frame(width: 118, alignment: .leading)
                            Text(moment.time).font(Theme.number(26, weight: .bold)).foregroundStyle(Theme.text)
                            Text(moment.place).font(Theme.body(25)).foregroundStyle(Theme.text.opacity(0.92)).lineLimit(2).minimumScaleFactor(0.8)
                        }
                    }
                }
                .padding(.top, 2)
                Text("\(card.brightnessText) · visible \(card.durationText) · reaches \(card.peakDegrees)° up")
                    .font(Theme.number(24, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36).padding(.vertical, 24)
    }

    private var compactBody: some View {
        HStack(spacing: 20) {
            AirlineBadge(size: 64, spacecraft: card.object.silhouette)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.headline).labelStyle(Theme.station)
                Text("\(card.object.shortName) at \(card.moments.first?.time ?? "")")
                    .font(Theme.body(32, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(card.route) · \(card.brightnessText) · reaches \(card.peakDegrees)° up")
                    .font(Theme.body(24)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
    }
}

/// The sky from the back garden: straight up is the middle, the horizon is the outer ring, north is at the top and east to the
/// right, as on the map. The dashed line is the pass; once it starts, the station moves along it.
private struct PassDial: View {
    let card: StationPassCard

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 28
            func point(_ az: Double, _ el: Double) -> CGPoint {
                let radius = r * (90 - max(0, min(90, el))) / 90
                let a = az * .pi / 180
                return CGPoint(x: c.x + radius * sin(a), y: c.y - radius * cos(a))
            }

            for (i, fraction) in [1.0, 2.0 / 3, 1.0 / 3].enumerated() {
                let ring = Path(ellipseIn: CGRect(x: c.x - r * fraction, y: c.y - r * fraction, width: r * 2 * fraction, height: r * 2 * fraction))
                ctx.stroke(ring, with: .color(.white.opacity(i == 0 ? 0.36 : 0.14)), lineWidth: i == 0 ? 2.5 : 1.2)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
            cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
            ctx.stroke(cross, with: .color(.white.opacity(0.10)), lineWidth: 1)
            for (i, letter) in ["N", "E", "S", "W"].enumerated() {
                let a = Double(i) * .pi / 2
                ctx.draw(Text(letter).font(.system(size: 18, weight: .bold)).foregroundColor(.white.opacity(i == 0 ? 0.85 : 0.5)),
                         at: CGPoint(x: c.x + (r + 17) * sin(a), y: c.y - (r + 17) * cos(a)), anchor: .center)
            }

            let pass = card.pass
            let points = pass.path.map { point($0.azimuthDeg, $0.elevationDeg) }
            guard points.count > 1 else { return }
            var route = Path()
            route.move(to: points[0])
            for p in points.dropFirst() { route.addLine(to: p) }
            ctx.stroke(route, with: .color(Theme.station.opacity(0.5)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [2, 8]))

            // Where it appears (a ring) and where it ends (a dot).
            let first = points[0], last = points[points.count - 1]
            ctx.stroke(Path(ellipseIn: CGRect(x: first.x - 8, y: first.y - 8, width: 16, height: 16)), with: .color(Theme.station), lineWidth: 3)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)), with: .color(Theme.station.opacity(0.8)))

            if card.phase == .underway || card.phase == .ended, let here = position(at: card.asOf, in: pass.path) {
                let p = point(here.az, here.el)
                let ahead = position(at: card.asOf.addingTimeInterval(4), in: pass.path) ?? here
                let q = point(ahead.az, ahead.el)
                let heading = atan2(q.x - p.x, p.y - q.y) * 180 / .pi
                var flown = Path()
                flown.move(to: points[0])
                for (i, pt) in points.enumerated().dropFirst() where pass.path[i].date <= card.asOf { flown.addLine(to: pt) }
                flown.addLine(to: p)
                ctx.stroke(flown, with: .color(Theme.station), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: Theme.station.opacity(0.8), radius: 9))
                    layer.fill(Silhouettes.path(card.object.silhouette, center: p, size: 36, headingDeg: heading.isFinite ? heading : 0), with: .color(Theme.station))
                }
            }
        }
    }

    /// Azimuth and height along the path at a moment, in between its samples.
    private func position(at date: Date, in path: [SatellitePass.Point]) -> (az: Double, el: Double)? {
        guard let first = path.first, let last = path.last else { return nil }
        if date <= first.date { return (first.azimuthDeg, first.elevationDeg) }
        if date >= last.date { return (last.azimuthDeg, last.elevationDeg) }
        for (a, b) in zip(path, path.dropFirst()) where date >= a.date && date <= b.date {
            let f = date.timeIntervalSince(a.date) / max(b.date.timeIntervalSince(a.date), 0.001)
            var turn = b.azimuthDeg - a.azimuthDeg
            if turn > 180 { turn -= 360 } else if turn < -180 { turn += 360 }
            return (Geo.normalize(a.azimuthDeg + turn * f), a.elevationDeg + (b.elevationDeg - a.elevationDeg) * f)
        }
        return nil
    }
}
