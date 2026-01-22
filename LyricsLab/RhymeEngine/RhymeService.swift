import Foundation

actor RhymeService {
    static let shared = RhymeService()

    private let dictionaryTask: Task<CMUDictionary, Never>
    private var hasLoadedDictionary = false

    init() {
        dictionaryTask = Task.detached(priority: .utility) {
            let cached = CMUDictionaryStore.loadCachedIndex()
            if let cached, cached.version == CMUDictionaryIndex.currentVersion {
                return CMUDictionary(
                    wordToRhymeKeys: cached.wordToKeys,
                    rhymeKeyToWords: cached.keyToWords,
                    vowelGroupToKeys: cached.vowelGroupToKeys,
                    vowelGroupConsonantClassToKeys: cached.vowelGroupConsonantClassToKeys
                )
            }

            let text = CMUDictionary.loadBundledOrSampleText()
            let index = CMUDictionary.parseIndex(text: text)
            CMUDictionaryStore.saveCachedIndex(index)
            return CMUDictionary(
                wordToRhymeKeys: index.wordToKeys,
                rhymeKeyToWords: index.keyToWords,
                vowelGroupToKeys: index.vowelGroupToKeys,
                vowelGroupConsonantClassToKeys: index.vowelGroupConsonantClassToKeys
            )
        }
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

    func suggestions(text: String, cursorLocation: Int, maxCount: Int = 12) async -> [String] {
        let dict = await dictionaryTask.value
        hasLoadedDictionary = true

        let schemeKey = RhymeAnalyzer.inferActiveRhymeKey(
            text: text,
            cursor: cursorLocation,
            dictionary: dict,
            lookbackLines: 4
        )

        let targetKey: String?
        if RhymeAnalyzer.isCursorMidLine(text: text, cursor: cursorLocation),
           let internalKey = RhymeAnalyzer.lastCompletedTokenRhymeKey(text: text, cursor: cursorLocation, dictionary: dict) {
            targetKey = internalKey
        } else {
            targetKey = schemeKey
        }

        guard let targetKey else {
            return []
        }

        let exactWords = dict.words(forRhymeKey: targetKey)
        let exactCap = min(maxCount, 10)

        var out: [String] = []
        out.reserveCapacity(maxCount)
        var seen: Set<String> = []

        for w in exactWords {
            guard seen.insert(w).inserted else { continue }
            out.append(w)
            if out.count >= exactCap { break }
        }

        guard out.count < maxCount else {
            return out
        }

        // Fill remaining slots with near rhymes (bucketed by vowel + consonant class).
        let nearKeys = dict.nearbyRhymeKeys(to: targetKey, limit: 24)
        for k in nearKeys {
            for w in dict.words(forRhymeKey: k).prefix(3) {
                guard seen.insert(w).inserted else { continue }
                out.append(w)
                if out.count >= maxCount { return out }
            }
        }

        return out
    }
}
