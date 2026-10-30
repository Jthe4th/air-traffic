import SwiftUI

private struct FixedNowKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var fixedNow: Date? {
        get { self[FixedNowKey.self] }
        set { self[FixedNowKey.self] = newValue }
    }
}

extension View {
    /// Freezes the display clock. Used by the design preview so renders are reproducible.
    public func fixedClock(_ date: Date?) -> some View { environment(\.fixedNow, date) }
}
