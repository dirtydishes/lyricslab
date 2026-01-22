import Foundation

nonisolated enum RhymeAnalyzer {
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

        var tokens: [RhymeToken] = []

        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
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
            tokens.append(RhymeToken(range: tokenRange, rhymeKey: key))
        }

        // Group by rhyme key; keep only groups with repeats.
        let grouped = Dictionary(grouping: tokens, by: { $0.rhymeKey })
        let repeatedKeys = grouped
            .filter { $0.value.count >= 2 }
            .map { $0.key }

        // Deterministic ordering: by first appearance in the text.
        let orderedKeys = repeatedKeys.sorted { a, b in
            let aFirst = grouped[a]?.map { $0.range.location }.min() ?? Int.max
            let bFirst = grouped[b]?.map { $0.range.location }.min() ?? Int.max
            return aFirst < bFirst
        }

        let groups = orderedKeys.map { key in
            RhymeGroup(rhymeKey: key, tokens: grouped[key] ?? [])
        }

        return RhymeAnalysis(groups: groups)
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
}
