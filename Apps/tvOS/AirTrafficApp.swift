import SwiftUI
import UIKit
import OverheadKit
import OverheadUI

@main
struct AirTrafficApp: App {
    @State private var engine = TrackingEngine()

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            guard let s = info[key] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return s
        }
        ClientIdentity.defaultContact = value("ATContact")
        MapStyle.templateOverride = value("ATTileURLTemplate")
        MapStyle.attributionOverride = value("ATTileAttribution")
    }

    var body: some Scene {
        WindowGroup {
            TVDashboardView(engine: engine)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
