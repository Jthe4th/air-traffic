import Foundation

public struct SquawkInfo: Hashable, Sendable {
    public var meaning: String
    public var isEmergency: Bool
}

public enum Squawk {
    public static func info(for code: String?) -> SquawkInfo? {
        guard let code else { return nil }
        return table[code]
    }

    private static let table: [String: SquawkInfo] = [
        "7500": SquawkInfo(meaning: "Hijacking", isEmergency: true),
        "7600": SquawkInfo(meaning: "Radio failure", isEmergency: true),
        "7700": SquawkInfo(meaning: "General emergency", isEmergency: true),
        "1200": SquawkInfo(meaning: "VFR, no ATC (US)", isEmergency: false),
        "7000": SquawkInfo(meaning: "VFR, no ATC (Europe)", isEmergency: false),
        "2000": SquawkInfo(meaning: "No ATC code assigned", isEmergency: false),
        "1255": SquawkInfo(meaning: "Firefighting", isEmergency: false),
        "1276": SquawkInfo(meaning: "Air defense zone", isEmergency: false),
        "1277": SquawkInfo(meaning: "Search & rescue", isEmergency: false),
        "7777": SquawkInfo(meaning: "Military intercept", isEmergency: false),
        "7400": SquawkInfo(meaning: "Drone lost link", isEmergency: false),
    ]
}
