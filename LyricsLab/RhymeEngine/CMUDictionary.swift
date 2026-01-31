import Foundation

nonisolated final class CMUDictionary {
    nonisolated private let wordToRhymeKeys: [String: [String]]
    nonisolated private let rhymeKeyToWords: [String: [String]]
    nonisolated private let vowelGroupToKeys: [String: [String]]
    nonisolated private let vowelGroupConsonantClassToKeys: [String: [String]]

    init(
        wordToRhymeKeys: [String: [String]],
        rhymeKeyToWords: [String: [String]],
        vowelGroupToKeys: [String: [String]],
        vowelGroupConsonantClassToKeys: [String: [String]]
    ) {
        self.wordToRhymeKeys = wordToRhymeKeys
        self.rhymeKeyToWords = rhymeKeyToWords
        self.vowelGroupToKeys = vowelGroupToKeys
        self.vowelGroupConsonantClassToKeys = vowelGroupConsonantClassToKeys
    }

    nonisolated func rhymeKeys(for rawWord: String) -> [String] {
        let word = Self.normalizeWord(rawWord)
        return wordToRhymeKeys[word] ?? []
    }

    nonisolated func words(forRhymeKey key: String) -> [String] {
        rhymeKeyToWords[key] ?? []
    }

    nonisolated func nearbyRhymeKeys(to key: String, limit: Int = 24) -> [String] {
        guard let sig = RhymeKey.signature(fromRhymeKey: key) else { return [] }

        let bucketKey = "\(sig.vowelGroupID)|\(sig.endingConsonantClassID ?? "none")"
        let tight = vowelGroupConsonantClassToKeys[bucketKey] ?? []
        let wide = vowelGroupToKeys[sig.vowelGroupID] ?? []

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

            wordToKeys[word, default: []].insert(key)
            keyToWords[key, default: []].insert(word)

            if let sig = RhymeKey.signature(fromRhymeKey: key) {
                vowelGroupToKeys[sig.vowelGroupID, default: []].insert(key)
                let bucketKey = "\(sig.vowelGroupID)|\(sig.endingConsonantClassID ?? "none")"
                vowelGroupConsonantClassToKeys[bucketKey, default: []].insert(key)
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

        return CMUDictionaryIndex(
            version: CMUDictionaryIndex.currentVersion,
            wordToKeys: normalizedWordToKeys,
            keyToWords: normalizedKeyToWords,
            vowelGroupToKeys: normalizedVowelGroupToKeys,
            vowelGroupConsonantClassToKeys: normalizedVowelGroupConsonantClassToKeys
        )
    }

    nonisolated static func normalizeWord(_ word: String) -> String {
        word
            .lowercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}

nonisolated struct CMUDictionaryIndex: Codable, Sendable {
    nonisolated static let currentVersion = 2

    var version: Int
    var wordToKeys: [String: [String]]
    var keyToWords: [String: [String]]
    var vowelGroupToKeys: [String: [String]]
    var vowelGroupConsonantClassToKeys: [String: [String]]
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
