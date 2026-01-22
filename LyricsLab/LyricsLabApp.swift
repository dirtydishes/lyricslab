// LyricsLabApp.swift

import SwiftUI
import SwiftData

@main
struct LyricsLabApp: App {
    @StateObject private var themeManager = ThemeManager()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            Composition.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
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
