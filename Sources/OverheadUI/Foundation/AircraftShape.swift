import SwiftUI
import OverheadKit

/// Top-down aircraft silhouettes in a unit box (-1…1), nose pointing up.
enum Silhouettes {
    static func unitPath(_ kind: AircraftKind.Silhouette) -> Path {
        switch kind {
        case .jet: mirrored([
            (0.00, -1.00), (0.08, -0.86), (0.10, -0.40), (0.12, -0.12), (0.98, 0.34), (0.98, 0.50),
            (0.14, 0.26), (0.11, 0.62), (0.40, 0.86), (0.40, 0.98), (0.07, 0.90), (0.00, 1.00),
        ])
        case .prop: mirrored([
            (0.00, -1.00), (0.07, -0.93), (0.09, -0.42), (0.98, -0.36), (0.98, -0.10), (0.10, -0.02),
            (0.09, 0.58), (0.40, 0.76), (0.40, 0.92), (0.06, 0.86), (0.00, 0.96),
        ])
        case .helicopter: helicopter()
        case .station: station()
        }
    }

    private static func mirrored(_ rightHalf: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rightHalf[0].0, y: rightHalf[0].1))
        for pt in rightHalf.dropFirst() { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        for pt in rightHalf.dropFirst().dropLast().reversed() { p.addLine(to: CGPoint(x: -pt.0, y: pt.1)) }
        p.closeSubpath()
        return p
    }

    private static func helicopter() -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: -0.22, y: -0.55, width: 0.44, height: 0.85))          // cabin
        p.addRect(CGRect(x: -0.05, y: 0.25, width: 0.10, height: 0.70))                     // tail boom
        p.addRect(CGRect(x: -0.20, y: 0.82, width: 0.40, height: 0.08))                     // tail rotor
        for angle in [28.0, 118.0] {                                                          // main rotor
            let blade = Path(CGRect(x: -1.0, y: -0.035, width: 2.0, height: 0.07))
                .applying(CGAffineTransform(translationX: 0, y: -0.12).rotated(by: angle * .pi / 180))
            p.addPath(blade)
        }
        return p
    }

    /// The Space Station from above, flying nose-up: the truss runs across the direction of travel, the solar arrays are the
    /// four wide panels, and the pressurised modules run along it.
    private static func station() -> Path {
        var p = Path()
        p.addRect(CGRect(x: -0.97, y: -0.04, width: 1.94, height: 0.08))                    // main truss
        p.addRect(CGRect(x: -0.06, y: -0.66, width: 0.12, height: 1.16))                    // modules
        for x in [-0.80, -0.44, 0.44, 0.80] {                                                  // solar arrays
            p.addRect(CGRect(x: x - 0.10, y: -0.46, width: 0.20, height: 0.92))
        }
        p.addRect(CGRect(x: -0.22, y: 0.18, width: 0.44, height: 0.07))                     // radiator
        return p
    }

    static func path(_ kind: AircraftKind.Silhouette, center: CGPoint, size: CGFloat, headingDeg: Double) -> Path {
        let t = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: headingDeg * .pi / 180)
            .scaledBy(x: size / 2, y: size / 2)
        return unitPath(kind).applying(t)
    }

    static func size(for aircraft: Aircraft, featured: Bool) -> CGFloat {
        let base: CGFloat = switch aircraft.wakeClass {
        case .heavy: 38
        case .highVortex, .large: 32
        case .small: 27
        case .light, .ultralight, .glider: 23
        case .rotorcraft: 28
        case .spaceVehicle: 42
        default: 28
        }
        return featured ? base * 1.3 : base
    }
}

/// SwiftUI view of a silhouette, used as the photo placeholder.
struct SilhouetteView: Shape {
    var kind: AircraftKind.Silhouette
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        return Silhouettes.path(kind, center: CGPoint(x: rect.midX, y: rect.midY), size: side, headingDeg: 0)
    }
}
