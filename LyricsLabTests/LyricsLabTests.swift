import Foundation
import Testing

@testable import LyricsLab

struct RhymeEngineTests {
    private func makeDict(fromCMUText text: String) -> CMUDictionary {
        let index = CMUDictionary.parseIndex(text: text)
        return CMUDictionary(
            wordToRhymeKeys: index.wordToKeys,
            rhymeKeyToWords: index.keyToWords,
            vowelGroupToKeys: index.vowelGroupToKeys,
            vowelGroupConsonantClassToKeys: index.vowelGroupConsonantClassToKeys
        )
    }

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
        #expect(index.vowelGroupToKeys["diphthong"]?.contains("AY1 M") == true)
        #expect(index.vowelGroupConsonantClassToKeys["diphthong|nasal"]?.contains("AY1 M") == true)
    }

    @Test func nearRhymeSimilarityTreatsNasalEndingsAsNear() async throws {
        #expect(RhymeKey.isNearRhyme("AY1 M", "AY1 N") == true)
        #expect(RhymeKey.isNearRhyme("AY1 M", "AY1 T") == false)
    }

    @Test func nearbyRhymeKeysReturnsSimilarKeys() async throws {
        let text = """
        TIME  T AY1 M
        LINE  L AY1 N
        """
        let dict = makeDict(fromCMUText: text)
        let near = dict.nearbyRhymeKeys(to: "AY1 M", limit: 10)
        #expect(near.contains("AY1 N") == true)
    }

    @Test func analyzeGroupsRepeatedEndRhymesAcrossLines() async throws {
        let cmuText = """
        TIME  T AY1 M
        RHYME  R AY1 M
        """
        let dict = makeDict(fromCMUText: cmuText)

        let lyricsText = "It's time\nTo rhyme\n"
        let analysis = RhymeAnalyzer.analyze(text: lyricsText, dictionary: dict)

        #expect(analysis.groups.count == 1)
        #expect(analysis.groups.first?.type == .end)
        #expect(analysis.groups.first?.rhymeKey == "AY1 M")
        #expect(analysis.groups.first?.tokens.count == 2)

        let ranges = analysis.groups.first?.tokens.map { $0.range } ?? []
        #expect(ranges.contains(NSRange(location: 5, length: 4)))
        #expect(ranges.contains(NSRange(location: 13, length: 5)))
    }

    @Test func currentLineRhymeKeyUsesLineEndingWord() async throws {
        let dict = makeDict(fromCMUText: """
        TIME  T AY1 M
        RHYME  R AY1 M
        """)

        let text = "It's time\nTo rhyme\n"
        let key = RhymeAnalyzer.currentLineRhymeKey(text: text, cursor: 15, dictionary: dict)
        #expect(key == "AY1 M")
    }

    @Test func inferActiveRhymeKeyPrefersRecentRepeatInLookback() async throws {
        let dict = makeDict(fromCMUText: """
        TIME  T AY1 M
        RHYME  R AY1 M
        LINE  L AY1 N
        """)

        let text = "It's time\nSome rhyme\nNext line\n"
        // Cursor in the third line.
        let key = RhymeAnalyzer.inferActiveRhymeKey(text: text, cursor: 24, dictionary: dict)
        #expect(key == "AY1 M")
    }
}
