import Foundation

/// Reads a latitude and longitude typed or pasted by hand, such as the pair a phone's Maps app shows for a dropped pin.
/// Accepts decimal degrees ("37.3349, -122.0090"), with N/S/E/W letters ("37.3349 N, 122.0090 W"), or degrees,
/// minutes and seconds ("37°20'06\"N 122°00'32\"W").
public enum Coordinates {
    public static func parse(_ text: String) -> GeoPoint? {
        var numbers: [Double] = []
        var hemispheres: [Character] = []
        var current = ""

        func flush() {
            if !current.isEmpty, let value = Double(current) { numbers.append(value) }
            current = ""
        }
        for ch in text.uppercased().replacingOccurrences(of: "\u{2212}", with: "-") {
            if ch.isASCII && (ch.isNumber || ch == ".") {
                current.append(ch)
            } else if ch == "-" {
                flush()
                current = "-"
            } else {
                flush()
                if "NSEW".contains(ch) { hemispheres.append(ch) }
                // Any other letter means this is not a coordinate pair at all.
                else if ch.isLetter { return nil }
            }
        }
        flush()

        let parts: Int
        switch numbers.count {
        case 2: parts = 1
        case 4: parts = 2
        case 6: parts = 3
        default: return nil
        }
        func degrees(_ chunk: ArraySlice<Double>) -> Double? {
            let v = Array(chunk)
            if v.count > 1, v[1...].contains(where: { $0 < 0 || $0 >= 60 }) { return nil }
            let magnitude = abs(v[0]) + (v.count > 1 ? v[1] / 60 : 0) + (v.count > 2 ? v[2] / 3600 : 0)
            return v[0] < 0 || (v[0] == 0 && chunk.first?.sign == .minus) ? -magnitude : magnitude
        }
        guard var latitude = degrees(numbers[0..<parts]), var longitude = degrees(numbers[parts..<(parts * 2)]) else { return nil }
        if hemispheres.contains("S") { latitude = -abs(latitude) }
        if hemispheres.contains("W") { longitude = -abs(longitude) }

        let point = GeoPoint(latitude: latitude, longitude: longitude)
        return point.isValid ? point : nil
    }

    /// "37.3349°, -122.0090°"
    public static func format(_ point: GeoPoint) -> String {
        String(format: "%.4f°, %.4f°", point.latitude, point.longitude)
    }
}
