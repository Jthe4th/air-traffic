import SwiftUI
import OverheadKit

/// Row of aircraft in range, nearest first. On tvOS each chip is focusable: swiping the remote
/// across the row selects that aircraft, which then stays featured for a minute.
struct NearbyStrip: View {
    let engine: TrackingEngine
    @FocusState private var focused: String?
    @State private var appeared = Date()
    @Environment(\.fixedNow) private var fixedNow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = fixedNow ?? timeline.date
            let airborne = engine.visibleAircraft(at: now).filter { !$0.aircraft.onGround }.prefix(14)
            let row = HStack(spacing: 14) {
                ForEach(Array(airborne)) { t in
                    Button { engine.pin(t.id) } label: {
                        Chip(tracked: t, selected: t.id == engine.featuredID, home: engine.home, now: now, units: engine.settings.units)
                    }
                    .buttonStyle(FlatButtonStyle())
                    .focused($focused, equals: t.id)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
            #if os(macOS)
            row.frame(width: 1000, alignment: .leading).clipped()   // design-preview only; ImageRenderer can't draw ScrollView
            #else
            ScrollView(.horizontal, showsIndicators: false) { row }.scrollClipDisabled()
            #endif
        }
        .frame(height: 164)
        #if !os(iOS)
        .focusSection()
        #endif
        .onChange(of: focused) { _, id in
            // Ignore the system's initial focus assignment; only a deliberate move selects.
            if let id, Date().timeIntervalSince(appeared) > 3 { engine.pin(id) }
        }
    }
}

private struct Chip: View {
    let tracked: TrackedAircraft
    let selected: Bool
    let home: GeoPoint
    let now: Date
    let units: UnitSystem
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let a = tracked.aircraft
        let d = units.distance(nm: Geo.distanceNM(home, a.position(at: now)))
        let tint = Theme.altitudeColor(a.altitudeFt(at: now), onGround: a.onGround)
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        HStack(spacing: 14) {
            AirlineBadge(airline: tracked.airline, fallbackText: a.registration.map { String($0.prefix(2)) } ?? "", size: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(tracked.flightNumber ?? a.title)
                    .font(Theme.number(28, weight: .bold)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 11, height: 11)
                    Text(subtitle(a, now: now)).font(Theme.body(21)).foregroundStyle(Theme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(d.value).font(Theme.number(30)).foregroundStyle(Theme.text)
                Text(d.unit).font(Theme.body(19)).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 330, height: 98)
        .background(shape.fill(.ultraThinMaterial).overlay(shape.fill(.black.opacity(selected || isFocused ? 0.30 : 0.50))))
        .overlay(shape.strokeBorder(isFocused ? Color.white.opacity(0.95) : (selected ? Theme.accent : Theme.hairline),
                                    lineWidth: isFocused ? 4 : (selected ? 3 : 1.5)))
        .shadow(color: .black.opacity(isFocused ? 0.55 : 0.3), radius: isFocused ? 26 : 12, y: isFocused ? 14 : 6)
        .scaleEffect(isFocused ? 1.08 : 1)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }

    private func subtitle(_ a: Aircraft, now: Date) -> String {
        let type = a.typeCode ?? "—"
        guard let ft = a.altitudeFt(at: now) else { return type }
        let alt = flightLevelText(altitudeFt: Int(ft)) ?? units.altitude(ft: ft).text
        return "\(type) · \(alt)"
    }
}
