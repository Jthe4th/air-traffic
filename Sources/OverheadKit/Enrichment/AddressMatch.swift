import Foundation

/// A street address that a geocoder resolved to a point. The street address is only shown while choosing; the app keeps
/// the point and the town name, so a house number never ends up on the TV or in the saved settings.
public struct AddressMatch: Hashable, Sendable, Identifiable {
    /// One line, as shown in the list of matches.
    public var address: String
    /// "Springfield, IL": what the header shows afterwards.
    public var placeName: String
    public var location: GeoPoint
    public var id: String { "\(address)|\(location.latitude)|\(location.longitude)" }

    public init(address: String, placeName: String, location: GeoPoint) {
        self.address = address; self.placeName = placeName; self.location = location
    }

    /// "123 Main St\nSpringfield, IL  62701" becomes "123 Main St, Springfield, IL 62701".
    public static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Drops matches without a usable point, and repeats, keeping the geocoder's order.
    public static func usable(_ matches: [AddressMatch], limit: Int = 5) -> [AddressMatch] {
        var seen = Set<String>()
        var out: [AddressMatch] = []
        for match in matches where match.location.isValid && !match.address.isEmpty && seen.insert(match.id).inserted {
            out.append(match)
            if out.count == limit { break }
        }
        return out
    }
}
