import Foundation

nonisolated enum LyricsTokenizer {
    struct Token: Equatable, Sendable {
        var raw: String
        var rangeInString: NSRange
        var normalizedCandidates: [String]
    }

    // Rough, rap-friendly tokenization. Produces tokens with NSRange offsets in the input string.
    // Notes:
    // - Hyphens are treated as separators.
    // - We include digits for tokens like 808, 9mm, 24/7 (split into 24 and 7).
    // - Normalization is for lookup only; the UI should display the original token.
    static func tokenize(_ text: String) -> [Token] {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return [] }

        // Split on whitespace and most punctuation, but keep apostrophes inside words.
        // Hyphens are treated as separators because rap writing uses a lot of hyphenated compounds.
        let pattern = "[A-Za-z0-9']+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let matches = regex.matches(in: text, range: fullRange)
        guard !matches.isEmpty else { return [] }

        var out: [Token] = []
        out.reserveCapacity(matches.count)

        for m in matches {
            let raw = ns.substring(with: m.range)
            let candidates = LookupNormalization.normalizedCandidates(forLookup: raw)
            out.append(Token(raw: raw, rangeInString: m.range, normalizedCandidates: candidates))
        }

        return out
    }
}
