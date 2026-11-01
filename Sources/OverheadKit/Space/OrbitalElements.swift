import Foundation

/// A satellite's orbit in the two-line element (TLE) format that CelesTrak and Space-Track publish, with the numbers SGP4 needs.
public struct OrbitalElements: Codable, Equatable, Sendable {
    public let name: String
    public let line1: String
    public let line2: String

    public let catalogNumber: Int
    /// The moment these elements describe exactly; predictions drift the further from it you go.
    public let epoch: Date
    let inclinationRad: Double
    let raanRad: Double
    let eccentricity: Double
    let argumentOfPerigeeRad: Double
    let meanAnomalyRad: Double
    /// Radians per minute (the TLE gives revolutions per day).
    let meanMotion: Double
    let bstar: Double

    /// Parses the two data lines, verifying their length, line numbers, checksums and that they describe one object.
    public init?(name: String = "", line1: String, line2: String) {
        let l1 = line1.trimmingCharacters(in: .whitespacesAndNewlines), l2 = line2.trimmingCharacters(in: .whitespacesAndNewlines)
        guard l1.count == 69, l2.count == 69, l1.hasPrefix("1 "), l2.hasPrefix("2 "),
              Self.checksumMatches(l1), Self.checksumMatches(l2) else { return nil }
        let a = Array(l1), b = Array(l2)
        func field(_ c: [Character], _ from: Int, _ to: Int) -> String { String(c[(from - 1)...(to - 1)]).trimmingCharacters(in: .whitespaces) }

        guard let catalog = Int(field(a, 3, 7)), Int(field(b, 3, 7)) == catalog,
              let yy = Int(field(a, 19, 20)), let day = Double(field(a, 21, 32)),
              let bstar = Self.impliedExponent(field(a, 54, 61)),
              let inclination = Double(field(b, 9, 16)), let raan = Double(field(b, 18, 25)),
              let eccentricity = Double("0." + field(b, 27, 33)), let perigee = Double(field(b, 35, 42)),
              let anomaly = Double(field(b, 44, 51)), let revsPerDay = Double(field(b, 53, 63)), revsPerDay > 0,
              day >= 1, day < 367
        else { return nil }

        let year = yy < 57 ? 2000 + yy : 1900 + yy
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let newYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }

        self.name = name.trimmingCharacters(in: .whitespaces)
        self.line1 = l1
        self.line2 = l2
        self.catalogNumber = catalog
        self.epoch = newYear.addingTimeInterval((day - 1) * 86_400)
        self.inclinationRad = inclination * .pi / 180
        self.raanRad = raan * .pi / 180
        self.eccentricity = eccentricity
        self.argumentOfPerigeeRad = perigee * .pi / 180
        self.meanAnomalyRad = anomaly * .pi / 180
        self.meanMotion = revsPerDay * 2 * .pi / 1440
        self.bstar = bstar
    }

    /// Reads a response of two lines, or of three with the object's name first.
    public static func parse(_ text: String) -> OrbitalElements? {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let i = lines.firstIndex(where: { $0.hasPrefix("1 ") }), i + 1 < lines.count else { return nil }
        return OrbitalElements(name: i > 0 ? lines[i - 1] : "", line1: lines[i], line2: lines[i + 1])
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .name)
        guard let parsed = OrbitalElements(name: name, line1: try c.decode(String.self, forKey: .line1), line2: try c.decode(String.self, forKey: .line2))
        else { throw DecodingError.dataCorruptedError(forKey: .line1, in: c, debugDescription: "Not a valid two-line element set") }
        self = parsed
    }

    enum CodingKeys: String, CodingKey { case name, line1, line2 }

    /// How long before (negative) or after (positive) the epoch `date` falls.
    public func age(at date: Date) -> TimeInterval { date.timeIntervalSince(epoch) }

    /// "26305.40213002" style fields hold digits, and a minus sign counts as 1, in the last column.
    private static func checksumMatches(_ line: String) -> Bool {
        let chars = Array(line)
        var sum = 0
        for ch in chars.prefix(68) {
            if let d = ch.wholeNumberValue { sum += d } else if ch == "-" { sum += 1 }
        }
        return chars[68].wholeNumberValue == sum % 10
    }

    /// The format used for B*: a sign, five digits with an implied leading decimal point, and a signed exponent ("13304-3" is 0.13304e-3).
    private static func impliedExponent(_ field: String) -> Double? {
        var text = field, sign = 1.0
        if text.first == "-" { sign = -1; text.removeFirst() } else if text.first == "+" { text.removeFirst() }
        guard text.count >= 3, let exponent = Int(text.suffix(2)), let mantissa = Double("0." + text.dropLast(2)) else { return nil }
        return sign * mantissa * pow(10, Double(exponent))
    }
}
