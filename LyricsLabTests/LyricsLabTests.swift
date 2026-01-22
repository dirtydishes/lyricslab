import Foundation
import Testing

@testable import LyricsLab

struct RhymeEngineTests {
    @Test func bundledCMUDictExistsInAppBundle() async throws {
        let bundle = Bundle(for: CMUDictionary.self)
        let candidates = ["cmudict", "cmudict-0.7b"]

        let url = candidates
            .compactMap { bundle.url(forResource: $0, withExtension: "txt") }
            .first

        #expect(url != nil)
    }

    @Test func rhymeKeyFromPhonemesUsesLastStressedVowel() async throws {
        let key = RhymeKey.fromPhonemes(["T", "AY1", "M"])
        #expect(key == "AY1 M")
    }

    @Test func cmuParseIndexBuildsWordAndKeyLookups() async throws {
        let text = """
        ;;;
        TIME  T AY1 M
        RHYME  R AY1 M
        LINE  L AY1 N
        SHINE  SH AY1 N
        """

        let index = CMUDictionary.parseIndex(text: text)
        #expect(index.wordToKeys["time"] == ["AY1 M"])
        #expect(index.keyToWords["AY1 M"]?.contains("time") == true)
        #expect(index.keyToWords["AY1 M"]?.contains("rhyme") == true)
    }

    @Test func analyzeGroupsRepeatedEndRhymesAcrossLines() async throws {
        let dict = CMUDictionary(
            wordToRhymeKeys: [
                "time": ["AY1 M"],
                "rhyme": ["AY1 M"],
            ],
            rhymeKeyToWords: [
                "AY1 M": ["rhyme", "time"],
            ]
        )

        let text = "It's time\nTo rhyme\n"
        let analysis = RhymeAnalyzer.analyze(text: text, dictionary: dict)

        #expect(analysis.groups.count == 1)
        #expect(analysis.groups.first?.rhymeKey == "AY1 M")
        #expect(analysis.groups.first?.tokens.count == 2)

        let ranges = analysis.groups.first?.tokens.map { $0.range } ?? []
        #expect(ranges.contains(NSRange(location: 5, length: 4)))
        #expect(ranges.contains(NSRange(location: 13, length: 5)))
    }

    @Test func currentLineRhymeKeyUsesLineEndingWord() async throws {
        let dict = CMUDictionary(
            wordToRhymeKeys: [
                "time": ["AY1 M"],
                "rhyme": ["AY1 M"],
            ],
            rhymeKeyToWords: [
                "AY1 M": ["rhyme", "time"],
            ]
        )

        let text = "It's time\nTo rhyme\n"
        let key = RhymeAnalyzer.currentLineRhymeKey(text: text, cursor: 15, dictionary: dict)
        #expect(key == "AY1 M")
    }
}
