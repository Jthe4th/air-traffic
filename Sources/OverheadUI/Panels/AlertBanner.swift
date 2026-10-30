import SwiftUI
import OverheadKit

/// Up to two banners for aircraft in distress (or flagged as notable), shown whatever the controls are doing.
struct AlertBanner: View {
    let alerts: [AircraftAlert]
    let units: UnitSystem

    var body: some View {
        VStack(spacing: 12) {
            ForEach(alerts.prefix(2)) { alert in
                let emergency = alert.kind.isEmergency
                let tint = emergency ? Theme.danger : Theme.warning
                HStack(spacing: 20) {
                    Image(systemName: emergency ? "exclamationmark.triangle.fill" : "star.fill")
                        .font(.system(size: 36, weight: .bold)).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.headline).labelStyle(tint)
                        HStack(spacing: 14) {
                            Text(alert.title).font(Theme.number(36, weight: .bold)).foregroundStyle(Theme.text)
                            Text(alert.detail).font(Theme.body(26)).foregroundStyle(Theme.secondary)
                        }
                    }
                    let d = units.distance(nm: alert.distanceNM)
                    Text("\(d.text)\(alert.onMap ? "" : " · off map")")
                        .font(Theme.number(28)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 30).padding(.vertical, 16)
                .glassCard(radius: 38, tint: tint.opacity(0.30))
            }
        }
    }
}
