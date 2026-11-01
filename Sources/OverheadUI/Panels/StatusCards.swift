import SwiftUI
import OverheadKit

/// Shown in place of the aircraft card when nothing is in range.
struct QuietSkiesCard: View {
    let engine: TrackingEngine
    @Environment(\.fixedNow) private var fixedNow

    var body: some View {
        let radius = MapZoom.label(radiusNM: engine.settings.mapRadiusNM, units: engine.settings.units).text
        let recent = Array(engine.sightings.prefix(5))
        VStack(alignment: .leading, spacing: 20) {
            Text("All clear").labelStyle(Theme.accent)
            Text("Quiet skies").font(Theme.serif(92)).foregroundStyle(Theme.text)
            Text("Nothing is flying within \(radius) right now. This screen wakes up the moment something does.")
                .font(Theme.body(28)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Re-read every minute, so "Tomorrow" becomes "Today" and a pass that has gone is replaced by the next.
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let now = fixedNow ?? timeline.date
                if let pass = engine.nextStationPass(after: now) {
                    let card = StationPassCard(pass: pass, asOf: now)
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(Theme.hairline).frame(height: 1.5).padding(.vertical, 6)
                        HStack(spacing: 18) {
                            AirlineBadge(size: 58, spacecraft: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Next Space Station pass").labelStyle()
                                Text(StationPassCard.whenText(for: pass, now: now)).font(Theme.body(30, weight: .bold)).foregroundStyle(Theme.text)
                                Text("\(card.route) · \(card.brightnessText) · reaches \(card.peakDegrees)° up")
                                    .font(Theme.body(22)).foregroundStyle(Theme.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }

            if !recent.isEmpty {
                Rectangle().fill(Theme.hairline).frame(height: 1.5).padding(.vertical, 6)
                Text("Recent sightings").labelStyle()
                VStack(spacing: 0) {
                    ForEach(recent) { s in
                        SightingRow(sighting: s, units: engine.settings.units)
                        if s.id != recent.last?.id { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    }
                }
            }
        }
        .padding(36)
        .frame(width: DetailPanel.width, alignment: .topLeading)
        .glassCard(radius: 40)
    }
}

private struct SightingRow: View {
    let sighting: Sighting
    let units: UnitSystem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sighting.title).font(Theme.number(30, weight: .bold)).foregroundStyle(Theme.text)
                Text([sighting.typeName, sighting.routeText].compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.body(22)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(sighting.lastSeen, style: .relative).font(Theme.body(22)).foregroundStyle(Theme.secondary)
                Text("closest \(units.distance(nm: sighting.closestNM).text)").font(Theme.body(20)).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.vertical, 13)
    }
}

/// First-launch prompt, floating over the demo traffic.
struct WelcomeCard: View {
    var focus: FocusState<Bool>.Binding
    var onSetup: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text("Welcome").labelStyle(Theme.accent)
            Text("See what's flying over your home")
                .font(Theme.serif(60)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Text("This is a demo with fictional flights. Set your location to switch to live aircraft.")
                .font(Theme.body(27)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            Button(action: onSetup) { SetupLabel() }.buttonStyle(FlatButtonStyle()).focused(focus)
        }
        .padding(44)
        .frame(width: 760)
        .glassCard(radius: 44, tint: .black.opacity(0.55))
    }

    private struct SetupLabel: View {
        @Environment(\.isFocused) private var isFocused
        var body: some View {
            Text("Set my location")
                .font(Theme.body(30, weight: .bold))
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .padding(.horizontal, 40).padding(.vertical, 18)
                .background(Capsule().fill(isFocused ? Color.white : Theme.accent.opacity(0.55)))
                .scaleEffect(isFocused ? 1.08 : 1)
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}
