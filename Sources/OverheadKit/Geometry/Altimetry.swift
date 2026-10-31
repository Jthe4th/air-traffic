import Foundation

/// ADS-B reports barometric altitude as *pressure altitude*: height measured against a fixed 1013.25 hPa. On a day of high
/// pressure that reads below zero near sea level, and a plane on a runway can show -400 ft. Pilots below the transition
/// altitude set the local pressure (QNH) instead, and many aircraft broadcast that setting. These functions use it to turn
/// pressure altitude into altitude above sea level, the number a pilot's altimeter shows.
public enum Altimetry {
    public static let standardHPa = 1013.25
    /// Above this pressure altitude flight levels (always 1013.25 hPa) are the convention, so nothing is corrected.
    public static let correctionCeilingFt = 17_000

    /// Altitude above sea level for an aircraft at `pressureAltitudeFt` when the local sea-level pressure is `qnhHPa`
    /// (International Standard Atmosphere).
    public static func indicatedAltitudeFt(pressureAltitudeFt: Double, qnhHPa: Double) -> Double {
        let exponent = 5.25588                                       // g / (R·L)
        let meters = pressureAltitudeFt * 0.3048
        let pressure = standardHPa * pow(1 - 0.0065 * meters / 288.15, exponent)
        let indicated = (288.15 / 0.0065) * (1 - pow(pressure / qnhHPa, 1 / exponent))
        return indicated / 0.3048
    }

    static func isPlausible(_ hPa: Double) -> Bool { (940...1060).contains(hPa) }

    /// The area's pressure setting: the median of what aircraft flying low report. Aircraft up at flight levels are left out;
    /// they are on 1013.25 whatever the weather.
    public static func localSetting(_ aircraft: [Aircraft]) -> Double? {
        let settings = aircraft.compactMap { a -> Double? in
            guard !a.onGround, let q = a.altimeterSettingHPa, isPlausible(q),
                  let baro = a.barometricAltitudeFt, baro < 12_000 else { return nil }
            return q
        }.sorted()
        guard !settings.isEmpty else { return nil }
        return settings[settings.count / 2]
    }

    /// The aircraft with its altitude corrected, using the area's setting, else its own, else leaving it as reported.
    public static func corrected(_ aircraft: Aircraft, localSetting: Double?) -> Aircraft {
        var a = aircraft
        guard !a.onGround, let baro = a.barometricAltitudeFt, baro <= correctionCeilingFt else { return a }
        let own = a.altimeterSettingHPa.flatMap { isPlausible($0) ? $0 : nil }
        guard let qnh = localSetting ?? own else { return a }
        a.qnhCorrectionFt = Int((indicatedAltitudeFt(pressureAltitudeFt: Double(baro), qnhHPa: qnh) - Double(baro)).rounded())
        return a
    }
}
