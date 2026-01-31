import Foundation

nonisolated struct SectionBracket: Equatable, Sendable, Identifiable {
    // Stable-enough identifier for UI diffing.
    var id: String

    var stanzaIndex: Int
    var startLineIndex: Int
    var endLineIndex: Int

    // Count of non-empty lines in the stanza.
    var barCount: Int

    // If non-nil, we show a bracket label.
    var labelBars: Int?
    var isLocked: Bool

    // Used to match persisted overrides to newly inferred stanzas.
    var anchor: String

    var labelText: String? {
        guard let labelBars else { return nil }
        return "\(labelBars) bars"
    }
}

nonisolated struct SectionOverride: Codable, Equatable, Sendable {
    var anchor: String
    var barCount: Int
}

nonisolated enum SectionOverrideCodec {
    nonisolated static func decode(blob: String) -> [SectionOverride] {
        let trimmed = blob.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SectionOverride].self, from: data)) ?? []
    }

    nonisolated static func encode(overrides: [SectionOverride]) -> String {
        guard !overrides.isEmpty else { return "" }
        guard let data = try? JSONEncoder().encode(overrides) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

nonisolated enum SectionDetector {
    nonisolated static func detectBrackets(text: String, overridesBlob: String) -> [SectionBracket] {
        let overrides = SectionOverrideCodec.decode(blob: overridesBlob)
        var overrideByAnchor: [String: Int] = [:]
        overrideByAnchor.reserveCapacity(overrides.count)
        for o in overrides {
            overrideByAnchor[o.anchor] = o.barCount
        }

        let lines = splitLines(text)
        if lines.isEmpty {
            return []
        }

        // Stanzas separated by blank lines.
        var stanzas: [(start: Int, end: Int, nonEmptyLineIndices: [Int])] = []
        stanzas.reserveCapacity(16)

        var current: [Int] = []
        current.reserveCapacity(16)

        for (idx, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !current.isEmpty {
                    stanzas.append((start: current.first!, end: current.last!, nonEmptyLineIndices: current))
                    current = []
                }
                continue
            }
            current.append(idx)
        }
        if !current.isEmpty {
            stanzas.append((start: current.first!, end: current.last!, nonEmptyLineIndices: current))
        }

        var out: [SectionBracket] = []
        out.reserveCapacity(stanzas.count)

        for (stanzaIndex, s) in stanzas.enumerated() {
            let barCount = s.nonEmptyLineIndices.count
            let anchor = stanzaAnchor(lines: lines, startLineIndex: s.start)

            let lockedBars = overrideByAnchor[anchor]
            let labelBars: Int?
            let isLocked: Bool
            if let lockedBars {
                labelBars = lockedBars
                isLocked = true
            } else {
                labelBars = snapBars(barCount)
                isLocked = false
            }

            let id = "\(anchor)|\(s.start)|\(s.end)"
            out.append(
                SectionBracket(
                    id: id,
                    stanzaIndex: stanzaIndex,
                    startLineIndex: s.start,
                    endLineIndex: s.end,
                    barCount: barCount,
                    labelBars: labelBars,
                    isLocked: isLocked,
                    anchor: anchor
                )
            )
        }

        return out
    }

    nonisolated static func applyOverride(blob: String, anchor: String, barCount: Int?) -> String {
        var overrides = SectionOverrideCodec.decode(blob: blob)
        overrides.removeAll(where: { $0.anchor == anchor })

        if let barCount {
            overrides.append(SectionOverride(anchor: anchor, barCount: barCount))
        }

        // Stable ordering for diffs/sync.
        overrides.sort { a, b in
            if a.anchor != b.anchor { return a.anchor < b.anchor }
            return a.barCount < b.barCount
        }

        return SectionOverrideCodec.encode(overrides: overrides)
    }

    private nonisolated static func snapBars(_ barCount: Int) -> Int? {
        let targets = [4, 8, 12, 16]
        var best: (target: Int, delta: Int)?
        for t in targets {
            let d = abs(barCount - t)
            if d <= 1 {
                if let bestExisting = best {
                    if d < bestExisting.delta {
                        best = (t, d)
                    } else if d == bestExisting.delta, t < bestExisting.target {
                        best = (t, d)
                    }
                } else {
                    best = (t, d)
                }
            }
        }
        return best?.target
    }

    private nonisolated static func stanzaAnchor(lines: [String], startLineIndex: Int) -> String {
        guard startLineIndex >= 0, startLineIndex < lines.count else { return "stanza-unknown" }
        let raw = lines[startLineIndex]
        let lower = raw.lowercased()

        // Keep letters/digits/spaces; collapse whitespace.
        let allowed = CharacterSet.letters.union(.decimalDigits).union(.whitespaces)
        let scalars = lower.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " }
        let cleaned = String(scalars)
        let collapsed = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if collapsed.isEmpty {
            return "stanza-\(startLineIndex)"
        }
        return String(collapsed.prefix(42))
    }

    private nonisolated static func splitLines(_ text: String) -> [String] {
        // Preserve empty lines between stanzas.
        text.split(omittingEmptySubsequences: false, whereSeparator: \ .isNewline).map(String.init)
    }
}
