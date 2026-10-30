import Foundation

public enum AlertLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case off, emergency, emergencyAndNotable

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: "Off"
        case .emergency: "Emergencies only"
        case .emergencyAndNotable: "Emergencies and notable aircraft"
        }
    }
}

public struct AircraftAlert: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case emergency(String)
        case notable

        public var isEmergency: Bool {
            if case .emergency = self { return true }
            return false
        }
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var distanceNM: Double
    public var onMap: Bool

    public var headline: String { kind.isEmergency ? "Emergency" : "Notable aircraft" }
    public var detail: String {
        if case .emergency(let text) = kind { return text }
        return "Flagged as interesting"
    }
}

public enum Alerts {
    /// What, if anything, makes this aircraft worth a banner.
    public static func evaluate(_ a: Aircraft, level: AlertLevel) -> AircraftAlert.Kind? {
        guard level != .off, !a.onGround else { return nil }
        if let text = emergencyText(a) { return .emergency(text) }
        if level == .emergencyAndNotable, a.flags.contains(.interesting) { return .notable }
        return nil
    }

    static func emergencyText(_ a: Aircraft) -> String? {
        if let code = a.squawk, let info = Squawk.info(for: code), info.isEmergency {
            return "Squawk \(code) · \(info.meaning)"
        }
        // "lifeguard" (medical flight) is reported by the same field but is not an emergency.
        switch a.emergency {
        case "general": return "General emergency"
        case "minfuel": return "Minimum fuel"
        case "nordo": return "No radio"
        case "unlawful": return "Hijacking"
        case "downed": return "Downed aircraft"
        default: return nil
        }
    }
}
