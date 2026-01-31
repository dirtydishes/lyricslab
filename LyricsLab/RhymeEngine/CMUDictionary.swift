import Foundation

nonisolated final class CMUDictionary {
    nonisolated private let wordToRhymeKeys: [String: [String]]
    nonisolated private let rhymeKeyToWords: [String: [String]]
    nonisolated private let vowelGroupToKeys: [String: [String]]
    nonisolated private let vowelGroupConsonantClassToKeys: [String: [String]]
    nonisolated private let wordToSyllableCount: [String: Int]

    nonisolated private let wordToTail2Keys: [String: [String]]
    nonisolated private let tail2KeyToWords: [String: [String]]
    nonisolated private let vowelGroupToTail2Keys: [String: [String]]
    nonisolated private let vowelGroupConsonantClassToTail2Keys: [String: [String]]

    init(
        wordToRhymeKeys: [String: [String]],
        rhymeKeyToWords: [String: [String]],
        vowelGroupToKeys: [String: [String]],
        vowelGroupConsonantClassToKeys: [String: [String]],
        wordToSyllableCount: [String: Int],
        wordToTail2Keys: [String: [String]],
        tail2KeyToWords: [String: [String]],
        vowelGroupToTail2Keys: [String: [String]],
        vowelGroupConsonantClassToTail2Keys: [String: [String]]
    ) {
        self.wordToRhymeKeys = wordToRhymeKeys
        self.rhymeKeyToWords = rhymeKeyToWords
        self.vowelGroupToKeys = vowelGroupToKeys
        self.vowelGroupConsonantClassToKeys = vowelGroupConsonantClassToKeys
        self.wordToSyllableCount = wordToSyllableCount

        self.wordToTail2Keys = wordToTail2Keys
        self.tail2KeyToWords = tail2KeyToWords
        self.vowelGroupToTail2Keys = vowelGroupToTail2Keys
        self.vowelGroupConsonantClassToTail2Keys = vowelGroupConsonantClassToTail2Keys
    }

    nonisolated func rhymeKeys(for rawWord: String) -> [String] {
        let word = Self.normalizeWord(rawWord)
        return wordToRhymeKeys[word] ?? []
    }

    nonisolated func rhymeKeys(for rawWord: String, tailLength: Int) -> [String] {
        if tailLength == 2 {
            let word = Self.normalizeWord(rawWord)
            return wordToTail2Keys[word] ?? []
        }
        return rhymeKeys(for: rawWord)
    }

    nonisolated func syllableCount(for rawWord: String) -> Int? {
        let word = Self.normalizeWord(rawWord)
        return wordToSyllableCount[word]
    }

    nonisolated func words(forRhymeKey key: String) -> [String] {
        rhymeKeyToWords[key] ?? []
    }

    nonisolated func words(forRhymeKey key: String, tailLength: Int) -> [String] {
        if tailLength == 2 {
            return tail2KeyToWords[key] ?? []
        }
        return words(forRhymeKey: key)
    }

    nonisolated func nearbyRhymeKeys(to key: String, limit: Int = 24) -> [String] {
        nearbyRhymeKeys(to: key, tailLength: 1, limit: limit)
    }

    nonisolated func nearbyRhymeKeys(to key: String, tailLength: Int, limit: Int = 24) -> [String] {
        guard let sig = RhymeKey.signature(fromRhymeKey: key) else { return [] }

        let bucketKey = "\(sig.vowelGroupID)|\(sig.endingConsonantClassID ?? "none")"
        let tight: [String]
        let wide: [String]
        if tailLength == 2 {
            tight = vowelGroupConsonantClassToTail2Keys[bucketKey] ?? []
            wide = vowelGroupToTail2Keys[sig.vowelGroupID] ?? []
        } else {
            tight = vowelGroupConsonantClassToKeys[bucketKey] ?? []
            wide = vowelGroupToKeys[sig.vowelGroupID] ?? []
        }

        var candidates = Array((tight + wide).filter { $0 != key })
        if candidates.isEmpty {
            return []
        }

        // De-dupe while preserving approximate order (tight first, then wide).
        var seen: Set<String> = []
        candidates = candidates.filter { seen.insert($0).inserted }

        let scored = candidates
            .map { other in (other, RhymeKey.similarity(key, other)) }
            .filter { $0.1 >= RhymeKey.nearRhymeThreshold && $0.1 < 1.0 }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0 < b.0
            }

        return scored.prefix(limit).map { $0.0 }
    }
}

extension CMUDictionary {
    nonisolated static func loadBundledText() -> String? {
        let candidates = ["cmudict", "cmudict-0.7b"]

        let bundles: [Bundle] = [
            Bundle(for: CMUDictionary.self),
            Bundle.main,
        ]

        for bundle in bundles {
            for name in candidates {
                if let url = bundle.url(forResource: name, withExtension: "txt"),
                   let data = try? Data(contentsOf: url),
                   let text = String(data: data, encoding: .utf8) {
                    return text
                }
            }
        }

        return nil
    }

    nonisolated static func loadBundledOrSampleText() -> String {
        loadBundledText() ?? SampleCMUDict.text
    }

    nonisolated static func parseIndex(text: String) -> CMUDictionaryIndex {
        var wordToKeys: [String: Set<String>] = [:]
        var keyToWords: [String: Set<String>] = [:]
        var vowelGroupToKeys: [String: Set<String>] = [:]
        var vowelGroupConsonantClassToKeys: [String: Set<String>] = [:]
        var wordToSyllables: [String: Set<Int>] = [:]

        var wordToTail2Keys: [String: Set<String>] = [:]
        var tail2KeyToWords: [String: Set<String>] = [:]
        var vowelGroupToTail2Keys: [String: Set<String>] = [:]
        var vowelGroupConsonantClassToTail2Keys: [String: Set<String>] = [:]

        for rawLine in text.split(whereSeparator: \.isNewline) {
            if rawLine.hasPrefix(";;;") {
                continue
            }

            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }

            var word = String(parts[0])
            if let paren = word.firstIndex(of: "(") {
                word = String(word[..<paren])
            }
            word = normalizeWord(word)
            guard !word.isEmpty else { continue }

            let phonemes = parts.dropFirst().map { String($0) }
            guard let key = RhymeKey.fromPhonemes(phonemes) else { continue }
            let key2 = RhymeKey.tailKey(fromPhonemes: phonemes, vowelNucleiCount: 2) ?? key

            // Syllables = vowel nuclei count, approximated by counting ARPAbet phonemes that carry a stress digit.
            let syllableCount = phonemes.filter { $0.last?.isNumber == true }.count
            if syllableCount > 0 {
                wordToSyllables[word, default: []].insert(syllableCount)
            }

            wordToKeys[word, default: []].insert(key)
            keyToWords[key, default: []].insert(word)

            wordToTail2Keys[word, default: []].insert(key2)
            tail2KeyToWords[key2, default: []].insert(word)

            if let sig = RhymeKey.signature(fromRhymeKey: key) {
                vowelGroupToKeys[sig.vowelGroupID, default: []].insert(key)
                let bucketKey = "\(sig.vowelGroupID)|\(sig.endingConsonantClassID ?? "none")"
                vowelGroupConsonantClassToKeys[bucketKey, default: []].insert(key)
            }

            if let sig2 = RhymeKey.signature(fromRhymeKey: key2) {
                vowelGroupToTail2Keys[sig2.vowelGroupID, default: []].insert(key2)
                let bucketKey2 = "\(sig2.vowelGroupID)|\(sig2.endingConsonantClassID ?? "none")"
                vowelGroupConsonantClassToTail2Keys[bucketKey2, default: []].insert(key2)
            }
        }

        let normalizedWordToKeys = wordToKeys
            .mapValues { Array($0).sorted() }

        let normalizedKeyToWords = keyToWords
            .mapValues { Array($0).sorted() }

        let normalizedVowelGroupToKeys = vowelGroupToKeys
            .mapValues { Array($0).sorted() }

        let normalizedVowelGroupConsonantClassToKeys = vowelGroupConsonantClassToKeys
            .mapValues { Array($0).sorted() }

        let normalizedWordToTail2Keys = wordToTail2Keys
            .mapValues { Array($0).sorted() }

        let normalizedTail2KeyToWords = tail2KeyToWords
            .mapValues { Array($0).sorted() }

        let normalizedVowelGroupToTail2Keys = vowelGroupToTail2Keys
            .mapValues { Array($0).sorted() }

        let normalizedVowelGroupConsonantClassToTail2Keys = vowelGroupConsonantClassToTail2Keys
            .mapValues { Array($0).sorted() }

        let normalizedWordToSyllables: [String: Int] = wordToSyllables.reduce(into: [:]) { out, pair in
            // Pronunciation variants usually share syllable counts; pick the minimum to avoid over-counting.
            out[pair.key] = pair.value.min() ?? 0
        }

        return CMUDictionaryIndex(
            version: CMUDictionaryIndex.currentVersion,
            wordToKeys: normalizedWordToKeys,
            keyToWords: normalizedKeyToWords,
            vowelGroupToKeys: normalizedVowelGroupToKeys,
            vowelGroupConsonantClassToKeys: normalizedVowelGroupConsonantClassToKeys,
            wordToSyllables: normalizedWordToSyllables,
            wordToTail2Keys: normalizedWordToTail2Keys,
            tail2KeyToWords: normalizedTail2KeyToWords,
            vowelGroupToTail2Keys: normalizedVowelGroupToTail2Keys,
            vowelGroupConsonantClassToTail2Keys: normalizedVowelGroupConsonantClassToTail2Keys
        )
    }

    nonisolated static func normalizeWord(_ word: String) -> String {
        word
            .lowercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}

nonisolated struct CMUDictionaryIndex: Codable, Sendable {
    nonisolated static let currentVersion = 4

    var version: Int
    var wordToKeys: [String: [String]]
    var keyToWords: [String: [String]]
    var vowelGroupToKeys: [String: [String]]
    var vowelGroupConsonantClassToKeys: [String: [String]]
    var wordToSyllables: [String: Int]

    var wordToTail2Keys: [String: [String]]
    var tail2KeyToWords: [String: [String]]
    var vowelGroupToTail2Keys: [String: [String]]
    var vowelGroupConsonantClassToTail2Keys: [String: [String]]
}

private enum SampleCMUDict {
    nonisolated static let text = """
;;; Minimal sample dictionary (dev-only fallback)
TIME  T AY1 M
RHYME  R AY1 M
LINE  L AY1 N
SHINE  SH AY1 N
MIND  M AY1 N D
FIND  F AY1 N D
NIGHT  N AY1 T
FIRE  F AY1 ER0
HIGHER  HH AY1 ER0
"""
}
