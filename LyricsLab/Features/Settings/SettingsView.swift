import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("icloudSyncEnabled") private var iCloudSyncEnabled = true

    @State private var showingRestartAlert = false

    #if DEBUG
    @AppStorage("bypassIAP") private var bypassIAP = false
    #endif

    var body: some View {
        ZStack {
            themeManager.theme.backgroundGradient
                .ignoresSafeArea()

            List {
                Section("Themes") {
                    Picker("Theme", selection: Binding(get: {
                        themeManager.themeID
                    }, set: { newValue in
                        themeManager.themeID = newValue
                    })) {
                        ForEach(ThemeID.allCases) { id in
                            Text(AppTheme.forID(id).displayName)
                                .tag(id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Toggle("iCloud Sync", isOn: $iCloudSyncEnabled)
                        .onChange(of: iCloudSyncEnabled) {
                            showingRestartAlert = true
                        }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Changes apply after restarting the app. Turning sync off does not delete local data.")
                }

                #if DEBUG
                Section("Developer") {
                    Toggle("Bypass IAP", isOn: $bypassIAP)
                }
                #endif
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .alert("Restart Required", isPresented: $showingRestartAlert) {
            Button("OK") {}
        } message: {
            Text("Restart LyricsLab to apply your iCloud Sync setting.")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
        }
        .environmentObject(ThemeManager())
    }
}
