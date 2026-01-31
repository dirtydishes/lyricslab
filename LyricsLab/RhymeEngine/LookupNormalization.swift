import Foundation

nonisolated enum LookupNormalization {
    // Returns normalized lookup candidates in priority order.
    // The first item should be the "closest" to the user's text.
    static func normalizedCandidates(forLookup raw: String) -> [String] {
        let trimmed = raw.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard !trimmed.isEmpty else { return [] }

        var out: [String] = []
        out.reserveCapacity(3)
        out.append(trimmed)

        // Common rap/colloquial spellings.
        let map: [String: String] = [
            "runnin": "running",
            "nothin": "nothing",
            "gon": "gonna",
            "gonna": "gonna",
            "cause": "because",
        ]

        // Handle trailing apostrophe drops like "gon'".
        let noTrailingApos = trimmed.hasSuffix("'") ? String(trimmed.dropLast()) : nil
        if let noTrailingApos, noTrailingApos != trimmed {
            out.append(noTrailingApos)
        }

        // Handle leading apostrophe like "'cause".
        let noLeadingApos = trimmed.hasPrefix("'") ? String(trimmed.dropFirst()) : nil
        if let noLeadingApos, noLeadingApos != trimmed {
            out.append(noLeadingApos)
        }

        // Expand mapped forms.
        for candidate in out {
            if let mapped = map[candidate], mapped != candidate {
                out.append(mapped)
            }
        }

        // De-dupe while preserving order.
        var seen: Set<String> = []
        out = out.filter { seen.insert($0).inserted }

        return out
    }
}
