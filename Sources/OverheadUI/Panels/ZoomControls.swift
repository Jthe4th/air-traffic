import SwiftUI
import OverheadKit

/// Plus and minus for the map, with the current radius between them. Sits under the settings gear so
/// one swipe down from it lands on the plus.
struct ZoomControls: View {
    let engine: TrackingEngine

    var body: some View {
        let radius = MapZoom.label(radiusNM: engine.settings.mapRadiusNM, units: engine.settings.units)
        VStack(spacing: 8) {
            ZoomButton(symbol: "plus", enabled: engine.canZoomIn) { engine.zoomIn() }
            VStack(spacing: 0) {
                Text(radius.value).font(Theme.number(30)).foregroundStyle(Theme.text)
                Text(radius.unit).font(Theme.body(19)).foregroundStyle(Theme.tertiary)
            }
            .frame(height: 56)
            ZoomButton(symbol: "minus", enabled: engine.canZoomOut) { engine.zoomOut() }
        }
        .padding(10)
        .glassCard(radius: 45)
        #if !os(iOS)
        .focusSection()
        #endif
    }
}

private struct ZoomButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void
    @Environment(\.ambient) private var ambient

    var body: some View {
        // Stays focusable at the limits (just dimmed), so focus doesn't jump away when you hit the end.
        Button(action: {
            if ambient?.consumeWakeUp() == true { return }
            if enabled { action() }
        }) { Face(symbol: symbol, enabled: enabled) }
            .buttonStyle(FlatButtonStyle())
    }

    private struct Face: View {
        let symbol: String
        let enabled: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(isFocused ? Color.black : (enabled ? Theme.text : Theme.tertiary))
                .frame(width: 70, height: 70)
                .background(Circle().fill(isFocused ? Color.white : Color.white.opacity(enabled ? 0.12 : 0.05)))
                .scaleEffect(isFocused ? 1.12 : 1)
                .animation(.easeOut(duration: 0.18), value: isFocused)
        }
    }
}
