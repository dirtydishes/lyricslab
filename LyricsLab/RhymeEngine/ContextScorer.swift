import Foundation
import NaturalLanguage

nonisolated enum ContextScorer {
    nonisolated static func keywords(text: String, cursorLocation: Int, maxLines: Int) -> [String] {
        let window = ContextWindow.textWindow(text: text, cursorLocation: cursorLocation, maxLines: maxLines)
        if window.isEmpty {
            return []
        }

        let tokens = LyricsTokenizer.tokenize(window)
        if tokens.isEmpty {
            return []
        }

        var counts: [String: Int] = [:]
        counts.reserveCapacity(tokens.count)

        for t in tokens {
            guard let normalized = t.normalizedCandidates.first else { continue }
            guard let keyword = normalizeForKeyword(normalized) else { continue }
            counts[keyword, default: 0] += 1
        }

        if counts.isEmpty {
            return []
        }

        // Return the most frequent keywords, stable tie-break by alpha.
        return counts
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return a.key < b.key
            }
            .prefix(12)
            .map { $0.key }
    }

    nonisolated static func contextScore(candidate: String, keywords: [String], embedding: NLEmbedding) -> Double {
        guard let c = normalizeForKeyword(candidate) else { return 0.0 }
        if keywords.isEmpty {
            return 0.0
        }

        var sims: [Double] = []
        sims.reserveCapacity(min(8, keywords.count))

        for k in keywords {
            // NLEmbedding.distance is a "distance" (smaller is closer). Map to 0..1.
            let d = embedding.distance(between: c, and: k)
            if d.isNaN || d.isInfinite {
                continue
            }

            let sim = 1.0 / (1.0 + max(0.0, d))
            sims.append(sim)
        }

        guard !sims.isEmpty else { return 0.0 }
        sims.sort(by: >)
        let take = min(3, sims.count)
        let top = sims.prefix(take)
        let avg = top.reduce(0.0, +) / Double(take)
        return min(1.0, max(0.0, avg))
    }

    nonisolated static func normalizeForKeyword(_ word: String) -> String? {
        let lower = word.lowercased()

        // Keep letters only (embeddings are word-based; punctuation/numbers add noise).
        let scalars = lower.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars))

        guard cleaned.count >= 3 else { return nil }
        guard !stopwords.contains(cleaned) else { return nil }
        return cleaned
    }

    nonisolated private static let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by",
        "for", "from", "had", "has", "have", "he", "her", "his", "i",
        "if", "in", "is", "it", "its", "me", "my", "no", "not", "of",
        "on", "or", "our", "she", "so", "that", "the", "their", "them",
        "then", "there", "they", "this", "to", "up", "us", "was", "we",
        "were", "what", "when", "where", "who", "with", "you", "your",
    ]
}

nonisolated enum ContextWindow {
    nonisolated static func textWindow(text: String, cursorLocation: Int, maxLines: Int) -> String {
        guard maxLines > 0 else { return "" }
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        if fullRange.length == 0 {
            return ""
        }

        var clamped = max(0, min(cursorLocation, ns.length))
        // If the cursor is at the very end and the text ends in a newline, treat it as being on
        // the last line (by-lines ranges usually exclude the trailing newline character).
        if clamped == ns.length, ns.length > 0 {
            let last = ns.character(at: ns.length - 1)
            if last == 10 || last == 13 {
                clamped = ns.length - 1
            }
        }

        var lineRanges: [NSRange] = []
        lineRanges.reserveCapacity(64)

        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            lineRanges.append(lineRange)
        }

        guard !lineRanges.isEmpty else { return "" }

        let currentLineIndex = lineRanges.lastIndex(where: { NSLocationInRange(clamped, $0) || (clamped == ns.length && NSMaxRange($0) == ns.length) })
        // Fallback: if we still couldn't find a containing line, treat it as the last line.
        let resolvedLineIndex = currentLineIndex ?? (lineRanges.count - 1)

        let start = max(0, resolvedLineIndex - maxLines + 1)
        let scoped = lineRanges[start...resolvedLineIndex]
            .map { ns.substring(with: $0) }
            .joined(separator: "\n")

        return scoped
    }
}
