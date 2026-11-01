import SwiftUI
import OverheadKit

struct SettingsView: View {
    @Bindable var engine: TrackingEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                locationSection
                displaySection
                flybySection
                stationSection
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
    }

    // MARK: Sections

    /// Unknown accuracy (a home saved by an older version) counts as approximate.
    private var homeIsApproximate: Bool { engine.settings.home != nil && (engine.settings.homeSource?.isApproximate ?? true) }

    private var locationSection: some View {
        Section {
            NavigationLink {
                HomeLocationView(engine: engine)
            } label: {
                LabeledContent("Home location", value: engine.settings.home == nil ? "Not set" : engine.locationName)
            }
        } header: {
            Text("Location")
        } footer: {
            if engine.settings.home == nil {
                Text("Not set, so demo traffic is showing. Open Home location to enter your street address.").foregroundStyle(.orange)
            } else if homeIsApproximate {
                Text("Only approximate: directions to a close flyby can be a mile or more off. Open Home location and enter your street address.").foregroundStyle(.orange)
            } else {
                Text("Exact. Open Home location to change it.")
            }
        }
    }


    private var displaySection: some View {
        let unit = engine.settings.units.distance(nm: 1).unit
        return Section("Display") {
            ChoiceRow(title: "Map radius", selection: presetBinding(\.mapRadiusNM, presets: mapPresets),
                      choices: mapPresets.map { ("\(Int($0)) \(unit)", $0) })
            ChoiceRow(title: "Overhead zone", selection: presetBinding(\.alertRadiusNM, presets: alertPresets),
                      choices: alertPresets.map { ("\(Int($0)) \(unit)", $0) })
            ChoiceRow(title: "Units", selection: $engine.settings.units, choices: UnitSystem.allCases.map { ($0.title, $0) })
            ChoiceRow(title: "Hide controls when idle", selection: $engine.settings.idleHideSeconds,
                      choices: [("Never", 0.0)] + [10.0, 15, 30, 60].map { ("After \(Int($0)) seconds", $0) })
            Toggle("Dim at night (10 PM to 6 AM)", isOn: $engine.settings.nightDimming)
            Toggle("Flight trails", isOn: $engine.settings.showTrails)
            Toggle("Rotate through aircraft overhead", isOn: $engine.settings.autoCycle)
        }
    }

    private var flybySection: some View {
        let units = engine.settings.units
        let unit = units.distance(nm: 1).unit
        return Section {
            if homeIsApproximate {
                NavigationLink {
                    HomeLocationView(engine: engine)
                } label: {
                    Label("Directions need your exact location. Set it here.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Toggle("Card for close flybys", isOn: $engine.settings.flybyCards)
            if engine.settings.flybyCards {
                ChoiceRow(title: "Counts as close", selection: presetBinding(\.flybyDistanceNM, presets: flybyPresets),
                          choices: flybyPresets.map { ("Within \(Int($0)) \(unit)", $0) })
                ChoiceRow(title: "Ignore aircraft above", selection: $engine.settings.flybyMaxAltitudeFt,
                          choices: [("Nothing (any altitude)", 0)] + [5_000, 10_000, 20_000, 30_000].map { (units.altitude(ft: Double($0)).text, $0) })
            }
            ChoiceRow(title: "When watching TV, I face", selection: $engine.settings.viewerHeadingDeg, choices: headingChoices)
            NavigationLink {
                DirectionNamesView(engine: engine)
            } label: {
                LabeledContent("Names for each side", value: DirectionNamesView.summary(engine.settings.directionNames))
            }
            Button {
                engine.showSampleFlyby()
                dismiss()
            } label: {
                Label("Show a sample card", systemImage: "airplane")
            }
        } header: {
            Text("Close flybys")
        } footer: {
            Text("A card says when an aircraft will pass close and which way to look.\n1. Enter your street address under Location above.\n2. Choose which way you face when you watch TV, from your seat toward the screen, so \"ahead\" is past the TV.\n3. Optionally name each side after a door or window.\nThen show the sample card: it shows a plane due north, so check it against a compass app.")
        }
    }

    private var stationSection: some View {
        let status = engine.stationStatus()
        return Section {
            Toggle("Watch for the Space Station", isOn: $engine.settings.issEnabled)
            if engine.settings.issEnabled {
                ChoiceRow(title: "Warn me", selection: $engine.settings.issLeadMinutes,
                          choices: AppSettings.issLeadChoices.map { ("\($0) minutes before", $0) })
                Toggle("Play a chime", isOn: $engine.settings.issChime)
                if case .demo = status {
                    Text("Set your location (above) to see when the Space Station passes over your home.").foregroundStyle(.orange)
                } else {
                    LabeledContent("Next visible pass", value: nextPassText(status))
                    LabeledContent("Orbit data", value: orbitDataText(status))
                }
                // Without a home the welcome card is on screen and would sit on top of the sample.
                if engine.settings.home != nil {
                    Button {
                        engine.showSampleStationPass()
                        dismiss()
                    } label: {
                        Label("Show a sample card", systemImage: "sparkles")
                    }
                }
            }
        } header: {
            Text("Space Station")
        } footer: {
            Text("A card appears before the Space Station crosses your sky after dark, with where to look, and a chime as it begins (silent while the screen is dimmed at night). Whenever it flies over your home, in daylight too, it shows on the map like an aircraft. Its orbit is downloaded from CelesTrak, which is told nothing about where you are.")
        }
    }

    private func nextPassText(_ status: StationStatus) -> String {
        switch status {
        case .ready:
            guard let pass = engine.nextStationPass() else { return "None in the next 10 days" }
            return StationPassCard.whenText(for: pass, now: Date())
        case .waiting: return "Waiting for orbit data"
        case .outdated: return "Orbit data too old"
        case .failed: return "Unavailable"
        case .off, .demo: return "n/a"
        }
    }

    private func orbitDataText(_ status: StationStatus) -> String {
        switch status {
        case .ready(let epoch): return "Current (from \(epoch.formatted(.dateTime.month(.abbreviated).day())))"
        case .outdated(let epoch): return "From \(epoch.formatted(.dateTime.month(.abbreviated).day())); needs a connection"
        case .waiting: return "Downloading…"
        case .failed(let message): return message
        case .off, .demo: return "n/a"
        }
    }

    private var headingChoices: [(title: String, value: Double?)] {
        [("Not set (use compass points)", nil)] + (0..<16).map { i in
            let degrees = Double(i) * 22.5
            return ("\(Geo.compassName(degrees).capitalized) (\(Geo.compass(degrees)))", degrees)
        }
    }

    private var flybyPresets: [Double] {
        switch engine.settings.units {
        case .imperial: [1, 2, 3, 5]
        case .metric: [2, 3, 5, 8]
        case .aviation: [1, 2, 3, 4]
        }
    }

    private var dataSection: some View {
        Section {
            ChoiceRow(title: "Aircraft data", selection: $engine.settings.feed, choices: FeedProvider.allCases.map { ($0.title, $0) })
            Toggle("Use the other provider if this one fails", isOn: $engine.settings.autoFailover)
            ChoiceRow(title: "Alerts", selection: $engine.settings.alertLevel, choices: AlertLevel.allCases.map { ($0.title, $0) })
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

}
