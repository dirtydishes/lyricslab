import SwiftUI
import SwiftData
import Foundation

struct EditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var composition: Composition

    @EnvironmentObject private var themeManager: ThemeManager

    @State private var lyricsSelectedRange = NSRange(location: 0, length: 0)
    @State private var pendingInsertion: TextInsertion?
    @State private var isLyricsFocused = false
    @State private var autosaveTask: Task<Void, Never>?

    @State private var rhymeTask: Task<Void, Never>?
    @State private var rhymeAnalysis: RhymeAnalysis = .empty

    @State private var warmUpTask: Task<Void, Never>?
    @State private var rhymeServiceReady = false

    @State private var suggestionsTask: Task<Void, Never>?

    @State private var suggestions: [String] = []

    var body: some View {
        ZStack {
            themeManager.theme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 12) {
                TextField("Title", text: $composition.title)
                    .font(.title2.weight(.semibold))
                    #if os(iOS) || os(tvOS) || os(visionOS)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    #endif
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                Divider()
                    .opacity(0.5)

                LyricsTextView(
                    text: $composition.lyrics,
                    selectedRange: $lyricsSelectedRange,
                    insertion: $pendingInsertion,
                    isFocused: $isLyricsFocused,
                    highlights: textHighlights,
                    preferredColorScheme: themeManager.theme.colorScheme,
                    preferredTextColor: themeManager.theme.textPrimary,
                    preferredTintColor: themeManager.theme.accent
                ) {
                    EditorSuggestionsBar(suggestions: suggestions, isLoading: !rhymeServiceReady) { word in
                        pendingInsertion = TextInsertion(id: UUID(), text: word)
                    }
                }
            }
        }
        .navigationTitle(composition.title.isEmpty ? "Untitled" : composition.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            composition.lastOpenedAt = Date()
            isLyricsFocused = true

            warmUpTask?.cancel()
            warmUpTask = Task {
                await RhymeService.shared.warmUp()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    rhymeServiceReady = true
                }
            }

            scheduleRhymeAnalysis()
            refreshSuggestions()
        }
        .onChange(of: composition.title) {
            scheduleAutosave()
        }
        .onChange(of: composition.lyrics) {
            scheduleAutosave()
            scheduleRhymeAnalysis()
            refreshSuggestions()
        }
        .onChange(of: lyricsSelectedRange) {
            refreshSuggestions()
        }
        .onSubmit {
            isLyricsFocused = true
        }
        .onDisappear {
            autosaveTask?.cancel()
            autosaveTask = nil

            rhymeTask?.cancel()
            rhymeTask = nil

            suggestionsTask?.cancel()
            suggestionsTask = nil

            warmUpTask?.cancel()
            warmUpTask = nil

            composition.touch()
            do {
                try modelContext.save()
            } catch {
                // Keep silent for now; we can add user-visible error UI once the basics are stable.
            }
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [modelContext, composition] in
            try? await Task.sleep(for: .milliseconds(450))
            await MainActor.run {
                composition.touch()
                do {
                    try modelContext.save()
                } catch {
                    // Keep silent for now; we can add user-visible error UI once the basics are stable.
                }
            }
        }
    }

    private func scheduleRhymeAnalysis() {
        rhymeTask?.cancel()
        rhymeTask = Task {
            try? await Task.sleep(for: .milliseconds(325))

            let snapshot = await MainActor.run { composition.lyrics }

            let analysis = await RhymeService.shared.analyze(text: snapshot)

            guard !Task.isCancelled else { return }
            await MainActor.run {
                rhymeAnalysis = analysis
                rhymeServiceReady = true
            }
        }
    }

    private func refreshSuggestions() {
        suggestionsTask?.cancel()

        let textSnapshot = composition.lyrics
        let cursorSnapshot = lyricsSelectedRange.location
        suggestionsTask = Task {
            let next = await RhymeService.shared.suggestions(
                text: textSnapshot,
                cursorLocation: cursorSnapshot
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestions = next
                rhymeServiceReady = true
            }
        }
    }

    private var highlightPalette: [Color] {
        [
            themeManager.theme.accent,
            Color(red: 0.98, green: 0.55, blue: 0.37),
            Color(red: 0.98, green: 0.84, blue: 0.35),
            Color(red: 0.42, green: 0.90, blue: 0.55),
            Color(red: 0.38, green: 0.76, blue: 0.98),
            Color(red: 0.96, green: 0.46, blue: 0.82),
        ]
    }

    private var textHighlights: [TextHighlight] {
        var out: [TextHighlight] = []
        out.reserveCapacity(rhymeAnalysis.groups.reduce(into: 0) { $0 += $1.tokens.count })

        for (idx, group) in rhymeAnalysis.groups.enumerated() {
            let c = highlightPalette[idx % highlightPalette.count]
            for token in group.tokens {
                #if canImport(UIKit)
                out.append(TextHighlight(range: token.range, color: UIColor(c)))
                #else
                out.append(TextHighlight(range: token.range, color: c))
                #endif
            }
        }

        return out
    }
}

struct EditorView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EditorView(composition: Composition(title: "Draft", lyrics: "Hello\nWorld"))
        }
        .modelContainer(for: Composition.self, inMemory: true)
        .environmentObject(ThemeManager())
    }
}
