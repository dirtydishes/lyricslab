import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Composition.updatedAt, order: .reverse) private var compositions: [Composition]

    @EnvironmentObject private var themeManager: ThemeManager

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var showingSettings = false
    @State private var gearRotation: Angle = .zero
    @State private var newComposition: Composition?

    private var filteredCompositions: [Composition] {
        let q = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return compositions }
        return compositions.filter { $0.searchBlob.contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.theme.backgroundGradient
                    .ignoresSafeArea()

                List {
                    ForEach(filteredCompositions) { composition in
                        NavigationLink {
                            EditorView(composition: composition)
                        } label: {
                            CompositionRow(composition: composition)
                        }
                        .listRowBackground(themeManager.theme.surface)
                    }
                    .onDelete(perform: delete)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("LyricsLab")
            .searchable(text: $searchText)
            .onAppear {
                debouncedSearchText = searchText
            }
            .onChange(of: searchText) {
                searchDebounceTask?.cancel()
                let snapshot = searchText
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        debouncedSearchText = snapshot
                    }
                }
            }
            .onDisappear {
                searchDebounceTask?.cancel()
                searchDebounceTask = nil
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            gearRotation += .degrees(240)
                        }
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .rotationEffect(gearRotation)
                    }
                    .accessibilityLabel("Settings")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createComposition()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Composition")
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                }
                .environmentObject(themeManager)
                .tint(themeManager.theme.accent)
            }
            .sheet(item: $newComposition) { composition in
                NavigationStack {
                    EditorView(composition: composition)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    newComposition = nil
                                }
                            }
                        }
                }
                .environmentObject(themeManager)
                .tint(themeManager.theme.accent)
            }
        }
    }

    private func createComposition() {
        let composition = Composition(title: "Untitled")
        modelContext.insert(composition)
        newComposition = composition
    }

    private func delete(_ indexSet: IndexSet) {
        let items = filteredCompositions
        for index in indexSet {
            guard items.indices.contains(index) else { continue }
            modelContext.delete(items[index])
        }
    }
}

private struct CompositionRow: View {
    let composition: Composition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(composition.title.isEmpty ? "Untitled" : composition.title)
                .font(.headline)

            if let snippet = snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var snippet: String? {
        let lines = composition.lyrics
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return lines.first(where: { !$0.isEmpty })
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
            .modelContainer(for: Composition.self, inMemory: true)
            .environmentObject(ThemeManager())
    }
}
