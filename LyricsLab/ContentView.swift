// ContentView.swift

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(for: [Composition.self, UserLexiconEntry.self, CompositionLexiconState.self], inMemory: true)
            .environmentObject(ThemeManager())
    }
}
