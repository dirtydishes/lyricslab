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
                    highlights: textHighlights,
                    suggestions: suggestions,
                    isLoadingSuggestions: !rhymeServiceReady,
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

                EditorSuggestionsBar(suggestions: suggestions, isLoading: !rhymeServiceReady) { word in
                    insertSuggestionFallback(word)
                }
                #endif
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
        .modelContainer(for: Composition.self, inMemory: true)
        .environmentObject(ThemeManager())
    }
}
