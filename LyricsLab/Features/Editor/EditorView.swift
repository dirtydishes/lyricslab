import SwiftUI
import SwiftData
import Foundation

struct EditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var composition: Composition

    @EnvironmentObject private var themeManager: ThemeManager

    @State private var lyricsSelectedRange = NSRange(location: 0, length: 0)
    @State private var isLyricsFocused = false
    @State private var autosaveTask: Task<Void, Never>?

    @State private var rhymeTask: Task<Void, Never>?
    @State private var rhymeAnalysis: RhymeAnalysis = .empty

    @State private var warmUpTask: Task<Void, Never>?
    @State private var rhymeServiceReady = false

    @State private var suggestionsTask: Task<Void, Never>?

    @State private var suggestions: [String] = []
    @State private var barPosition: BarPosition?

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

                #if canImport(UIKit)
                EditorTextViewControllerRepresentable(
                    text: $composition.lyrics,
                    selectedRange: $lyricsSelectedRange,
                    isFocused: $isLyricsFocused,
                    endRhymeTailLength: $composition.endRhymeTailLength,
                    highlights: textHighlights,
                    suggestions: suggestions,
                    isLoadingSuggestions: !rhymeServiceReady,
                    barPosition: barPosition,
                    onSuggestionAccepted: { word in
                        recordSuggestionAcceptance(word)
                    },
                    preferredColorScheme: themeManager.theme.colorScheme,
                    preferredTextColor: themeManager.theme.textPrimary,
                    preferredTintColor: themeManager.theme.accent
                )
                #else
                LyricsTextView(
                    text: $composition.lyrics,
                    selectedRange: $lyricsSelectedRange,
                    insertion: .constant(nil),
                    isFocused: $isLyricsFocused,
                    highlights: textHighlights,
                    preferredColorScheme: themeManager.theme.colorScheme,
                    preferredTextColor: themeManager.theme.textPrimary,
                    preferredTintColor: themeManager.theme.accent
                ) {
                    EmptyView()
                }

                EditorSuggestionsBar(
                    suggestions: suggestions,
                    isLoading: !rhymeServiceReady,
                    barPosition: barPosition,
                    endRhymeTailLength: composition.endRhymeTailLength,
                    onSetEndRhymeTailLength: { next in
                        let clamped = max(1, min(2, next))
                        if composition.endRhymeTailLength != clamped {
                            composition.endRhymeTailLength = clamped
                            try? modelContext.save()
                        }
                    }
                ) { word in
                    insertSuggestionFallback(word)
                    recordSuggestionAcceptance(word)
                }
                #endif
            }
        }
        .navigationTitle(composition.title.isEmpty ? "Untitled" : composition.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            composition.lastOpenedAt = Date()
            isLyricsFocused = true

            ensureCompositionLexiconState()

            warmUpTask?.cancel()
            warmUpTask = Task {
                await RhymeService.shared.warmUp()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    rhymeServiceReady = true
                }
            }

            scheduleRhymeAnalysis()
            refreshAssist()
        }
        .onChange(of: composition.title) {
            scheduleAutosave()
        }
        .onChange(of: composition.lyrics) {
            scheduleAutosave()
            scheduleRhymeAnalysis()
            refreshAssist()
        }
        .onChange(of: composition.endRhymeTailLength) {
            // End-rhyme tail length affects both highlights (end groups) and suggestion targeting.
            scheduleAutosave()
            scheduleRhymeAnalysis()
            refreshAssist()
        }
        .onChange(of: lyricsSelectedRange) {
            refreshAssist()
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
            let tailLength = await MainActor.run { max(1, min(2, composition.endRhymeTailLength)) }
            let analysis = await RhymeService.shared.analyze(text: snapshot, endRhymeTailLength: tailLength)

            guard !Task.isCancelled else { return }
            await MainActor.run {
                rhymeAnalysis = analysis
                rhymeServiceReady = true
            }
        }
    }

    private func refreshAssist() {
        suggestionsTask?.cancel()

        let textSnapshot = composition.lyrics
        let cursorSnapshot = lyricsSelectedRange.location
        let tailLengthSnapshot = max(1, min(2, composition.endRhymeTailLength))

        // Snapshot the lexicon on the main actor (SwiftData), then compute assist off-main.
        let lexiconSnapshot = UserLexiconStore.fetchTopUserLexiconItems(in: modelContext, limit: 512)

        suggestionsTask = Task {
            let result = await RhymeService.shared.editorAssist(
                text: textSnapshot,
                cursorLocation: cursorSnapshot,
                userLexicon: lexiconSnapshot,
                endRhymeTailLength: tailLengthSnapshot,
                maxCount: 12
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestions = result.suggestions
                barPosition = result.barPosition
                rhymeServiceReady = true
            }
        }
    }

    private func ensureCompositionLexiconState() {
        guard composition.lexiconState == nil else { return }

        let state = CompositionLexiconState(composition: composition)
        composition.lexiconState = state
        modelContext.insert(state)
        try? modelContext.save()
    }

    private func recordSuggestionAcceptance(_ word: String) {
        UserLexiconStore.recordAcceptedWord(word, in: modelContext)
        try? modelContext.save()
    }

    private func insertSuggestionFallback(_ word: String) {
        let needsSpace: Bool
        if let last = composition.lyrics.unicodeScalars.last {
            needsSpace = !CharacterSet.whitespacesAndNewlines.contains(last)
        } else {
            needsSpace = true
        }

        composition.lyrics += word
        if needsSpace {
            composition.lyrics += " "
        }
        isLyricsFocused = true
    }

    private var textHighlights: [TextHighlight] {
        struct RangeKey: Hashable {
            var location: Int
            var length: Int
        }

        func precedence(for style: TextHighlight.Style) -> Int {
            switch style {
            case .end: return 3
            case .internal: return 2
            case .near: return 1
            }
        }

        let palette = themeManager.theme.highlightPalette
        guard !palette.isEmpty else { return [] }

        var best: [RangeKey: TextHighlight] = [:]
        best.reserveCapacity(rhymeAnalysis.groups.reduce(into: 0) { $0 += $1.occurrences.count })

        for group in rhymeAnalysis.groups {
            let c = palette[group.colorIndex % palette.count]
            for occ in group.occurrences {
                let style: TextHighlight.Style
                switch group.type {
                case .near:
                    style = .near
                case .end, .`internal`:
                    style = occ.isLineFinalToken ? .end : .internal
                }

                let key = RangeKey(location: occ.range.location, length: occ.range.length)

                #if canImport(UIKit)
                let candidate = TextHighlight(range: occ.range, style: style, color: UIColor(c))
                #else
                let candidate = TextHighlight(range: occ.range, style: style, color: c)
                #endif

                if let existing = best[key] {
                    if precedence(for: candidate.style) > precedence(for: existing.style) {
                        best[key] = candidate
                    }
                } else {
                    best[key] = candidate
                }
            }
        }

        return best.values.sorted { $0.range.location < $1.range.location }
    }
}

struct EditorView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EditorView(composition: Composition(title: "Draft", lyrics: "Hello\nWorld"))
        }
        .modelContainer(for: [Composition.self, UserLexiconEntry.self, CompositionLexiconState.self], inMemory: true)
        .environmentObject(ThemeManager())
    }
}
