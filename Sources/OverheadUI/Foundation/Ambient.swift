import SwiftUI

/// Always-on display behaviour: fades the controls out when nobody is using them, dims the screen at night,
/// and nudges everything by a few pixels over time so a static layout can't burn into an OLED panel.
@MainActor
@Observable
public final class Ambient {
    public var controlsHidden = false
    public var isNight = false
    public var shift = CGSize.zero
    /// Stops the clock-driven updates, so design previews can pin a state.
    public var isFrozen = false

    @ObservationIgnored private var lastInput = Date()

    public init() {}

    /// Any remote activity wakes the controls.
    public func touch(at now: Date = Date()) {
        lastInput = now
        if controlsHidden { controlsHidden = false }
    }

    /// For button presses: when the controls were hidden the press only wakes them and must not also act,
    /// since the viewer couldn't see what they were pressing.
    public func consumeWakeUp() -> Bool {
        guard controlsHidden else { return false }
        touch()
        return true
    }

    func tick(now: Date, idleAfter: Double, nightDimming: Bool, keepControlsVisible: Bool) {
        guard !isFrozen else { return }
        let hide = idleAfter > 0 && !keepControlsVisible && now.timeIntervalSince(lastInput) >= idleAfter
        if hide != controlsHidden { controlsHidden = hide }

        let hour = Calendar.current.component(.hour, from: now)
        let night = nightDimming && (hour >= 22 || hour < 6)
        if night != isNight { isNight = night }

        // A slow drift of a few whole pixels: under one pixel a minute, invisible but enough to spread wear.
        let t = now.timeIntervalSinceReferenceDate
        let next = CGSize(width: (7 * sin(t / 600)).rounded(), height: (7 * cos(t / 830)).rounded())
        if next != shift { shift = next }
    }
}

private struct AmbientKey: EnvironmentKey {
    static let defaultValue: Ambient? = nil
}

extension EnvironmentValues {
    var ambient: Ambient? {
        get { self[AmbientKey.self] }
        set { self[AmbientKey.self] = newValue }
    }
}
