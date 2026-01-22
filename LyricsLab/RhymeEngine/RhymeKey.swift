import Foundation

nonisolated enum RhymeKey {
    struct Signature: Equatable, Hashable, Sendable {
        var vowelBase: String
        var vowelGroupID: String
        var endingConsonant: String?
        var endingConsonantClassID: String?
    }

    // Common heuristic: from last stressed vowel to end.
    // Example: "S T AY1" -> "AY1" (or "AY1" plus following phonemes).
    static func fromPhonemes(_ phonemes: [String]) -> String? {
        guard !phonemes.isEmpty else { return nil }

        // CMU marks stress with a trailing digit on vowel phonemes (0/1/2).
        if let idx = phonemes.lastIndex(where: { $0.last?.isNumber == true }) {
            return phonemes[idx...].joined(separator: " ")
        }

        // Fallback: last two phonemes. (Better than nothing if stress is missing.)
        let tail = phonemes.suffix(2)
        return tail.isEmpty ? nil : tail.joined(separator: " ")
    }

    static let nearRhymeThreshold: Double = 0.84

    static func signature(fromRhymeKey key: String) -> Signature? {
        let parts = key.split(separator: " ").map(String.init)
        guard let first = parts.first else { return nil }

        let vowel = stripStressDigit(first)
        let vowelGroup = vowelGroupID(for: vowel)

        // Find last consonant-like phoneme in the key (ignores vowels like ER0).
        let lastConsonant = parts.last(where: { isConsonantPhoneme($0) })
        let consonantClass = lastConsonant.flatMap { consonantClassID(for: $0) }

        return Signature(
            vowelBase: vowel,
            vowelGroupID: vowelGroup,
            endingConsonant: lastConsonant,
            endingConsonantClassID: consonantClass
        )
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        guard a != b else { return 1.0 }
        guard let sa = signature(fromRhymeKey: a), let sb = signature(fromRhymeKey: b) else { return 0.0 }

        let vowelScore: Double
        if sa.vowelBase == sb.vowelBase {
            vowelScore = 1.0
        } else if sa.vowelGroupID == sb.vowelGroupID {
            vowelScore = 0.70
        } else {
            vowelScore = 0.0
        }

        let consonantScore: Double
        switch (sa.endingConsonant, sb.endingConsonant) {
        case (nil, nil):
            consonantScore = 0.55
        case (let ca?, let cb?):
            if ca == cb {
                consonantScore = 1.0
            } else if sa.endingConsonantClassID != nil, sa.endingConsonantClassID == sb.endingConsonantClassID {
                consonantScore = 0.70
            } else {
                consonantScore = 0.0
            }
        default:
            consonantScore = 0.0
        }

        return 0.65 * vowelScore + 0.35 * consonantScore
    }

    static func isNearRhyme(_ a: String, _ b: String) -> Bool {
        similarity(a, b) >= nearRhymeThreshold
    }

    private static func stripStressDigit(_ phoneme: String) -> String {
        phoneme.trimmingCharacters(in: CharacterSet.decimalDigits)
    }

    private static func isConsonantPhoneme(_ phoneme: String) -> Bool {
        // Vowels have a trailing stress digit in CMU.
        phoneme.last?.isNumber != true
    }

    private static func vowelGroupID(for vowelBase: String) -> String {
        // Rough ARPAbet vowel clustering.
        switch vowelBase {
        case "IY", "IH":
            return "front-high"
        case "EH", "EY":
            return "front-mid"
        case "AE":
            return "front-low"
        case "AH", "AX", "ER":
            return "central"
        case "AA", "AO", "OW", "UH", "UW":
            return "back"
        case "AY", "AW", "OY":
            return "diphthong"
        default:
            return "other"
        }
    }

    private static func consonantClassID(for consonant: String) -> String? {
        switch consonant {
        case "M", "N", "NG":
            return "nasal"
        case "P", "B", "T", "D", "K", "G":
            return "stop"
        case "F", "V", "TH", "DH", "S", "Z", "SH", "ZH", "HH":
            return "fricative"
        case "CH", "JH":
            return "affricate"
        case "L", "R":
            return "liquid"
        case "W", "Y":
            return "glide"
        default:
            return nil
        }
    }
}
