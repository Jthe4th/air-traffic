import SwiftUI
import OverheadKit

/// The app icon and Top Shelf artwork, drawn in code so it can be regenerated at any size:
/// `design-preview --icons <dir>` renders the layers that go into the asset catalog.
public struct AppIconArtwork: View {
    public enum Layer { case back, middle, front }
    public enum Format { case icon, banner }

    let layer: Layer?
    let format: Format

    /// `layer` nil draws every layer into one image (used for the flat Top Shelf banners).
    public init(layer: Layer? = nil, format: Format = .icon) {
        self.layer = layer
        self.format = format
    }

    public var body: some View {
        ZStack {
            if layer == nil || layer == .back { Canvas { ctx, size in Painter.back(&ctx, size, format) } }
            if layer == nil || layer == .middle { Canvas { ctx, size in Painter.middle(&ctx, size, format) } }
            if layer == nil || layer == .front { Canvas { ctx, size in Painter.front(&ctx, size, format) } }
            if layer == nil && format == .banner {
                GeometryReader { geo in
                    VStack(alignment: .leading, spacing: geo.size.height * 0.02) {
                        Text("Air Traffic")
                            .font(.system(size: geo.size.height * 0.2, weight: .regular, design: .serif))
                            .foregroundStyle(.white)
                        Text("What's flying over your home")
                            .font(.system(size: geo.size.height * 0.058, weight: .medium))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    .shadow(color: .black.opacity(0.6), radius: geo.size.height * 0.03)
                    .position(x: geo.size.width * 0.27, y: geo.size.height * 0.5)
                }
            }
        }
    }

    private enum Painter {
        struct Frame { let center: CGPoint; let unit: CGFloat }

        static func frame(_ size: CGSize, _ format: Format) -> Frame {
            switch format {
            case .icon: Frame(center: CGPoint(x: size.width * 0.5, y: size.height * 0.52), unit: size.height)
            case .banner: Frame(center: CGPoint(x: size.width * 0.76, y: size.height * 0.5), unit: size.height * 1.1)
            }
        }

        static func back(_ ctx: inout GraphicsContext, _ size: CGSize, _ format: Format) {
            let f = frame(size, format)
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(red: 0.025, green: 0.04, blue: 0.075), Color(red: 0.06, green: 0.11, blue: 0.19)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width * 0.25, y: size.height)))
            ctx.fill(Path(rect), with: .radialGradient(
                Gradient(colors: [Theme.accent.opacity(0.34), Theme.accent.opacity(0.08), .clear]),
                center: f.center, startRadius: 0, endRadius: f.unit * 0.8))

            // A faint chart grid, like a radar scope.
            let step = f.unit * 0.11
            var grid = Path()
            var x = f.center.x.truncatingRemainder(dividingBy: step)
            while x < size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y = f.center.y.truncatingRemainder(dividingBy: step)
            while y < size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(grid, with: .color(.white.opacity(0.035)), lineWidth: max(1, f.unit * 0.003))

            ctx.fill(Path(rect), with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(0.5)]),
                center: f.center, startRadius: f.unit * 0.55, endRadius: max(size.width, size.height) * 0.75))
        }

        static func middle(_ ctx: inout GraphicsContext, _ size: CGSize, _ format: Format) {
            let f = frame(size, format)
            let lw = max(1.5, f.unit * 0.006)

            for (i, r) in [0.17, 0.31, 0.45].enumerated() {
                let radius = f.unit * r
                let ring = Path(ellipseIn: CGRect(x: f.center.x - radius, y: f.center.y - radius, width: radius * 2, height: radius * 2))
                if i == 1 {
                    ctx.stroke(ring, with: .color(Theme.accent.opacity(0.7)), style: StrokeStyle(lineWidth: lw * 1.3, dash: [f.unit * 0.035, f.unit * 0.025]))
                } else {
                    ctx.stroke(ring, with: .color(.white.opacity(i == 2 ? 0.26 : 0.16)), lineWidth: lw)
                }
            }

            // The viewer's home at the centre.
            let h = f.unit * 0.03
            ctx.fill(Path(ellipseIn: CGRect(x: f.center.x - h, y: f.center.y - h, width: h * 2, height: h * 2)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: f.center.x - h * 2, y: f.center.y - h * 2, width: h * 4, height: h * 4)),
                       with: .color(.white.opacity(0.6)), lineWidth: lw)

            // A dotted trail running in from lower left, fading in toward the aircraft.
            let start = CGPoint(x: f.center.x - f.unit * 0.50, y: f.center.y + f.unit * 0.30)
            let control = CGPoint(x: f.center.x - f.unit * 0.30, y: f.center.y + f.unit * 0.02)
            let end = CGPoint(x: f.center.x + f.unit * 0.13, y: f.center.y - f.unit * 0.12)
            let dots = 22
            for i in 0..<dots {
                let t = Double(i) / Double(dots - 1)
                let p = CGPoint(
                    x: (1 - t) * (1 - t) * start.x + 2 * (1 - t) * t * control.x + t * t * end.x,
                    y: (1 - t) * (1 - t) * start.y + 2 * (1 - t) * t * control.y + t * t * end.y)
                let r = f.unit * (0.006 + 0.012 * t)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.altitudeColor(12_000 + 14_000 * t).opacity(0.25 + 0.7 * t)))
            }

            // Other traffic, small and colour-coded by altitude as on the map.
            let others: [(dx: Double, dy: Double, heading: Double, alt: Double)] = [
                (0.30, 0.24, 215, 3_500), (-0.30, -0.22, 120, 9_000), (0.40, -0.14, 330, 36_000),
            ]
            for o in others {
                let c = CGPoint(x: f.center.x + f.unit * o.dx, y: f.center.y + f.unit * o.dy)
                let p = Silhouettes.path(.jet, center: c, size: f.unit * 0.085, headingDeg: o.heading)
                ctx.stroke(p, with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: f.unit * 0.008, lineJoin: .round))
                ctx.fill(p, with: .color(Theme.altitudeColor(o.alt)))
            }
        }

        static func front(_ ctx: inout GraphicsContext, _ size: CGSize, _ format: Format) {
            let f = frame(size, format)
            let at = CGPoint(x: f.center.x + f.unit * 0.13, y: f.center.y - f.unit * 0.12)
            let plane = Silhouettes.path(.jet, center: at, size: f.unit * 0.50, headingDeg: 42)
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: Theme.accent.opacity(0.85), radius: f.unit * 0.05))
                layer.stroke(plane, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: f.unit * 0.014, lineJoin: .round))
                layer.fill(plane, with: .linearGradient(
                    Gradient(colors: [Color(red: 0.72, green: 0.92, blue: 1.0), Theme.accent, Color(red: 0.30, green: 0.52, blue: 1.0)]),
                    startPoint: CGPoint(x: at.x - f.unit * 0.2, y: at.y - f.unit * 0.25),
                    endPoint: CGPoint(x: at.x + f.unit * 0.2, y: at.y + f.unit * 0.25)))
            }
            ctx.stroke(plane, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: max(1, f.unit * 0.004), lineJoin: .round))
        }
    }
}
