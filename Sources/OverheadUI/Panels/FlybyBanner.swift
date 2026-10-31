import SwiftUI
import OverheadKit

/// A card that says an aircraft is about to pass close, and which way to look from the viewer's seat.
struct FlybyBanner: View {
    let card: FlybyCard
    let units: UnitSystem

    var body: some View {
        HStack(spacing: 32) {
            SkyDial(look: card.pass.look, altitudeFt: card.isSample ? nil : card.pass.altitudeFt)
                .frame(width: 196, height: 196)

            VStack(alignment: .leading, spacing: 8) {
                Text(card.headline).labelStyle(Theme.accent)
                Text(card.place)
                    .font(Theme.serif(54, weight: .semibold)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !card.directionDetail.isEmpty {
                    Text(Self.capitalizingFirst(card.directionDetail)).font(Theme.body(28)).foregroundStyle(Theme.text.opacity(0.92))
                }
                HStack(spacing: 16) {
                    Text(card.title).font(Theme.number(30, weight: .bold)).foregroundStyle(Theme.text)
                    if let detail = card.detail {
                        Text(detail).font(Theme.body(24)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                .padding(.top, 4)
                if let stats { Text(stats).font(Theme.number(24, weight: .medium)).foregroundStyle(Theme.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 36).padding(.vertical, 24)
        .frame(width: 870, alignment: .leading)     // stops short of the zoom buttons at the right edge
        .glassCard(radius: 44, tint: Theme.accent.opacity(0.20))
    }

    private var stats: String? {
        guard !card.isSample else { return nil }
        var parts = [units.altitude(ft: Double(card.pass.altitudeFt)).text]
        if let closest = card.pass.closestNM, card.phase != .close {
            parts.append("passes \(units.distance(nm: closest).text) away")
        } else {
            parts.append("\(units.distance(nm: card.pass.distanceNM).text) away")
        }
        return parts.joined(separator: " · ")
    }

    private static func capitalizingFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

/// The sky as the viewer sees it from their seat: straight up is the middle, the horizon is the outer ring, and the top
/// is the way they face (or north, until they have said which way that is).
struct SkyDial: View {
    let look: LookDirection
    let altitudeFt: Int?

    var body: some View {
        let facing = look.headingDeg != nil
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2 - 30     // leaves room for the labels outside the ring
                for (i, fraction) in [1.0, 2.0 / 3, 1.0 / 3].enumerated() {
                    let ring = Path(ellipseIn: CGRect(x: c.x - r * fraction, y: c.y - r * fraction, width: r * 2 * fraction, height: r * 2 * fraction))
                    ctx.stroke(ring, with: .color(.white.opacity(i == 0 ? 0.36 : 0.14)), lineWidth: i == 0 ? 2.5 : 1.2)
                }
                var cross = Path()
                cross.move(to: CGPoint(x: c.x, y: c.y - r)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
                cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
                ctx.stroke(cross, with: .color(.white.opacity(0.10)), lineWidth: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(.white.opacity(0.75)))

                let angle = (look.relativeDeg ?? look.bearingDeg) * .pi / 180
                let radius = r * (90 - look.elevationDeg) / 90
                let p = CGPoint(x: c.x + radius * sin(angle), y: c.y - radius * cos(angle))
                let color = altitudeFt.map { Theme.altitudeColor(Double($0)) } ?? Theme.accent

                var line = Path()
                line.move(to: c); line.addLine(to: p)
                ctx.stroke(line, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 2.5, dash: [4, 7]))
                if let track = look.trackDeg {
                    ctx.fill(Silhouettes.path(.jet, center: p, size: 38, headingDeg: track - (look.headingDeg ?? 0)), with: .color(color))
                } else {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), with: .color(color))
                }
            }

            VStack {
                if facing { Image(systemName: "tv").font(.system(size: 24, weight: .semibold)) } else { Text("N").font(.system(size: 22, weight: .bold)) }
                Spacer()
                Text(facing ? "BEHIND" : "S").font(.system(size: 15, weight: .bold)).tracking(1)
            }
            .foregroundStyle(Theme.secondary)
        }
    }
}
