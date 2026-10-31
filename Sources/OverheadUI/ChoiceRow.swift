import SwiftUI

/// A setting with a handful of choices. It opens a list page of its own: SwiftUI's built-in Picker page comes up blank on
/// tvOS inside the Settings screen.
struct ChoiceRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [(title: String, value: Value)]

    private var current: String { choices.first { $0.value == selection }?.title ?? "" }

    var body: some View {
        NavigationLink {
            ChoiceList(title: title, selection: $selection, choices: choices)
        } label: {
            LabeledContent(title, value: current)
        }
    }
}

private struct ChoiceList<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [(title: String, value: Value)]

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Int?

    var body: some View {
        Form {
            Section {
                ForEach(choices.indices, id: \.self) { i in
                    Button {
                        selection = choices[i].value
                        dismiss()
                    } label: {
                        HStack {
                            Text(choices[i].title)
                            Spacer()
                            if choices[i].value == selection { Image(systemName: "checkmark") }
                        }
                    }
                    .focused($focused, equals: i)
                }
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Theme.ink.ignoresSafeArea())
        .navigationTitle(title)
        // Start on the current choice, so one press of Select keeps it and a swipe moves from it.
        .onAppear { focused = choices.firstIndex { $0.value == selection } }
    }
}
