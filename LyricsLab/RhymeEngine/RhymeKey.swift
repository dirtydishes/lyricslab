import Foundation

enum RhymeKey {
    // Common heuristic: from last stressed vowel to end.
    // Example: "S T AY1" -> "AY1" (or "AY1" plus following phonemes).
    nonisolated static func fromPhonemes(_ phonemes: [String]) -> String? {
        guard !phonemes.isEmpty else { return nil }

        // CMU marks stress with a trailing digit on vowel phonemes (0/1/2).
        if let idx = phonemes.lastIndex(where: { $0.last?.isNumber == true }) {
            return phonemes[idx...].joined(separator: " ")
        }

        // Fallback: last two phonemes. (Better than nothing if stress is missing.)
        let tail = phonemes.suffix(2)
        return tail.isEmpty ? nil : tail.joined(separator: " ")
    }
}
