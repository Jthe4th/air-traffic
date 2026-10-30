import Foundation
import CoreGraphics

public struct MapTile: Hashable, Sendable, Identifiable {
    public var x: Int
    public var y: Int
    public var z: Int
    /// Where the tile's top-left corner lands in view coordinates, and its edge length in points.
    public var origin: CGPoint
    public var size: CGFloat
    public var id: String { "\(z)/\(x)/\(y)" }
}

/// Web-Mercator camera. The geographic `center` is drawn at `anchor` inside a `size` viewport,
/// at a (fractional) zoom level. Tiles are fetched at the integer zoom below and scaled to fit.
public struct MapCamera: Sendable, Equatable {
    public var center: GeoPoint
    public var zoom: Double
    public var size: CGSize
    public var anchor: CGPoint
    /// How many zoom levels deeper than the view zoom to fetch tiles (1 for 256 px tiles on a TV).
    public var tileZoomBias: Int

    public init(center: GeoPoint, zoom: Double, size: CGSize, anchor: CGPoint? = nil, tileZoomBias: Int = 0) {
        self.center = center
        self.zoom = zoom
        self.size = size
        self.anchor = anchor ?? CGPoint(x: size.width / 2, y: size.height / 2)
        self.tileZoomBias = tileZoomBias
    }

    /// Picks the zoom at which `radiusNM` spans `radiusPoints` on screen.
    public static func fitting(radiusNM: Double, radiusPoints: CGFloat, center: GeoPoint, size: CGSize, anchor: CGPoint? = nil, tileZoomBias: Int = 0) -> MapCamera {
        let metersPerPoint = radiusNM * Geo.metersPerNM / Double(radiusPoints)
        let z = log2(156_543.03392 * cos(Geo.rad(center.latitude)) / metersPerPoint)
        return MapCamera(center: center, zoom: min(max(z, 3), 17), size: size, anchor: anchor, tileZoomBias: tileZoomBias)
    }

    private func worldPoint(_ p: GeoPoint, zoom z: Double) -> (x: Double, y: Double) {
        let scale = 256 * pow(2, z)
        let sinLat = sin(Geo.rad(max(-85, min(85, p.latitude))))
        let x = (p.longitude + 180) / 360 * scale
        let y = (0.5 - log((1 + sinLat) / (1 - sinLat)) / (4 * .pi)) * scale
        return (x, y)
    }

    public func point(for p: GeoPoint) -> CGPoint {
        let c = worldPoint(center, zoom: zoom), w = worldPoint(p, zoom: zoom)
        return CGPoint(x: anchor.x + (w.x - c.x), y: anchor.y + (w.y - c.y))
    }

    public var pointsPerNM: Double {
        let metersPerPoint = 156_543.03392 * cos(Geo.rad(center.latitude)) / pow(2, zoom)
        return Geo.metersPerNM / metersPerPoint
    }

    /// The integer zoom level the map tiles are fetched at.
    public var tileZoomLevel: Int { min(19, Int(zoom.rounded(.down)) + tileZoomBias) }

    public var tiles: [MapTile] {
        let zi = tileZoomLevel
        let tileSize = 256 * pow(2, zoom - Double(zi))
        let c = worldPoint(center, zoom: zoom)
        let left = c.x - Double(anchor.x), top = c.y - Double(anchor.y)
        let maxIndex = (1 << zi) - 1
        let x0 = Int((left / tileSize).rounded(.down)), x1 = Int(((left + Double(size.width)) / tileSize).rounded(.down))
        let y0 = Int((top / tileSize).rounded(.down)), y1 = Int(((top + Double(size.height)) / tileSize).rounded(.down))
        var out: [MapTile] = []
        for ty in max(0, y0)...max(0, min(maxIndex, y1)) {
            for tx in x0...x1 {
                let wrapped = ((tx % (maxIndex + 1)) + (maxIndex + 1)) % (maxIndex + 1)
                out.append(MapTile(
                    x: wrapped, y: ty, z: zi,
                    origin: CGPoint(x: CGFloat(Double(tx) * tileSize - left), y: CGFloat(Double(ty) * tileSize - top)),
                    size: CGFloat(tileSize)))
            }
        }
        return out
    }
}

/// Where map tiles come from. The default is OpenStreetMap, darkened at draw time.
public enum MapStyle {
    public static let defaultTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    /// Set at launch from the app's Info.plist to use a different tile server, e.g. a dark style from
    /// a provider you have a key for. Placeholders: {z} {x} {y}. Add "@2x" in the template for 512 px tiles.
    public nonisolated(unsafe) static var templateOverride: String?
    public nonisolated(unsafe) static var attributionOverride: String?

    public static var template: String { templateOverride ?? defaultTemplate }
    public static var attribution: String { attributionOverride ?? "© OpenStreetMap contributors" }
    /// 256 px tiles are fetched one zoom level deeper so they stay sharp on a TV.
    public static var tileZoomBias: Int { template.contains("@2x") ? 0 : 1 }
    /// The default OpenStreetMap tiles are light; the dark look is produced by filtering them.
    /// A custom template is assumed to already be dark.
    public static var appliesDarkFilter: Bool { templateOverride == nil }

    public static func url(for tile: MapTile) -> URL {
        let s = template
            .replacingOccurrences(of: "{z}", with: String(tile.z))
            .replacingOccurrences(of: "{x}", with: String(tile.x))
            .replacingOccurrences(of: "{y}", with: String(tile.y))
        return URL(string: s) ?? URL(string: "https://tile.openstreetmap.org/\(tile.z)/\(tile.x)/\(tile.y).png")!
    }
}
