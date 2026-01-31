import Foundation

actor RhymeService {
    static let shared = RhymeService()

    private let dictionaryTask: Task<CMUDictionary, Never>
    private var hasLoadedDictionary = false

    // Local-only suggestion recency to reduce repeats across keystrokes.
    private var suggestionTick: Int = 0
    private var lastSuggestedTickByWord: [String: Int] = [:]

    init() {
        dictionaryTask = Task.detached(priority: .utility) {
            let cached = CMUDictionaryStore.loadCachedIndex()
            if let cached, cached.version == CMUDictionaryIndex.currentVersion {
                return CMUDictionary(
                    wordToRhymeKeys: cached.wordToKeys,
                    rhymeKeyToWords: cached.keyToWords,
                    vowelGroupToKeys: cached.vowelGroupToKeys,
                    vowelGroupConsonantClassToKeys: cached.vowelGroupConsonantClassToKeys,
                    wordToSyllableCount: cached.wordToSyllables
                )
            }

            let text = CMUDictionary.loadBundledOrSampleText()
            let index = CMUDictionary.parseIndex(text: text)
            CMUDictionaryStore.saveCachedIndex(index)
            return CMUDictionary(
                wordToRhymeKeys: index.wordToKeys,
                rhymeKeyToWords: index.keyToWords,
                vowelGroupToKeys: index.vowelGroupToKeys,
                vowelGroupConsonantClassToKeys: index.vowelGroupConsonantClassToKeys,
                wordToSyllableCount: index.wordToSyllables
            )
        }
    }

    func editorAssist(
        text: String,
        cursorLocation: Int,
        userLexicon: [UserLexiconItem],
        maxCount: Int = 12
    ) async -> RhymeEditorAssistResult {
        let dict = await dictionaryTask.value
        hasLoadedDictionary = true

        let targetKey = inferTargetKey(text: text, cursorLocation: cursorLocation, dictionary: dict)
        let suggestions: [String]
        if let targetKey {
            suggestions = makeSuggestions(
                targetKey: targetKey,
                text: text,
                cursorLocation: cursorLocation,
                userLexicon: userLexicon,
                maxSuggestions: maxCount,
                dictionary: dict
            )
        } else {
            suggestions = []
        }

        let barPosition = computeBarPosition(text: text, cursorLocation: cursorLocation, dictionary: dict)
        return RhymeEditorAssistResult(suggestions: suggestions, barPosition: barPosition)
    }

    func warmUp() async {
        _ = await dictionaryTask.value
        hasLoadedDictionary = true
    }

    func isReady() -> Bool {
        hasLoadedDictionary
    }

    func analyze(text: String) async -> RhymeAnalysis {
        let dict = await dictionaryTask.value
        hasLoadedDictionary = true
        return RhymeAnalyzer.analyze(text: text, dictionary: dict)
    }

    func suggestions(
        text: String,
        cursorLocation: Int,
        userLexicon: [UserLexiconItem],
        maxCount: Int = 12
    ) async -> [String] {
        let result = await editorAssist(text: text, cursorLocation: cursorLocation, userLexicon: userLexicon, maxCount: maxCount)
        return result.suggestions
    }

    func suggestions(text: String, cursorLocation: Int, maxCount: Int = 12) async -> [String] {
        await suggestions(text: text, cursorLocation: cursorLocation, userLexicon: [], maxCount: maxCount)
    }

    private func inferTargetKey(text: String, cursorLocation: Int, dictionary: CMUDictionary) -> String? {
        let schemeKey = RhymeAnalyzer.inferActiveRhymeKey(
            text: text,
            cursor: cursorLocation,
            dictionary: dictionary,
            lookbackLines: 4
        )

        if RhymeAnalyzer.isCursorMidLine(text: text, cursor: cursorLocation),
           let internalKey = RhymeAnalyzer.lastCompletedTokenRhymeKey(text: text, cursor: cursorLocation, dictionary: dictionary) {
            return internalKey
        }

        return schemeKey
    }

    private func makeSuggestions(
        targetKey: String,
        text: String,
        cursorLocation: Int,
        userLexicon: [UserLexiconItem],
        maxSuggestions: Int,
        dictionary: CMUDictionary
    ) -> [String] {
        struct Candidate {
            var normalized: String
            var display: String
            var key: String
            var rhymeScore: Double
            var personalScore: Double
            var recencyPenalty: Double
            var usedInTextPenalty: Double
            var qualityScore: Double

            var score: Double {
                // Simple, debuggable scoring. Keep rhyme as the dominant signal.
                (0.70 * rhymeScore)
                    + (0.22 * personalScore)
                    + (0.08 * qualityScore)
                    - (0.30 * recencyPenalty)
                    - (0.22 * usedInTextPenalty)
            }
        }

        // Words used near the cursor should be down-ranked to reduce repetition.
        let recentWords = recentNormalizedWords(text: text, cursorLocation: cursorLocation, maxLines: 8)

        suggestionTick &+= 1
        let nowTick = suggestionTick

        func personalScore(forAcceptCount n: Int) -> Double {
            guard n > 0 else { return 0.0 }
            let capped = min(n, 40)
            let x = log(Double(1 + capped)) / log(41.0)
            return min(1.0, max(0.0, x))
        }

        func recencyPenalty(forNormalized normalized: String) -> Double {
            guard let last = lastSuggestedTickByWord[normalized] else { return 0.0 }
            let delta = max(0, nowTick - last)
            let window = 80
            if delta >= window { return 0.0 }
            return Double(window - delta) / Double(window)
        }

        func usedInTextPenalty(forNormalized normalized: String) -> Double {
            recentWords.contains(normalized) ? 0.85 : 0.0
        }

        func qualityScore(forDisplay display: String) -> Double {
            // Tiny heuristic: prefer short-ish alphabetic tokens.
            let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 2 { return 0.0 }
            if trimmed.count > 14 { return 0.2 }
            let lettersOnly = trimmed.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
            return lettersOnly ? 1.0 : 0.45
        }

        func lemmaKey(forNormalized w: String) -> String {
            var s = w
            if s.hasSuffix("'s") { s = String(s.dropLast(2)) }
            if s.hasSuffix("ing"), s.count > 5 { s = String(s.dropLast(3)) }
            if s.hasSuffix("ed"), s.count > 4 { s = String(s.dropLast(2)) }
            if s.hasSuffix("s"), s.count > 4 { s = String(s.dropLast(1)) }
            return s
        }

        var candidates: [String: Candidate] = [:]
        candidates.reserveCapacity(2048)

        // 1) Exact candidates from CMU dict.
        for w in dictionary.words(forRhymeKey: targetKey).prefix(600) {
            let normalized = w
            let c = Candidate(
                normalized: normalized,
                display: w,
                key: targetKey,
                rhymeScore: 1.0,
                personalScore: 0.0,
                recencyPenalty: recencyPenalty(forNormalized: normalized),
                usedInTextPenalty: usedInTextPenalty(forNormalized: normalized),
                qualityScore: qualityScore(forDisplay: w)
            )
            candidates[normalized] = c
        }

        // 2) Near candidates from bucketed nearby keys.
        let nearKeys = dictionary.nearbyRhymeKeys(to: targetKey, limit: 28)
        for k in nearKeys {
            let sim = RhymeKey.similarity(targetKey, k)
            for w in dictionary.words(forRhymeKey: k).prefix(4) {
                let normalized = w
                if let existing = candidates[normalized], existing.rhymeScore >= sim {
                    continue
                }
                candidates[normalized] = Candidate(
                    normalized: normalized,
                    display: w,
                    key: k,
                    rhymeScore: sim,
                    personalScore: 0.0,
                    recencyPenalty: recencyPenalty(forNormalized: normalized),
                    usedInTextPenalty: usedInTextPenalty(forNormalized: normalized),
                    qualityScore: qualityScore(forDisplay: w)
                )
            }
        }

        // 3) Merge user lexicon candidates (global; already accepted/used by the user).
        for item in userLexicon {
            let keys = dictionary.rhymeKeys(for: item.normalized)
            if keys.isEmpty {
                continue
            }

            var bestKey: String?
            var bestSim: Double = 0.0
            for k in keys {
                let sim = (k == targetKey) ? 1.0 : RhymeKey.similarity(targetKey, k)
                if sim > bestSim {
                    bestSim = sim
                    bestKey = k
                }
            }

            // Hard gate: must be exact or a high-quality near rhyme.
            if bestSim < RhymeKey.nearRhymeThreshold {
                continue
            }

            let normalized = item.normalized
            let personal = personalScore(forAcceptCount: item.acceptCount)

            if var existing = candidates[normalized] {
                existing.personalScore = max(existing.personalScore, personal)
                // Prefer stronger rhyme match if the user word is a better fit.
                if bestSim > existing.rhymeScore {
                    existing.rhymeScore = bestSim
                    existing.key = bestKey ?? existing.key
                }
                if item.display != existing.display {
                    existing.display = item.display
                }
                candidates[normalized] = existing
            } else {
                candidates[normalized] = Candidate(
                    normalized: normalized,
                    display: item.display,
                    key: bestKey ?? targetKey,
                    rhymeScore: bestSim,
                    personalScore: personal,
                    recencyPenalty: recencyPenalty(forNormalized: normalized),
                    usedInTextPenalty: usedInTextPenalty(forNormalized: normalized),
                    qualityScore: qualityScore(forDisplay: item.display)
                )
            }
        }

        // Sort and apply diversity caps.
        let sorted = candidates.values.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.rhymeScore != b.rhymeScore { return a.rhymeScore > b.rhymeScore }
            if a.personalScore != b.personalScore { return a.personalScore > b.personalScore }
            return a.display < b.display
        }

        var out: [String] = []
        out.reserveCapacity(maxSuggestions)

        var usedLemmas: Set<String> = []
        var countByKey: [String: Int] = [:]

        for c in sorted {
            if out.count >= maxSuggestions { break }

            let lemma = lemmaKey(forNormalized: c.normalized)
            if !lemma.isEmpty, usedLemmas.contains(lemma) {
                continue
            }

            let keyCount = countByKey[c.key, default: 0]
            if keyCount >= 2 {
                continue
            }

            usedLemmas.insert(lemma)
            countByKey[c.key] = keyCount + 1
            out.append(c.display)
        }

        // Update local recency based on what we actually returned.
        for w in out {
            let normalized = CMUDictionary.normalizeWord(w)
            if !normalized.isEmpty {
                lastSuggestedTickByWord[normalized] = nowTick
            }
        }

        return out
    }

    private func recentNormalizedWords(text: String, cursorLocation: Int, maxLines: Int) -> Set<String> {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return [] }

        let clamped = max(0, min(cursorLocation, ns.length))

        var lineRanges: [NSRange] = []
        lineRanges.reserveCapacity(64)

        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            lineRanges.append(lineRange)
        }

        let currentLineIndex = lineRanges.lastIndex(where: { NSLocationInRange(clamped, $0) || (clamped == ns.length && NSMaxRange($0) == ns.length) })
        guard let currentLineIndex else { return [] }

        let start = max(0, currentLineIndex - maxLines + 1)
        let scoped = lineRanges[start...currentLineIndex]
            .map { ns.substring(with: $0) }
            .joined(separator: "\n")

        let tokens = LyricsTokenizer.tokenize(scoped)
        var out: Set<String> = []
        out.reserveCapacity(tokens.count)
        for t in tokens {
            if let n = t.normalizedCandidates.first {
                out.insert(n)
            }
        }
        return out
    }

    private func computeBarPosition(text: String, cursorLocation: Int, dictionary: CMUDictionary) -> BarPosition? {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return nil }

        let clamped = max(0, min(cursorLocation, ns.length))

        var lineRangeAtCursor: NSRange?
        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, stop in
            if NSLocationInRange(clamped, lineRange) || (clamped == ns.length && NSMaxRange(lineRange) == ns.length) {
                lineRangeAtCursor = lineRange
                stop.pointee = true
            }
        }

        guard let lineRange = lineRangeAtCursor else { return nil }
        let lineText = ns.substring(with: lineRange)
        let lineNS = lineText as NSString

        let cursorInLine = max(0, min(clamped - lineRange.location, lineNS.length))

        let tokens = LyricsTokenizer.tokenize(lineText)
        guard !tokens.isEmpty else { return nil }

        let engine = SyllableEngine(dictionary: dictionary)
        var syllablesBefore = 0
        var total = 0
        var lowConfidence = 0

        for t in tokens {
            guard let res = engine.syllableCount(forToken: t.raw) else { continue }
            total += res.count
            if res.confidence < 0.99 {
                lowConfidence += 1
            }
            if NSMaxRange(t.rangeInString) <= cursorInLine {
                syllablesBefore += res.count
            }
        }

        guard total > 0 else { return nil }

        let pos = Double(syllablesBefore) / Double(max(1, total))
        let rawStep = Int((pos * 16.0).rounded())
        let step = min(15, max(0, rawStep))

        return BarPosition(
            step: step,
            syllablesBeforeCaret: syllablesBefore,
            totalSyllables: total,
            lowConfidenceTokenCount: lowConfidence
        )
    }
}
