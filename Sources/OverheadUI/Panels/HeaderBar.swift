import SwiftUI
import OverheadKit

struct HeaderBar: View {
    let engine: TrackingEngine
    var onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            StatusPill(engine: engine)
            Spacer(minLength: 0)
            ClockView()
            SettingsButton(action: onSettings)
        }
        // The row spans the full width, so one swipe up from any chip lands on the gear.
        #if !os(iOS)
        .focusSection()
        #endif
    }
}

private struct StatusPill: View {
    let engine: TrackingEngine

    var body: some View {
        let (label, color) = state
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                PulsingDot(color: color)
                Text(label).labelStyle(color)
                if !engine.isDemo { Text("· \(engine.sourceName)").labelStyle(Theme.tertiary) }
            }
            Text(engine.locationName)
                .font(Theme.serif(34)).foregroundStyle(Theme.text).lineLimit(1)
            Text(summary).font(Theme.body(23)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 26).padding(.vertical, 16)
        .frame(width: 560, alignment: .leading)
        .glassCard(radius: 30)
    }

    private var state: (String, Color) {
        if engine.isDemo { return ("Demo traffic", Theme.accent) }
        switch engine.status {
        case .starting: return ("Connecting", Theme.warning)
        case .live: return ("Live", Theme.climb)
        case .offline: return ("Offline · retrying", Theme.danger)
        }
    }

    private var summary: String {
        if case .offline(let message) = engine.status { return message }
        let n = engine.visibleAircraft().count
        let radius = MapZoom.label(radiusNM: engine.settings.mapRadiusNM, units: engine.settings.units).text
        return n == 0 ? "No aircraft within \(radius)" : "\(n) aircraft within \(radius)"
    }
}

private struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: 22, height: 22).scaleEffect(pulse ? 1.5 : 0.8).opacity(pulse ? 0 : 1)
            Circle().fill(color).frame(width: 12, height: 12)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

struct ClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(alignment: .trailing, spacing: 0) {
                Text(timeline.date, format: .dateTime.hour().minute())
                    .font(Theme.serif(66)).foregroundStyle(Theme.text).monospacedDigit()
                Text(timeline.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .labelStyle(Theme.secondary)
            }
            .shadow(color: .black.opacity(0.6), radius: 8)
        }
    }
}

private struct SettingsButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) { Inner() }.buttonStyle(FlatButtonStyle())
    }

    private struct Inner: View {
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(isFocused ? Color.black : Theme.secondary)
                .frame(width: 76, height: 76)
                .background(Circle().fill(isFocused ? Color.white : Color.black.opacity(0.45)))
                .overlay(Circle().strokeBorder(.white.opacity(isFocused ? 0 : 0.18), lineWidth: 1.5))
                .scaleEffect(isFocused ? 1.14 : 1)
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}
