import Foundation

actor RhymeService {
    static let shared = RhymeService()

    private let dictionaryTask: Task<CMUDictionary, Never>
    private var hasLoadedDictionary = false

    init() {
        dictionaryTask = Task.detached(priority: .utility) {
            let cached = CMUDictionaryStore.loadCachedIndex()
            if let cached, cached.version == CMUDictionaryIndex.currentVersion {
                return CMUDictionary(wordToRhymeKeys: cached.wordToKeys, rhymeKeyToWords: cached.keyToWords)
            }

            let text = CMUDictionary.loadBundledOrSampleText()
            let index = CMUDictionary.parseIndex(text: text)
            CMUDictionaryStore.saveCachedIndex(index)
            return CMUDictionary(wordToRhymeKeys: index.wordToKeys, rhymeKeyToWords: index.keyToWords)
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
        guard let key = RhymeAnalyzer.currentLineRhymeKey(
            text: text,
            cursor: cursorLocation,
            dictionary: dict
        ) else {
            return []
        }

        let words = dict.words(forRhymeKey: key)
        return Array(words.prefix(maxCount))
    }
}
