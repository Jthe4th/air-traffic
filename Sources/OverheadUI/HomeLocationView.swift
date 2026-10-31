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
            ? "Location access is off for this app. Use your street address instead, or enable it in Settings."
            : "Couldn't determine this device's location. Try your street address instead."
        Task { @MainActor in self.state = .failed(message) }
    }
}

/// Where you live, and how exactly the app knows it. It has a page of its own because there are several ways to say it
/// and one that is clearly best: a street address, which is what makes the directions on a flyby card right.
struct HomeLocationView: View {
    @Bindable var engine: TrackingEngine

    @StateObject private var finder = LocationFinder()
    @State private var addressText = ""
    @State private var addressMatches: [AddressMatch] = []
    @State private var addressMessage: String?
    @State private var findingAddress = false
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searchState: String?
    @State private var searching = false
    @State private var coordinateText = ""
    @State private var coordinateMessage: String?
    @State private var saved: String?

    var body: some View {
        Form {
            statusSection
            addressSection
            deviceSection
            placeSection
            coordinatesSection
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Theme.ink.ignoresSafeArea())
        .navigationTitle("Home location")
        .onChange(of: finder.state) { _, state in
            if case .found(let point) = state { setHome(point, name: "Apple TV location", source: .device) }
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        let home = engine.settings.home
        let source = engine.settings.homeSource
        return Section {
            LabeledContent("Watching over", value: home == nil ? "Not set (demo traffic)" : engine.locationName)
            if home != nil, let source { LabeledContent("How exact", value: accuracyText(source)) }
            if let saved { Label(saved, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.climb) }
            if home == nil {
                Text("You are seeing demo traffic. Enter your street address below to see the real aircraft over your home.")
                    .foregroundStyle(.orange)
            } else if source?.isApproximate ?? true {
                Text("This is only approximate, so directions to a close flyby can be a mile or more off. Enter your street address below.")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Your home")
        } footer: {
            Text("Your location stays on this Apple TV. Aircraft data providers only ever see it rounded to roughly a mile.")
        }
    }

    private var addressSection: some View {
        Section {
            TextField("House number, street, town, state", text: $addressText)
                .onSubmit { Task { await findAddress() } }
            Button {
                Task { await findAddress() }
            } label: {
                Label(findingAddress ? "Finding…" : "Find this address", systemImage: "house.fill")
            }
            .disabled(addressText.trimmingCharacters(in: .whitespaces).count < 5 || findingAddress)
            if let addressMessage { Text(addressMessage).foregroundStyle(.secondary) }
            ForEach(addressMatches) { match in
                Button {
                    setHome(match.location, name: match.placeName, source: .address)
                } label: {
                    Text(match.address)
                }
            }
        } header: {
            Text("Street address · exact (best)")
        } footer: {
            Text("Looked up with Apple Maps, the only place it is sent. Only the point and your town are kept, so your house number never appears on screen.")
        }
    }

    private var deviceSection: some View {
        Section {
            Button {
                finder.request()
            } label: {
                Label("Use this Apple TV's location", systemImage: "location.fill")
            }
            if case .working = finder.state { Text("Finding location…").foregroundStyle(.secondary) }
            if case .failed(let message) = finder.state { Text(message).foregroundStyle(.orange) }
        } header: {
            Text("Or: this Apple TV's location · approximate")
        }
    }

    private var placeSection: some View {
        Section {
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
                    setHome(place.location, name: place.fullName, source: .place)
                } label: {
                    VStack(alignment: .leading) {
                        Text(place.name)
                        if !place.subtitle.isEmpty { Text(place.subtitle).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
        } header: {
            Text("Or: city or ZIP code · approximate")
        } footer: {
            Text("This lands in the middle of the place, which can be a mile or more from your home.")
        }
    }

    private var coordinatesSection: some View {
        Section {
            TextField("Latitude, longitude, e.g. 37.3349, -122.0090", text: $coordinateText)
                .onSubmit { applyCoordinates() }
            Button {
                applyCoordinates()
            } label: {
                Label("Use these coordinates", systemImage: "scope")
            }
            .disabled(coordinateText.trimmingCharacters(in: .whitespaces).isEmpty)
            if let coordinateMessage { Text(coordinateMessage).foregroundStyle(.orange) }
        } header: {
            Text("Or: coordinates · exact")
        } footer: {
            Text("Use a minus sign for west, or add W.")
        }
    }

    private func accuracyText(_ source: HomeSource) -> String {
        switch source {
        case .address: "Exact (street address)"
        case .coordinates: "Exact (coordinates)"
        case .place: "Approximate (city or ZIP centre)"
        case .device: "Approximate (the Apple TV's own location)"
        }
    }

    // MARK: Actions

    /// Saves the home, clears every field, and says so. The page stays open so the new status is right there.
    private func setHome(_ point: GeoPoint, name: String, source: HomeSource) {
        engine.settings.demoMode = false
        engine.settings.homeName = name
        engine.settings.homeSource = source
        engine.settings.home = point
        addressText = ""; addressMatches = []; addressMessage = nil
        query = ""; results = []; searchState = nil
        coordinateText = ""; coordinateMessage = nil
        saved = "Saved. Watching over \(name)."
    }

    private func findAddress() async {
        findingAddress = true; addressMessage = nil; addressMatches = []; saved = nil
        defer { findingAddress = false }
        do {
            addressMatches = try await AddressSearch.find(addressText)
            if addressMatches.isEmpty { addressMessage = "No match. Include the house number, street, town and state." }
            else { addressMessage = "Choose your address:" }
        } catch {
            addressMessage = "Couldn't look that up. Check the network connection and try again."
        }
    }

    private func applyCoordinates() {
        guard let point = Coordinates.parse(coordinateText) else {
            coordinateMessage = "That doesn't look like a latitude and longitude. Try 37.3349, -122.0090."
            return
        }
        setHome(point, name: Coordinates.format(point), source: .coordinates)
    }

    private func search() async {
        searching = true; searchState = nil; saved = nil
        defer { searching = false }
        do {
            results = try await PlaceSearch.search(query)
            if results.isEmpty { searchState = "No matches. Try a nearby city, or a ZIP code." }
        } catch {
            searchState = "Search failed. Check the network connection."
        }
    }
}
