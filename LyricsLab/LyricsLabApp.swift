// LyricsLabApp.swift

import SwiftUI
import SwiftData

@main
struct LyricsLabApp: App {
    @StateObject private var themeManager = ThemeManager()

    private let modelContainer: ModelContainer = {
        do {
            return try PersistenceFactory.makeContainer(iCloudSyncEnabled: UserDefaults.standard.object(forKey: "icloudSyncEnabled") as? Bool ?? true)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .tint(themeManager.theme.accent)
                .preferredColorScheme(themeManager.theme.colorScheme)
        }
        .modelContainer(modelContainer)
    }
}
