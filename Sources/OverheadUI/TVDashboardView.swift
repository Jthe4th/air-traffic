import SwiftUI
import OverheadKit
#if canImport(UIKit)
import UIKit
#endif

/// The whole living-room display, laid out on a 1920×1080 canvas and scaled to fit.
public struct TVDashboardView: View {
    @Bindable var engine: TrackingEngine
    @State private var showSettings = false
    @State private var ambient: Ambient
    @FocusState private var welcomeFocused: Bool
    @Environment(\.fixedNow) private var fixedNow

    static let canvas = CGSize(width: 1920, height: 1080)
    /// Where "home" sits on the canvas: centred in the space to the right of the aircraft card.
    static let mapCenter = CGPoint(x: 1352, y: 526)
    static let mapRadiusPoints: CGFloat = 372

    public init(engine: TrackingEngine, ambient: Ambient? = nil) {
        self.engine = engine
        _ambient = State(initialValue: ambient ?? Ambient())
    }

    public var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.canvas.width, geo.size.height / Self.canvas.height)
            canvasContent
                .offset(ambient.shift)
                .animation(.linear(duration: 1), value: ambient.shift)
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Theme.ink)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .environment(\.ambient, ambient)
        .onAppear {
            engine.start()
            if engine.needsLocation { welcomeFocused = true }
        }
        .task {
            while !Task.isCancelled {
                ambient.tick(now: Date(), idleAfter: engine.settings.idleHideSeconds, nightDimming: engine.settings.nightDimming,
                             keepControlsVisible: engine.needsLocation || showSettings)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: engine.settings.mapRadiusNM) { _, _ in ambient.touch() }
        .onChange(of: engine.pinned) { _, _ in ambient.touch() }
        .onChange(of: showSettings) { _, _ in ambient.touch() }
        #if canImport(UIKit)
        // Any remote movement (focus changing) counts as activity.
        .onReceive(NotificationCenter.default.publisher(for: UIFocusSystem.didUpdateNotification)) { _ in ambient.touch() }
        #endif
        #if os(tvOS)
        // A swipe or arrow press toward an edge moves no focus, so focus updates alone would miss it.
        .onMoveCommand { _ in ambient.touch() }
        .onPlayPauseCommand {
            if ambient.consumeWakeUp() { return }
            if engine.pinned { engine.unpin() } else if let id = engine.featuredID { engine.pin(id) }
        }
        // Menu steps back (unpins) and otherwise does nothing, so a stray press can't close an always-on
        // display. While Settings is open it is left to the sheet, which dismisses itself.
        .onExitCommand(perform: showSettings ? nil : { ambient.touch(); if engine.pinned { engine.unpin() } })
        #endif
        #if os(macOS)
        .sheet(isPresented: $showSettings) { SettingsView(engine: engine).frame(width: 900, height: 800) }
        #else
        .fullScreenCover(isPresented: $showSettings) { SettingsView(engine: engine).presentationBackground(Theme.ink) }
        #endif
    }

    public static func camera(for engine: TrackingEngine) -> MapCamera {
        MapCamera.fitting(radiusNM: engine.settings.mapRadiusNM, radiusPoints: mapRadiusPoints,
                          center: engine.home, size: canvas, anchor: mapCenter, tileZoomBias: MapStyle.tileZoomBias)
    }

    private var camera: MapCamera { Self.camera(for: engine) }

    private var canvasContent: some View {
        ZStack(alignment: .topLeading) {
            MapStage(engine: engine, camera: camera)
            vignettes

            leftColumn
                .padding(.leading, 80).padding(.top, 60)
                .animation(.easeInOut(duration: 0.55), value: engine.featuredID)

            VStack(spacing: 0) {
                HeaderBar(engine: engine, controlsHidden: ambient.controlsHidden) {
                    if ambient.consumeWakeUp() { return }
                    showSettings = true
                }
                Spacer(minLength: 0)
                NearbyStrip(engine: engine)
                    .opacity(ambient.controlsHidden ? 0 : 1)
            }
            .frame(width: 1000, height: 960)
            .offset(x: 840, y: 60)

            ZoomControls(engine: engine)
                .opacity(ambient.controlsHidden ? 0 : 1)
                .offset(x: 1750, y: 410)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                AlertBanner(alerts: engine.alerts(at: fixedNow ?? timeline.date), units: engine.settings.units)
            }
            .frame(width: 1000)
            .offset(x: 840, y: 206)

            Rectangle().fill(.black)
                .opacity(ambient.isNight ? 0.55 : 0)
                .allowsHitTesting(false)

            if engine.needsLocation {
                WelcomeCard(focus: $welcomeFocused) { showSettings = true }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(x: 330, y: 20)
            }
        }
    }

    @ViewBuilder private var leftColumn: some View {
        if let featured = engine.featured {
            DetailPanel(tracked: featured, home: engine.home, settings: engine.settings, pinned: engine.pinned)
                .id(featured.id)
                .transition(.opacity)
        } else {
            QuietSkiesCard(engine: engine)
                .transition(.opacity)
        }
    }

    private var vignettes: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black.opacity(0.82), location: 0), .init(color: .black.opacity(0.55), location: 0.34),
                                   .init(color: .clear, location: 0.52)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.black.opacity(0.62), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22))
            LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .bottom, endPoint: UnitPoint(x: 0.5, y: 0.74))
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: UnitPoint(x: 0.7, y: 0.49), startRadius: 520, endRadius: 1250)
        }
        .allowsHitTesting(false)
    }
}
