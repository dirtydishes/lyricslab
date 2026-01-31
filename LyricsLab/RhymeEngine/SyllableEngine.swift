import Foundation

nonisolated struct SyllableCountResult: Equatable, Sendable {
    var count: Int
    // 1.0 means dictionary-backed; <1.0 means heuristic.
    var confidence: Double
}

nonisolated struct SyllableEngine {
    var dictionary: CMUDictionary

    func syllableCount(forToken token: String) -> SyllableCountResult? {
        let candidates = LookupNormalization.normalizedCandidates(forLookup: token)
        for c in candidates {
            if let n = dictionary.syllableCount(for: c), n > 0 {
                return SyllableCountResult(count: n, confidence: 1.0)
            }
        }

        // Heuristic fallback.
        if let raw = candidates.first {
            if let n = Self.heuristicSyllableCount(raw), n > 0 {
                return SyllableCountResult(count: n, confidence: 0.35)
            }
        }

        return nil
    }

    private static func heuristicSyllableCount(_ word: String) -> Int? {
        let cleaned = word
            .lowercased()
            .trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
            .replacingOccurrences(of: "'", with: "")

        guard !cleaned.isEmpty else { return nil }

        // Count vowel groups.
        let vowels = Set(["a", "e", "i", "o", "u", "y"])
        var count = 0
        var prevWasVowel = false

        for ch in cleaned {
            let isVowel = vowels.contains(String(ch))
            if isVowel && !prevWasVowel {
                count += 1
            }
            prevWasVowel = isVowel
        }

        // Silent trailing 'e' (very rough).
        if cleaned.hasSuffix("e"), !cleaned.hasSuffix("le"), count > 1 {
            count -= 1
        }

        // "-le" ending after a consonant often adds a syllable (table, bottle).
        if cleaned.hasSuffix("le"), cleaned.count >= 3 {
            let idx = cleaned.index(cleaned.endIndex, offsetBy: -3)
            let before = cleaned[idx]
            let beforeIsVowel = vowels.contains(String(before))
            if !beforeIsVowel {
                count += 1
            }
        }

        return max(1, count)
    }
}
