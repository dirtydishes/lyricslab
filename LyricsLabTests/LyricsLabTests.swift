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
            vowelGroupConsonantClassToKeys: index.vowelGroupConsonantClassToKeys,
            wordToSyllableCount: index.wordToSyllables,
            wordToTail2Keys: index.wordToTail2Keys,
            tail2KeyToWords: index.tail2KeyToWords,
            vowelGroupToTail2Keys: index.vowelGroupToTail2Keys,
            vowelGroupConsonantClassToTail2Keys: index.vowelGroupConsonantClassToTail2Keys
        )
    }

    @Test func tail2KeyUsesLastTwoVowelSegments() async throws {
        let key = RhymeKey.tailKey(fromPhonemes: ["T", "AY1", "M", "IH0", "NG"], vowelNucleiCount: 2)
        #expect(key == "AY1 M IH0 NG")
    }

    @Test func signatureUsesLastVowelInMultiTailKey() async throws {
        let sig = RhymeKey.signature(fromRhymeKey: "AY1 M IH0 NG")
        #expect(sig?.vowelBase == "IH")
    }

    @Test func contextKeywordsIgnoreStopwords() async throws {
        let text = "I got money on my mind\nMoney and cars on the street\n"
        let cursor = (text as NSString).length
        let keywords = ContextScorer.keywords(text: text, cursorLocation: cursor, maxLines: 4)
        #expect(keywords.contains("money") == true)
        #expect(keywords.contains("street") == true)
        #expect(keywords.contains("cars") == true)
        #expect(keywords.contains("the") == false)
        #expect(keywords.contains("and") == false)
    }

    @Test func sectionDetectorSplitsStanzasAndSnapsBarCounts() async throws {
        let text = "a\nb\nc\nd\n\n1\n2\n3\n4\n5\n6\n7\n8\n"
        let brackets = SectionDetector.detectBrackets(text: text, overridesBlob: "")
        #expect(brackets.count == 2)

        #expect(brackets[0].barCount == 4)
        #expect(brackets[0].labelBars == 4)

        #expect(brackets[1].barCount == 8)
        #expect(brackets[1].labelBars == 8)
    }

    @Test func sectionOverrideIsAppliedByAnchor() async throws {
        let text = "money on my mind\nline2\nline3\nline4\n"
        let brackets = SectionDetector.detectBrackets(text: text, overridesBlob: "")
        #expect(brackets.count == 1)

        let anchor = brackets[0].anchor
        let blob = SectionDetector.applyOverride(blob: "", anchor: anchor, barCount: 8)
        let after = SectionDetector.detectBrackets(text: text, overridesBlob: blob)
        #expect(after.first?.isLocked == true)
        #expect(after.first?.labelBars == 8)
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
        #expect(index.wordToSyllables["time"] == 1)
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

    @Test func internalNearRhymeThresholdIsStricterThanEnd() async throws {
        let dict = makeDict(fromCMUText: """
        TIME  T AY1 M
        LINE  L AY1 N
        """)

        // End words: should form a near group (0.895 similarity) at the looser threshold.
        let endText = "time\nline\n"
        let endAnalysis = RhymeAnalyzer.analyze(text: endText, dictionary: dict)
        let endNear = endAnalysis.groups.first(where: { $0.type == .near })
        #expect(endNear != nil)
        #expect(endNear?.occurrences.count == 2)

        // Internal words: should NOT form a near group at the stricter internal threshold.
        let internalText = "time foo\nline bar\n"
        let internalAnalysis = RhymeAnalyzer.analyze(text: internalText, dictionary: dict)
        let internalNear = internalAnalysis.groups.first(where: { $0.type == .near })
        #expect(internalNear == nil)
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
        #expect(analysis.groups.first?.occurrences.count == 2)

        let ranges = analysis.groups.first?.occurrences.map { $0.range } ?? []
        #expect(ranges.contains(NSRange(location: 5, length: 4)))
        #expect(ranges.contains(NSRange(location: 13, length: 5)))
    }

    @Test func analyzeBuildsInternalGroupsAcrossNearbyLines() async throws {
        let dict = makeDict(fromCMUText: """
        TIME  T AY1 M
        RHYME  R AY1 M
        SHINE  SH AY1 N
        """)

        // "time" (internal), "rhyme" (internal), and "time" (line-final) should
        // form one exact group within the 4-line span.
        let text = "It's time to shine\nWe rhyme at night\nBack in time\n"
        let analysis = RhymeAnalyzer.analyze(text: text, dictionary: dict)

        let internalGroup = analysis.groups.first(where: { $0.rhymeKey == "AY1 M" && $0.type == .`internal` })
        #expect(internalGroup != nil)
        #expect(internalGroup?.occurrences.count == 3)

        let finals = internalGroup?.occurrences.filter { $0.isLineFinalToken }.count ?? 0
        #expect(finals == 1)
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

    @Test func lastCompletedTokenUsesWordBeforeCursor() async throws {
        let dict = makeDict(fromCMUText: """
        TIME  T AY1 M
        SHINE  SH AY1 N
        """)

        let text = "It's time to shine\n"
        // Cursor after "time".
        let cursor = ("It's time" as NSString).length
        let key = RhymeAnalyzer.lastCompletedTokenRhymeKey(text: text, cursor: cursor, dictionary: dict)
        #expect(key == "AY1 M")
    }
}
