import Foundation

nonisolated enum RhymeAnalyzer {
    private static let wordPattern = "[A-Za-z']+"
    private static let maxLineDistance = 3

    private struct RangeKey: Hashable {
        var location: Int
        var length: Int
    }

    nonisolated static func analyze(text: String, dictionary: CMUDictionary) -> RhymeAnalysis {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return .empty }

        guard let regex = try? NSRegularExpression(pattern: wordPattern, options: []) else {
            return .empty
        }

        var occurrences: [RhymeOccurrence] = []
        occurrences.reserveCapacity(256)

        var endOccurrences: [RhymeOccurrence] = []
        endOccurrences.reserveCapacity(64)

        var lineIndex = 0
        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            defer { lineIndex += 1 }
            guard lineRange.length > 0 else { return }

            let lineText = ns.substring(with: lineRange)
            let lineNS = lineText as NSString
            let matches = regex.matches(in: lineText, options: [], range: NSRange(location: 0, length: lineNS.length))
            guard !matches.isEmpty else { return }

            var lineOccurrences: [RhymeOccurrence] = []
            lineOccurrences.reserveCapacity(matches.count)

            for (idx, m) in matches.enumerated() {
                let isFinalToken = idx == matches.count - 1
                let word = lineNS.substring(with: m.range)
                guard let key = dictionary.rhymeKeys(for: word).first else { continue }
                let fullTokenRange = NSRange(location: lineRange.location + m.range.location, length: m.range.length)

                let occ = RhymeOccurrence(
                    range: fullTokenRange,
                    rhymeKey: key,
                    lineIndex: lineIndex,
                    isLineFinalToken: isFinalToken
                )
                lineOccurrences.append(occ)
                if isFinalToken {
                    endOccurrences.append(occ)
                }
            }

            guard !lineOccurrences.isEmpty else { return }
            occurrences.append(contentsOf: lineOccurrences)
        }

        // 1) End rhyme groups (exact, by line-final tokens only; global).
        let endByKey = Dictionary(grouping: endOccurrences, by: { $0.rhymeKey })
        let endKeys = endByKey
            .filter { $0.value.count >= 2 }
            .map { $0.key }

        // 2) Internal rhyme groups (exact, connected across <= 4 lines).
        // Includes line-final tokens, but only emits groups that contain at least one non-final token.
        let allByKey = Dictionary(grouping: occurrences, by: { $0.rhymeKey })
        var internalGroups: [RhymeGroup] = []
        internalGroups.reserveCapacity(32)

        for (key, occs) in allByKey {
            // Quick skip: if there are no internal occurrences at all, don't create internal groups.
            if occs.allSatisfy({ $0.isLineFinalToken }) {
                continue
            }

            // Use union-find with a bounded lookahead in sorted order.
            let sorted = occs.sorted {
                if $0.lineIndex != $1.lineIndex { return $0.lineIndex < $1.lineIndex }
                return $0.range.location < $1.range.location
            }
            if sorted.count < 2 {
                continue
            }

            var parent = Array(sorted.indices)
            func find(_ i: Int) -> Int {
                var x = i
                while parent[x] != x {
                    parent[x] = parent[parent[x]]
                    x = parent[x]
                }
                return x
            }
            func union(_ a: Int, _ b: Int) {
                let ra = find(a)
                let rb = find(b)
                if ra != rb { parent[rb] = ra }
            }

            for i in 0..<sorted.count {
                var j = i + 1
                while j < sorted.count {
                    let d = sorted[j].lineIndex - sorted[i].lineIndex
                    if d > maxLineDistance { break }
                    union(i, j)
                    j += 1
                }
            }

            var clusters: [Int: [RhymeOccurrence]] = [:]
            for i in 0..<sorted.count {
                clusters[find(i), default: []].append(sorted[i])
            }

            for cluster in clusters.values {
                guard cluster.count >= 2 else { continue }
                guard cluster.contains(where: { !$0.isLineFinalToken }) else { continue }
                let occsForGroup = cluster.sorted { $0.range.location < $1.range.location }
                internalGroups.append(RhymeGroup(type: .`internal`, rhymeKey: key, colorIndex: 0, occurrences: occsForGroup))
            }
        }

        // 3) Assign stable colorIndex per exact rhymeKey across BOTH end + internal groups.
        let exactKeys = Set(endKeys).union(internalGroups.map { $0.rhymeKey })
        var keyToFirstLocation: [String: Int] = [:]
        for (key, occs) in allByKey where exactKeys.contains(key) {
            keyToFirstLocation[key] = occs.map { $0.range.location }.min() ?? Int.max
        }

        let orderedExactKeys = exactKeys.sorted { a, b in
            let aFirst = keyToFirstLocation[a] ?? Int.max
            let bFirst = keyToFirstLocation[b] ?? Int.max
            if aFirst != bFirst { return aFirst < bFirst }
            return a < b
        }
        let colorIndexByKey = Dictionary(uniqueKeysWithValues: orderedExactKeys.enumerated().map { ($0.element, $0.offset) })

        var endGroups: [RhymeGroup] = []
        endGroups.reserveCapacity(endKeys.count)
        for key in orderedExactKeys where endKeys.contains(key) {
            let occs = (endByKey[key] ?? []).sorted { $0.range.location < $1.range.location }
            endGroups.append(RhymeGroup(type: .end, rhymeKey: key, colorIndex: colorIndexByKey[key] ?? 0, occurrences: occs))
        }
        for i in internalGroups.indices {
            internalGroups[i].colorIndex = colorIndexByKey[internalGroups[i].rhymeKey] ?? 0
        }
        internalGroups.sort { a, b in
            let aFirst = a.occurrences.first?.range.location ?? Int.max
            let bFirst = b.occurrences.first?.range.location ?? Int.max
            return aFirst < bFirst
        }

        // 4) Near groups (exact groups take precedence). We only emit near highlights
        // for occurrences that are not part of any exact group to avoid visual noise.
        var used: Set<RangeKey> = []
        used.reserveCapacity((endGroups.count + internalGroups.count) * 8)
        for g in endGroups {
            for o in g.occurrences {
                used.insert(RangeKey(location: o.range.location, length: o.range.length))
            }
        }
        for g in internalGroups {
            for o in g.occurrences {
                used.insert(RangeKey(location: o.range.location, length: o.range.length))
            }
        }

        let remaining = occurrences.filter { !used.contains(RangeKey(location: $0.range.location, length: $0.range.length)) }
        var nearGroups = clusterNearOccurrences(occurrences: remaining)
        let nearStart = orderedExactKeys.count
        for i in nearGroups.indices {
            nearGroups[i].colorIndex = nearStart + i
        }

        var out: [RhymeGroup] = []
        out.reserveCapacity(endGroups.count + internalGroups.count + nearGroups.count)
        out.append(contentsOf: endGroups)
        out.append(contentsOf: internalGroups)
        out.append(contentsOf: nearGroups)

        // Deterministic ordering: by first occurrence.
        out.sort { a, b in
            let aFirst = a.occurrences.first?.range.location ?? Int.max
            let bFirst = b.occurrences.first?.range.location ?? Int.max
            if aFirst != bFirst { return aFirst < bFirst }
            return a.id < b.id
        }

        return RhymeAnalysis(groups: out)
    }

    // Picks the last completed word token before the cursor in the current line.
    // This powers the internal-rhyme suggestion mode.
    nonisolated static func lastCompletedTokenRhymeKey(text: String, cursor: Int, dictionary: CMUDictionary) -> String? {
        let ns = text as NSString
        let clamped = max(0, min(cursor, ns.length))
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return nil }
        guard let regex = try? NSRegularExpression(pattern: wordPattern, options: []) else { return nil }

        var foundLineRange: NSRange?
        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, stop in
            if NSLocationInRange(clamped, lineRange) || (clamped == ns.length && NSMaxRange(lineRange) == ns.length) {
                foundLineRange = lineRange
                stop.pointee = true
            }
        }

        guard let lineRange = foundLineRange else { return nil }
        let lineText = ns.substring(with: lineRange)
        let lineNS = lineText as NSString
        let cursorInLine = max(0, min(clamped - lineRange.location, lineNS.length))

        let matches = regex.matches(in: lineText, options: [], range: NSRange(location: 0, length: lineNS.length))
        let completed = matches.filter { NSMaxRange($0.range) <= cursorInLine }
        guard let last = completed.last else { return nil }

        let word = lineNS.substring(with: last.range)
        return dictionary.rhymeKeys(for: word).first
    }

    nonisolated static func isCursorMidLine(text: String, cursor: Int) -> Bool {
        let ns = text as NSString
        let clamped = max(0, min(cursor, ns.length))
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return false }
        guard let regex = try? NSRegularExpression(pattern: wordPattern, options: []) else { return false }

        var foundLineRange: NSRange?
        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, stop in
            if NSLocationInRange(clamped, lineRange) || (clamped == ns.length && NSMaxRange(lineRange) == ns.length) {
                foundLineRange = lineRange
                stop.pointee = true
            }
        }
        guard let lineRange = foundLineRange else { return false }

        let lineText = ns.substring(with: lineRange)
        let lineNS = lineText as NSString
        let cursorInLine = max(0, min(clamped - lineRange.location, lineNS.length))
        let tailRange = NSRange(location: cursorInLine, length: max(0, lineNS.length - cursorInLine))
        guard tailRange.length > 0 else { return false }

        return regex.firstMatch(in: lineText, options: [], range: tailRange) != nil
    }

    // Simple scheme inference: in the last N lines up to cursor, pick the most recent
    // repeated line-ending rhyme key; otherwise fall back to current line ending.
    nonisolated static func inferActiveRhymeKey(text: String, cursor: Int, dictionary: CMUDictionary, lookbackLines: Int = 12) -> String? {
        let ns = text as NSString
        let clamped = max(0, min(cursor, ns.length))
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return nil }
        guard let regex = try? NSRegularExpression(pattern: wordPattern, options: []) else { return nil }

        var currentLineIndex: Int?
        var lineIndex = 0
        var endings: [(lineIndex: Int, key: String)] = []
        endings.reserveCapacity(64)

        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            if NSLocationInRange(clamped, lineRange) || (clamped == ns.length && NSMaxRange(lineRange) == ns.length) {
                currentLineIndex = lineIndex
            }

            guard lineRange.length > 0 else {
                lineIndex += 1
                return
            }

            let lineText = ns.substring(with: lineRange)
            let lineNS = lineText as NSString
            let matches = regex.matches(in: lineText, options: [], range: NSRange(location: 0, length: lineNS.length))
            guard let last = matches.last else {
                lineIndex += 1
                return
            }

            let word = lineNS.substring(with: last.range)
            guard let key = dictionary.rhymeKeys(for: word).first else {
                lineIndex += 1
                return
            }

            endings.append((lineIndex: lineIndex, key: key))
            lineIndex += 1
        }

        guard let currentLineIndex else { return nil }

        let scoped = endings
            .filter { $0.lineIndex <= currentLineIndex }
            .suffix(lookbackLines)

        var counts: [String: Int] = [:]
        for e in scoped {
            counts[e.key, default: 0] += 1
        }

        for e in scoped.reversed() {
            if (counts[e.key] ?? 0) >= 2 {
                return e.key
            }
        }

        // Fall back to current line ending if present.
        return scoped.last(where: { $0.lineIndex == currentLineIndex })?.key
    }

    private static func clusterNearOccurrences(occurrences: [RhymeOccurrence]) -> [RhymeGroup] {
        guard occurrences.count >= 2 else { return [] }

        // Union-find over occurrences, but keep it local: only connect if within
        // the line distance window and above a threshold.
        var parent = Array(occurrences.indices)
        func find(_ i: Int) -> Int {
            var x = i
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a)
            let rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        for i in 0..<occurrences.count {
            for j in (i + 1)..<occurrences.count {
                if abs(occurrences[i].lineIndex - occurrences[j].lineIndex) > maxLineDistance {
                    continue
                }

                let threshold = (occurrences[i].isLineFinalToken && occurrences[j].isLineFinalToken)
                    ? RhymeKey.nearRhymeThreshold
                    : RhymeKey.nearRhymeThresholdInternal

                let sim = RhymeKey.similarity(occurrences[i].rhymeKey, occurrences[j].rhymeKey)
                if sim >= threshold && sim < 1.0 {
                    union(i, j)
                }
            }
        }

        var clusters: [Int: [RhymeOccurrence]] = [:]
        for i in 0..<occurrences.count {
            clusters[find(i), default: []].append(occurrences[i])
        }

        let nearGroups = clusters.values
            .filter { $0.count >= 2 }
            .map { occs -> RhymeGroup in
                let sorted = occs.sorted { $0.range.location < $1.range.location }
                let rep = sorted.first?.rhymeKey ?? occs[0].rhymeKey
                return RhymeGroup(type: .near, rhymeKey: rep, colorIndex: 0, occurrences: sorted)
            }
            .sorted { a, b in
                let aFirst = a.occurrences.first?.range.location ?? Int.max
                let bFirst = b.occurrences.first?.range.location ?? Int.max
                return aFirst < bFirst
            }

        return nearGroups
    }
}
