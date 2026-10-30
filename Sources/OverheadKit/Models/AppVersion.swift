import Foundation

/// The app's version as shown to people: "1.0.1-beta". The number comes from the bundle; the pre-release
/// label (Info.plist ATReleaseChannel) is kept separate because Apple's version field allows only digits and dots.
public enum AppVersion {
    public static var number: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    public static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    public static var channel: String? {
        (Bundle.main.object(forInfoDictionaryKey: "ATReleaseChannel") as? String).flatMap(clean)
    }

    public static var display: String { format(number: number, channel: channel) }

    static func format(number: String, channel: String?) -> String {
        guard let channel = channel.flatMap(clean) else { return number }
        return "\(number)-\(channel)"
    }

    private static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
