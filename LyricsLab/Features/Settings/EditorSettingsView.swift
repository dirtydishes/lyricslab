import SwiftUI

struct EditorSettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager

    @AppStorage(EditorPreferenceKeys.textAlignment) private var editorTextAlignmentRaw: String = EditorTextAlignment.left.rawValue
    @AppStorage(EditorPreferenceKeys.ruledLinesEnabled) private var ruledLinesEnabled: Bool = false

    private var alignment: EditorTextAlignment {
        get { EditorTextAlignment(rawValue: editorTextAlignmentRaw) ?? .left }
        nonmutating set { editorTextAlignmentRaw = newValue.rawValue }
    }

    var body: some View {
        ZStack {
            themeManager.theme.backgroundGradient
                .ignoresSafeArea()

            List {
                Section("Text") {
                    Picker("Alignment", selection: Binding(get: {
                        alignment
                    }, set: { next in
                        alignment = next
                    })) {
                        ForEach(EditorTextAlignment.allCases) { a in
                            Text(a.displayName)
                                .tag(a)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Ruled Lines", isOn: $ruledLinesEnabled)
                } header: {
                    Text("Rules")
                } footer: {
                    Text("Adds subtle horizontal guidelines behind your lyrics.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Editor")
    }
}

struct EditorSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EditorSettingsView()
        }
        .environmentObject(ThemeManager())
    }
}
