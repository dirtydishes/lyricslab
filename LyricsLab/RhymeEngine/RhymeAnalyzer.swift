import Foundation

nonisolated enum RhymeAnalyzer {
    private struct LineEnding {
        var lineIndex: Int
        var lineRange: NSRange
        var token: RhymeToken
    }

    nonisolated static func analyze(text: String, dictionary: CMUDictionary) -> RhymeAnalysis {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return .empty }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: "[A-Za-z']+", options: [])
        } catch {
            return .empty
        }

        var endings: [LineEnding] = []
        endings.reserveCapacity(64)

        var lineIndex = 0
        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            defer { lineIndex += 1 }

            guard lineRange.length > 0 else { return }
            let lineText = ns.substring(with: lineRange)
            let lineNS = lineText as NSString
            let lineTextRange = NSRange(location: 0, length: lineNS.length)
            let matches = regex.matches(in: lineText, options: [], range: lineTextRange)
            guard let last = matches.last else { return }

            let word = lineNS.substring(with: last.range)
            guard let key = dictionary.rhymeKeys(for: word).first else { return }

            // Translate the match range (line-local) into full text range.
            let tokenRange = NSRange(location: lineRange.location + last.range.location, length: last.range.length)
            let token = RhymeToken(range: tokenRange, rhymeKey: key)
            endings.append(LineEnding(lineIndex: lineIndex, lineRange: lineRange, token: token))
        }

        let tokens = endings.map { $0.token }

        // 1) Exact end rhyme groups.
        let groupedByKey = Dictionary(grouping: tokens, by: { $0.rhymeKey })
        let repeatedKeys = groupedByKey
            .filter { $0.value.count >= 2 }
            .map { $0.key }

        let orderedEndKeys = repeatedKeys.sorted { a, b in
            let aFirst = groupedByKey[a]?.map { $0.range.location }.min() ?? Int.max
            let bFirst = groupedByKey[b]?.map { $0.range.location }.min() ?? Int.max
            return aFirst < bFirst
        }

        var groups: [RhymeGroup] = []
        groups.reserveCapacity(orderedEndKeys.count + 8)

        var usedRanges: Set<Int> = []
        usedRanges.reserveCapacity(tokens.count)

        for (idx, key) in orderedEndKeys.enumerated() {
            let toks = groupedByKey[key] ?? []
            for t in toks {
                usedRanges.insert(t.range.location)
            }
            groups.append(RhymeGroup(type: .end, rhymeKey: key, colorIndex: idx, tokens: toks))
        }

        // 2) Near rhyme groups: cluster remaining line-ending keys by similarity.
        let remaining = endings
            .map { $0.token }
            .filter { !usedRanges.contains($0.range.location) }

        let nearGroups = clusterNearRhymes(tokens: remaining)
        let startColor = groups.count
        for (offset, g) in nearGroups.enumerated() {
            groups.append(RhymeGroup(type: .near, rhymeKey: g.rhymeKey, colorIndex: startColor + offset, tokens: g.tokens))
        }

        return RhymeAnalysis(groups: groups)
    }

    nonisolated static func inferActiveRhymeKey(text: String, cursor: Int, dictionary: CMUDictionary, lookbackLines: Int = 12) -> String? {
        let ns = text as NSString
        let clamped = max(0, min(cursor, ns.length))
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return nil }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: "[A-Za-z']+", options: [])
        } catch {
            return nil
        }

        var endings: [LineEnding] = []
        endings.reserveCapacity(32)

        var currentLineIndex: Int?
        var lineIndex = 0
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

            let tokenRange = NSRange(location: lineRange.location + last.range.location, length: last.range.length)
            endings.append(LineEnding(lineIndex: lineIndex, lineRange: lineRange, token: RhymeToken(range: tokenRange, rhymeKey: key)))
            lineIndex += 1
        }

        guard let currentLineIndex else {
            return currentLineRhymeKey(text: text, cursor: cursor, dictionary: dictionary)
        }

        let inScope = endings
            .filter { $0.lineIndex <= currentLineIndex }
            .suffix(lookbackLines)

        let keys = inScope.map { $0.token.rhymeKey }
        var counts: [String: Int] = [:]
        for k in keys {
            counts[k, default: 0] += 1
        }

        // Pick the most recent key that repeats in the lookback window.
        for end in inScope.reversed() {
            if (counts[end.token.rhymeKey] ?? 0) >= 2 {
                return end.token.rhymeKey
            }
        }

        return inScope.last(where: { $0.lineIndex == currentLineIndex })?.token.rhymeKey
            ?? currentLineRhymeKey(text: text, cursor: cursor, dictionary: dictionary)
    }

    nonisolated static func currentLineRhymeKey(text: String, cursor: Int, dictionary: CMUDictionary) -> String? {
        let ns = text as NSString
        let clamped = max(0, min(cursor, ns.length))
        let fullRange = NSRange(location: 0, length: ns.length)
        guard fullRange.length > 0 else { return nil }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: "[A-Za-z']+", options: [])
        } catch {
            return nil
        }

        var found: String?

        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, stop in
            guard NSLocationInRange(clamped, lineRange) || (clamped == ns.length && NSMaxRange(lineRange) == ns.length) else {
                return
            }

            let lineText = ns.substring(with: lineRange)
            let matches = regex.matches(in: lineText, options: [], range: NSRange(location: 0, length: (lineText as NSString).length))
            guard let last = matches.last else {
                found = nil
                stop.pointee = true
                return
            }

            let word = (lineText as NSString).substring(with: last.range)
            found = dictionary.rhymeKeys(for: word).first
            stop.pointee = true
        }

        return found
    }

    private static func clusterNearRhymes(tokens: [RhymeToken]) -> [RhymeGroup] {
        guard tokens.count >= 2 else { return [] }

        // Union-find over line-ending tokens (n is small enough for O(n^2)).
        var parent = Array(tokens.indices)
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

        for i in 0..<tokens.count {
            for j in (i + 1)..<tokens.count {
                if RhymeKey.isNearRhyme(tokens[i].rhymeKey, tokens[j].rhymeKey) {
                    union(i, j)
                }
            }
        }

        var clusters: [Int: [RhymeToken]] = [:]
        for i in 0..<tokens.count {
            clusters[find(i), default: []].append(tokens[i])
        }

        let near = clusters.values
            .filter { $0.count >= 2 }
            .map { toks -> RhymeGroup in
                let representative = toks.sorted { $0.range.location < $1.range.location }.first?.rhymeKey ?? toks[0].rhymeKey
                return RhymeGroup(type: .near, rhymeKey: representative, colorIndex: 0, tokens: toks.sorted { $0.range.location < $1.range.location })
            }
            .sorted { a, b in
                let aFirst = a.tokens.map { $0.range.location }.min() ?? Int.max
                let bFirst = b.tokens.map { $0.range.location }.min() ?? Int.max
                return aFirst < bFirst
            }

        return near
    }
}
