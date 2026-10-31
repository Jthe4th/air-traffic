import SwiftUI
import OverheadKit

/// What you call each side of the room ("Back door", "Kitchen window"). It keeps what you type to itself and saves when a
/// field is finished or the page closes, instead of writing every keystroke into the app's settings.
///
/// The names are read once, when the page is made, and never reloaded: the tvOS keyboard is a screen of its own, so this
/// page "disappears" and "reappears" around every field, and reloading then would overwrite what was just typed.
struct DirectionNamesView: View {
    let engine: TrackingEngine
    @State private var draft: DirectionNames

    init(engine: TrackingEngine) {
        self.engine = engine
        _draft = State(initialValue: engine.settings.directionNames)
    }

    var body: some View {
        Form {
            Section {
                ForEach(Sector.allCases) { sector in
                    TextField(prompt(sector), text: Binding(get: { draft[sector] }, set: { draft[sector] = $0 }))
                        .onSubmit { commit() }
                }
            } header: {
                Text("What do you call each side?")
            } footer: {
                Text("Name each side of the room the way you do, such as \"Back door\" or \"Kitchen window\". \"Ahead\" is past the TV, in the direction you face. Leave a side blank to use plain words like \"Behind you\".")
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Theme.ink.ignoresSafeArea())
        .navigationTitle("Names for the room")
        .onDisappear { commit() }
    }

    private func commit() {
        if engine.settings.directionNames != draft { engine.settings.directionNames = draft }
    }

    private func prompt(_ sector: Sector) -> String {
        switch sector {
        case .ahead: "Ahead, past the TV (e.g. Back yard)"
        case .right: "On your right (e.g. Side door)"
        case .behind: "Behind you (e.g. Front door)"
        case .left: "On your left (e.g. Garage)"
        }
    }

    /// "Back door, Side door" for the row that opens this page.
    static func summary(_ names: DirectionNames) -> String {
        let named = Sector.allCases.compactMap { names.name(for: $0) }
        return named.isEmpty ? "None yet" : named.joined(separator: ", ")
    }
}
