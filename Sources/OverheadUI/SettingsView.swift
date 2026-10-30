import SwiftUI
import CoreLocation
import OverheadKit

@MainActor
final class LocationFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle, working, found(GeoPoint), failed(String)
    }

    @Published var state: State = .idle
    private let manager = CLLocationManager()

    func request() {
        state = .working
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let point = GeoPoint(latitude: l.coordinate.latitude, longitude: l.coordinate.longitude)
        Task { @MainActor in self.state = .found(point) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = (error as? CLError)?.code == .denied
            ? "Location access is off for this app. Use search instead, or enable it in Settings."
            : "Couldn't determine this device's location. Try searching for your city or ZIP code."
        Task { @MainActor in self.state = .failed(message) }
    }
}

struct SettingsView: View {
    @Bindable var engine: TrackingEngine
    @Environment(\.dismiss) private var dismiss

    @StateObject private var finder = LocationFinder()
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searchState: String?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            Form {
                locationSection
                displaySection
                dataSection
                photosSection
                diagnosticsSection
                aboutSection
                Section { Button("Done") { dismiss() } }
            }
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        // Opaque: the cover otherwise lets the dashboard show through the form.
        .background(Theme.ink.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: finder.state) { _, state in
            if case .found(let point) = state { setHome(point, name: "Apple TV location") }
        }
    }

    // MARK: Sections

    private var locationSection: some View {
        Section {
            LabeledContent("Watching over", value: engine.settings.home == nil ? "Not set (demo traffic)" : engine.locationName)

            Button {
                finder.request()
            } label: {
                Label("Use this device's location", systemImage: "location.fill")
            }
            if case .working = finder.state { Text("Finding location…").foregroundStyle(.secondary) }
            if case .failed(let message) = finder.state { Text(message).foregroundStyle(.orange) }

            TextField("City, State or ZIP code", text: $query)
                .onSubmit { Task { await search() } }
            Button {
                Task { await search() }
            } label: {
                Label(searching ? "Searching…" : "Search", systemImage: "magnifyingglass")
            }
            .disabled(query.trimmingCharacters(in: .whitespaces).count < 2 || searching)
            if let searchState { Text(searchState).foregroundStyle(.secondary) }
            ForEach(results) { place in
                Button {
                    setHome(place.location, name: place.fullName)
                    results = []; query = ""; searchState = nil
                } label: {
                    VStack(alignment: .leading) {
                        Text(place.name)
                        if !place.subtitle.isEmpty { Text(place.subtitle).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
        } header: {
            Text("Location")
        } footer: {
            Text("Your location stays on this device. Data providers only ever see it rounded to roughly a mile.")
        }
    }

    private var displaySection: some View {
        let unit = engine.settings.units.distance(nm: 1).unit
        return Section("Display") {
            Picker("Map radius", selection: presetBinding(\.mapRadiusNM, presets: mapPresets)) {
                ForEach(mapPresets, id: \.self) { Text("\(Int($0)) \(unit)").tag($0) }
            }
            Picker("Overhead zone", selection: presetBinding(\.alertRadiusNM, presets: alertPresets)) {
                ForEach(alertPresets, id: \.self) { Text("\(Int($0)) \(unit)").tag($0) }
            }
            Picker("Units", selection: $engine.settings.units) {
                ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
            }
            Picker("Hide controls when idle", selection: $engine.settings.idleHideSeconds) {
                Text("Never").tag(0.0)
                ForEach([10.0, 15, 30, 60], id: \.self) { Text("After \(Int($0)) seconds").tag($0) }
            }
            Toggle("Dim at night (10 PM to 6 AM)", isOn: $engine.settings.nightDimming)
            Toggle("Flight trails", isOn: $engine.settings.showTrails)
            Toggle("Rotate through aircraft overhead", isOn: $engine.settings.autoCycle)
        }
    }

    private var dataSection: some View {
        Section {
            Picker("Aircraft data", selection: $engine.settings.feed) {
                ForEach(FeedProvider.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Use the other provider if this one fails", isOn: $engine.settings.autoFailover)
            Picker("Alerts", selection: $engine.settings.alertLevel) {
                ForEach(AlertLevel.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Demo mode (fictional traffic)", isOn: $engine.settings.demoMode)
        } header: {
            Text("Data")
        } footer: {
            Text("Both providers share volunteer ADS-B receiver data. If one is slow or down, try the other.")
        }
    }

    private var photosSection: some View {
        let typed = engine.settings.photoContact.trimmingCharacters(in: .whitespaces)
        let valid = ClientIdentity.sanitize(typed) != nil
        return Section {
            TextField("Contact email or website", text: $engine.settings.photoContact)
            if !typed.isEmpty && !valid {
                Text("That doesn't look like an email address or web address yet.").foregroundStyle(.orange)
            }
            LabeledContent("Aircraft photos", value: (valid || (typed.isEmpty && ClientIdentity.defaultContact != nil)) ? "On" : "Off")
        } header: {
            Text("Aircraft photos")
        } footer: {
            Text("Planespotters asks apps to identify a contact. It is sent only to Planespotters, never to the map or flight-data services. Leave blank to use this app's built-in contact, if it has one.")
        }
    }

    private var diagnosticsSection: some View {
        let d = engine.diagnostics
        return Section {
            LabeledContent("Data source", value: engine.sourceName)
            LabeledContent("Last update") {
                if let last = d.lastSuccess { Text(last, style: .relative) + Text(" ago") } else { Text("None yet") }
            }
            LabeledContent("Response time", value: d.lastLatencyMs.map { "\($0) ms" } ?? "n/a")
            LabeledContent("Aircraft in last response", value: d.lastAircraftCount.map(String.init) ?? "n/a")
            LabeledContent("Requests", value: "\(d.successes) succeeded, \(d.failures) failed")
            if let error = d.lastError { LabeledContent("Last error", value: error) }
            LabeledContent("Running for") { Text(d.startedAt, style: .relative) }
        } header: {
            Text("Connection")
        } footer: {
            Text("Useful when something looks wrong: it shows which provider is answering and how recently.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: AppVersion.build.map { "\(AppVersion.display) (\($0))" } ?? AppVersion.display)
            Text("Positions: adsb.fi and adsb.lol. Routes: ADSB.lol standing data. Photos: Planespotters.net (photographers credited on each photo). Maps: \(MapStyle.attribution).")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Radius presets (round numbers in whichever units the viewer reads)

    private var perNM: Double {
        switch engine.settings.units {
        case .imperial: Geo.milesPerNM
        case .metric: Geo.kmPerNM
        case .aviation: 1
        }
    }

    private var mapPresets: [Double] { MapZoom.presets(for: engine.settings.units) }

    private var alertPresets: [Double] {
        switch engine.settings.units {
        case .imperial: [3, 5, 8, 12]
        case .metric: [5, 8, 12, 20]
        case .aviation: [2, 4, 6, 10]
        }
    }

    private func presetBinding(_ keyPath: WritableKeyPath<AppSettings, Double>, presets: [Double]) -> Binding<Double> {
        Binding(
            get: {
                let current = engine.settings[keyPath: keyPath] * perNM
                return presets.min { abs($0 - current) < abs($1 - current) } ?? presets[0]
            },
            set: { engine.settings[keyPath: keyPath] = $0 / perNM })
    }

    // MARK: Actions

    private func setHome(_ point: GeoPoint, name: String) {
        engine.settings.demoMode = false
        engine.settings.homeName = name
        engine.settings.home = point
        dismiss()
    }

    private func search() async {
        searching = true; searchState = nil
        defer { searching = false }
        do {
            results = try await PlaceSearch.search(query)
            if results.isEmpty { searchState = "No matches. Try a nearby city, or a ZIP code." }
        } catch {
            searchState = "Search failed. Check the network connection."
        }
    }
}
